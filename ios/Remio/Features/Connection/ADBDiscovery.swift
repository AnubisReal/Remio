import Foundation
import Network
import Observation
import Darwin

/// Explicit, bounded, unauthenticated ADB discovery. No shell or public keys during scanning.
@MainActor @Observable
final class ADBDiscovery {
    private(set) var hosts: [String] = []
    private(set) var running = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var message: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(port: Int, excluding connected: PortalEndpoint?) {
        guard !running else { return }
        guard (1...65535).contains(port), let network = Self.wifiNetwork(),
              let addresses = try? ADBTools.scanHosts(address: network.0, mask: network.1) else {
            message = String(localized: "Conecta el iPhone a una red Wi-Fi privada para buscar ADB."); return
        }
        hosts = []; completed = 0; total = addresses.count; message = nil; running = true
        task = Task {
            defer { running = false; task = nil }
            for start in stride(from: 0, to: addresses.count, by: 12) {
                guard !Task.isCancelled else { return }
                let batch = Array(addresses[start..<min(start + 12, addresses.count)])
                await withTaskGroup(of: String?.self) { group in
                    for host in batch {
                        if connected?.host == host && connected?.port == port { completed += 1; hosts.append(host); continue }
                        group.addTask { await Self.probe(host: host, port: port) }
                    }
                    for await result in group {
                        guard !Task.isCancelled else { group.cancelAll(); return }
                        completed += 1
                        if let result { hosts.append(result); hosts.sort() }
                    }
                }
            }
            if hosts.isEmpty { message = String(localized: "No se encontraron servicios ADB. Comprueba el puerto o introduce la IP.") }
        }
    }

    func stop() { task?.cancel() }

    nonisolated private static func probe(host: String, port: Int) async -> String? {
        let probe = await ADBDiscoveryProbe(host: host, port: port)
        return await probe.run() ? host : nil
    }

    private static func wifiNetwork() -> (String, String)? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let item = current.pointee
            guard String(cString: item.ifa_name) == "en0", let addr = item.ifa_addr, let mask = item.ifa_netmask,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            func text(_ value: UnsafeMutablePointer<sockaddr>) -> String? {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(value, socklen_t(value.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
                return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            if let address = text(addr), let netmask = text(mask) { return (address, netmask) }
        }
        return nil
    }
}

@MainActor
private final class ADBDiscoveryProbe {
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeout: Task<Void, Never>?

    init(host: String, port: Int) {
        let parameters = NWParameters.tcp
        parameters.prohibitedInterfaceTypes = [.cellular]
        parameters.requiredInterfaceType = .wifi
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: parameters)
    }

    func run() async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(false); return }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(1000)) } catch { return }
                    self?.finish(false)
                }
                connection.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, self.continuation != nil else { return }
                        switch state {
                        case .ready: self.hello()
                        case .failed, .cancelled: self.finish(false)
                        default: break
                        }
                    }
                }
                connection.start(queue: .main)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(false) } }
    }

    private func hello() {
        connection.send(content: ADBHandshake.hello(), completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self, self.continuation != nil else { return }
                if error != nil { self.finish(false); return }
                self.connection.receive(minimumIncompleteLength: 24, maximumLength: 24) { [weak self] data, _, _, error in
                    Task { @MainActor in
                        guard let self, self.continuation != nil else { return }
                        guard error == nil, let data, let header = try? ADBHandshake.response(data),
                              header.command == ADBHandshake.auth || header.command == ADBHandshake.connect,
                              header.length > 0 else { self.finish(false); return }
                        self.connection.receive(minimumIncompleteLength: header.length, maximumLength: header.length) { [weak self] payload, _, _, error in
                            Task { @MainActor in
                                guard let self else { return }
                                let valid = error == nil && payload?.count == header.length && payload?.reduce(UInt32(0), { $0 + UInt32($1) }) == header.checksum
                                self.finish(valid)
                            }
                        }
                    }
                }
            }
        })
    }

    private func finish(_ result: Bool) {
        guard let continuation else { return }
        self.continuation = nil; timeout?.cancel(); timeout = nil
        connection.stateUpdateHandler = nil; connection.cancel()
        continuation.resume(returning: result)
    }
}
