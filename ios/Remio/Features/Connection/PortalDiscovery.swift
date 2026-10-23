import Foundation
import Network
import Observation

struct NearbyPortal: Identifiable, Sendable {
    let name: String
    let endpoint: PortalEndpoint
    var id: String { endpoint.id }
}

@MainActor @Observable
final class PortalDiscovery {
    private(set) var devices: [NearbyPortal] = []
    private(set) var status = String(localized: "Buscando equipos en tu Wi-Fi…")
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connections: [String: NWConnection] = [:]
    @ObservationIgnored private var generation = UUID()

    func start() {
        guard browser == nil else { return }
        let generation = UUID()
        self.generation = generation
        status = String(localized: "Buscando equipos en tu Wi-Fi…")
        let browser = NWBrowser(for: .bonjour(type: "_immortal-remote._tcp", domain: "local."), using: .tcp)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if case .failed = state { self.status = String(localized: "No se pudo buscar. Comprueba el permiso de red local.") }
                if case .waiting = state { self.status = String(localized: "Comprueba la Wi-Fi y el permiso de red local de Remio.") }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                for result in results { self.resolve(result.endpoint, generation: generation) }
            }
        }
        browser.start(queue: .main)
    }

    func stop() {
        generation = UUID()
        browser?.cancel()
        browser = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        devices = []
    }

    private func resolve(_ service: NWEndpoint, generation: UUID) {
        guard case let .service(name, _, _, _) = service, connections[name] == nil else { return }
        // The first version stores canonical IPv4 destinations. Resolve over IPv4 too,
        // rather than silently dropping the Portal's preferred IPv6 link-local route.
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: service, using: parameters)
        connections[name] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            if case .ready = state {
                let resolved = connection.currentPath?.remoteEndpoint
                connection.cancel() // Resolve only: no HTTP, auth or control sent.
                Task { @MainActor in
                    guard let self, self.generation == generation,
                          case let .hostPort(.ipv4(address), port) = resolved,
                          let endpoint = try? PortalEndpoint(host: address.rawValue.map { String($0) }.joined(separator: "."), port: Int(port.rawValue)) else { return }
                    self.devices.removeAll { $0.id == endpoint.id }
                    self.devices.append(NearbyPortal(name: name, endpoint: endpoint))
                    self.devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    self.status = String(localized: "Selecciona tu Portal para vincularlo.")
                }
            }
        }
        connection.start(queue: .main)
        Task { @MainActor [weak self, weak connection] in
            try? await Task.sleep(for: .seconds(4))
            guard self?.generation == generation else { return }
            connection?.cancel()
        }
    }
}
