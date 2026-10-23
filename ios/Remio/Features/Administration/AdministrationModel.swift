import Foundation
import Network
import Observation
import Security

@MainActor @Observable
final class AdministrationModel {
    private(set) var isChecking = false
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var transferProgress = 0.0
    @ObservationIgnored private var streamCompletion: CheckedContinuation<Data, any Error>?
    @ObservationIgnored private var streamInput = Data()
    @ObservationIgnored private var streamOutput = Data()
    @ObservationIgnored private var inputOffset = 0
    @ObservationIgnored private var localStream: UInt32 = 0
    @ObservationIgnored private var remoteStream: UInt32 = 0
    @ObservationIgnored private var syncReceiving: Bool?
    @ObservationIgnored private var syncDecoder: ADBSyncDecoder?
    @ObservationIgnored private var streamTimeout: Task<Void, Never>?
    private(set) var status = String(localized: "Sin comprobar")
    private(set) var checkedAddress: String?
    private(set) var savedEndpoint: PortalEndpoint?
    private(set) var savedDevices: [SavedADBPortal] = []
    @ObservationIgnored private var nextRetry = Date.distantPast
    @ObservationIgnored private var retryDelay: TimeInterval = 3
    @ObservationIgnored private var requiresManualAuthorization = false
    @ObservationIgnored private var allowsAuthorization = true

    init() {
        if let data = UserDefaults.standard.data(forKey: "remio.adb.devices.v1") {
            savedDevices = (try? JSONDecoder().decode([SavedADBPortal].self, from: data)) ?? []
        }
        if let data = UserDefaults.standard.data(forKey: "remio.adb.endpoint.v1") {
            savedEndpoint = try? JSONDecoder().decode(PortalEndpoint.self, from: data)
            checkedAddress = savedEndpoint?.id
        }
    }

    /// One foreground owner in the app, independent of the selected tab.
    func monitor(fallback: PortalEndpoint?) async {
        // Migrate the previously authorized first version, which did not save its destination.
        if !UserDefaults.standard.bool(forKey: "remio.adb.destination.migrated"), savedEndpoint == nil, ADBIdentity.hasSavedIdentity, let fallback,
           let endpoint = try? PortalEndpoint(host: fallback.host, port: 5555) { save(endpoint) }
        UserDefaults.standard.set(true, forKey: "remio.adb.destination.migrated")
        while !Task.isCancelled {
            if !isConnected, !isChecking, !requiresManualAuthorization, Date() >= nextRetry,
               let endpoint = savedEndpoint {
                check(host: endpoint.host, port: String(endpoint.port), automatic: true)
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }

    private func save(_ endpoint: PortalEndpoint) {
        savedEndpoint = endpoint
        checkedAddress = endpoint.id
        if let data = try? JSONEncoder().encode(endpoint) {
            UserDefaults.standard.set(data, forKey: "remio.adb.endpoint.v1")
        }
    }
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var attempt = UUID()
    @ObservationIgnored private var reachedTCP = false
    @ObservationIgnored private var identity: SecKey?
    @ObservationIgnored private var sentSignature = false
    @ObservationIgnored private var sentPublicKey = false

    func rename(_ device: SavedADBPortal, to name: String) {
        guard let index = savedDevices.firstIndex(where: { $0.id == device.id }) else { return }
        savedDevices[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        persistDevices()
    }

    func remove(_ device: SavedADBPortal) {
        guard !isBusy else { return }
        savedDevices.removeAll { $0.id == device.id }
        if savedEndpoint == device.endpoint {
            cancel(); savedEndpoint = nil; checkedAddress = nil
            UserDefaults.standard.removeObject(forKey: "remio.adb.endpoint.v1")
        }
        persistDevices()
    }

    private func persistDevices() {
        if let data = try? JSONEncoder().encode(savedDevices) { UserDefaults.standard.set(data, forKey: "remio.adb.devices.v1") }
    }

    func cancel() {
        completeStream(.failure(ADBToolError.disconnected))
        attempt = UUID()
        reachedTCP = false
        isConnected = false
        identity = nil
        sentSignature = false
        sentPublicKey = false
        timeout?.cancel()
        timeout = nil
        connection?.cancel()
        connection = nil
        status = String(localized: "Desconectado")
        isChecking = false
    }

    func check(host: String, port: String, automatic: Bool = false) {
        cancel()
        allowsAuthorization = !automatic
        if !automatic { requiresManualAuthorization = false; retryDelay = 3 }
        do {
            guard let number = Int(port), String(number) == port else { throw PortalError.invalidAddress }
            let endpoint = try PortalEndpoint(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: number)
            guard let networkPort = NWEndpoint.Port(rawValue: UInt16(endpoint.port)) else { throw PortalError.invalidAddress }
            save(endpoint)
            status = automatic ? String(localized: "Reconectando ADB…") : String(localized: "Conectando ADB…")
            isChecking = true
            identity = try ADBIdentity.loadOrCreate()
            let id = attempt
            let parameters = NWParameters.tcp
            parameters.prohibitedInterfaceTypes = [.cellular]
            let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: networkPort, using: parameters)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.attempt == id, self.isChecking else { return }
                    switch state {
                    case .ready:
                        self.reachedTCP = true
                        self.status = String(localized: "Puerto abierto · comprobando ADB…")
                        self.sendHello(connection, id: id)
                    case .waiting(let error), .failed(let error):
                        if case .posix(.ECONNREFUSED) = error {
                            self.finish(String(localized: "Puerto cerrado o conexión rechazada"), id: id)
                        } else if case .failed = state {
                            self.finish(String(localized: "No se pudo acceder a esa dirección"), id: id)
                        }
                    default: break
                    }
                }
            }
            armTimeout(id: id, seconds: 8)
            connection.start(queue: .main)
        } catch {
            cancel()
            status = (error as? PortalError) == .keychain ?
                String(localized: "No se pudo acceder a la clave ADB del llavero") : String(localized: "Introduce una IP local y un puerto válido")
            if automatic { requiresManualAuthorization = true }
        }
    }

    private func sendHello(_ connection: NWConnection, id: UUID) {
        connection.send(content: ADBHandshake.hello(), completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self, self.attempt == id, self.isChecking else { return }
                guard error == nil else { self.finish(String(localized: "No se pudo consultar ADB"), id: id); return }
                self.receiveHeader(connection, id: id)
            }
        })
    }

    private func armTimeout(id: UUID, seconds: Int) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.attempt == id else { return }
            let message = self.sentPublicKey ? String(localized: "Autorización pendiente en el Portal · vuelve a conectar") :
                self.reachedTCP ? String(localized: "Puerto abierto · sin respuesta ADB") : String(localized: "No se pudo alcanzar el puerto")
            self.finish(message, id: id)
        }
    }

    private func receiveHeader(_ connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 24, maximumLength: 24) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, self.attempt == id, self.isChecking || self.isConnected else { return }
                guard error == nil, let data, let reply = try? ADBHandshake.response(data) else {
                    self.finish(String(localized: "Conexión ADB cerrada o respuesta inválida"), id: id); return
                }
                if reply.length == 0 {
                    if self.isConnected { self.processStream(reply.command, arg0: reply.arg0, arg1: reply.arg1, payload: Data(), connection: connection, id: id) }
                    else { self.finish(String(localized: "Respuesta ADB vacía"), id: id) }
                    return
                }
                connection.receive(minimumIncompleteLength: reply.length, maximumLength: reply.length) { [weak self] payload, _, _, error in
                    Task { @MainActor in
                        guard let self, self.attempt == id, self.isChecking || self.isConnected else { return }
                        guard error == nil, let payload, payload.count == reply.length,
                              payload.reduce(UInt32(0), { $0 + UInt32($1) }) == reply.checksum else {
                            self.finish(String(localized: "Respuesta ADB incompleta o inválida"), id: id); return
                        }
                        if self.isConnected { self.processStream(reply.command, arg0: reply.arg0, arg1: reply.arg1, payload: payload, connection: connection, id: id) }
                        else { self.process(command: reply.command, payload: payload, connection: connection, id: id) }
                    }
                }
            }
        }
    }

    private func process(command: UInt32, payload: Data, connection: NWConnection, id: UUID) {
        if command == ADBHandshake.connect {
            guard payload.starts(with: Data("device::".utf8)) else {
                finish(String(localized: "El servicio no se identifica como dispositivo ADB"), id: id); return
            }
            timeout?.cancel(); timeout = nil
            isChecking = false
            isConnected = true
            status = String(localized: "ADB conectado")
            if let endpoint = savedEndpoint, !savedDevices.contains(where: { $0.endpoint == endpoint }) {
                savedDevices.append(SavedADBPortal(endpoint: endpoint, name: endpoint.host))
                persistDevices()
            }
            retryDelay = 3
            nextRetry = .distantPast
            requiresManualAuthorization = false
            receiveHeader(connection, id: id)
            return
        }
        do {
            guard let identity else { throw PortalError.keychain }
            let type: UInt32
            let data: Data
            if !sentSignature {
                data = try ADBIdentity.sign(payload, key: identity)
                type = 2
                sentSignature = true
                status = String(localized: "Autenticando ADB…")
            } else if !sentPublicKey {
                guard allowsAuthorization else {
                    requiresManualAuthorization = true
                    finish(String(localized: "ADB requiere autorización · pulsa Conectar ADB"), id: id)
                    return
                }
                data = try ADBIdentity.publicPayload(key: identity)
                type = 3
                sentPublicKey = true
                status = String(localized: "Acepta Remio en la pantalla del Portal")
                armTimeout(id: id, seconds: 90)
            } else {
                finish(String(localized: "Autorización rechazada o pendiente · vuelve a conectar"), id: id); return
            }
            connection.send(content: ADBHandshake.packet(command: ADBHandshake.auth, arg0: type, payload: data),
                            completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self, self.attempt == id, self.isChecking else { return }
                    if error != nil { self.finish(String(localized: "No se pudo enviar la autorización"), id: id) }
                    else { self.receiveHeader(connection, id: id) }
                }
            })
        } catch {
            finish(error is PortalError && (error as? PortalError) == .keychain ?
                   String(localized: "No se pudo acceder a la clave ADB del llavero") : String(localized: "No se pudo preparar la autorización ADB"), id: id)
        }
    }

    /// Single serialized ADB stream; all calls are explicit tool actions.
    func service(_ name: String, input: Data = Data(), syncReceiving: Bool? = nil) async throws -> Data {
        guard isConnected, let connection else { throw ADBToolError.disconnected }
        guard !isBusy else { throw ADBToolError.busy }
        guard !name.contains("\0"), name.utf8.count < 4000, input.count <= ADBTools.limit + 65536 else { throw ADBToolError.tooLarge }
        isBusy = true
        localStream &+= 1
        if localStream == 0 { localStream = 1 }
        remoteStream = 0
        streamInput = input; streamOutput = Data(); inputOffset = 0; transferProgress = 0
        self.syncReceiving = syncReceiving
        syncDecoder = syncReceiving.map { ADBSyncDecoder(receiving: $0) }
        let id = attempt
        let streamID = localStream
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                streamCompletion = continuation
                streamTimeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(120)) } catch { return }
                    guard let self, self.attempt == id, self.localStream == streamID, self.isBusy else { return }
                    self.finish(String(localized: "La operación ADB agotó el tiempo de espera"), id: id)
                }
                sendStream(ADBHandshake.open, arg0: localStream, arg1: 0,
                           payload: Data((name + "\0").utf8), connection: connection, id: id)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.attempt == id, self.localStream == streamID, self.isBusy else { return }
                self.finish(String(localized: "Operación cancelada"), id: id)
            }
        }
    }

    private func sendStream(_ command: UInt32, arg0: UInt32, arg1: UInt32, payload: Data = Data(), connection: NWConnection, id: UUID) {
        connection.send(content: ADBHandshake.packet(command: command, arg0: arg0, arg1: arg1, payload: payload),
                        completion: .contentProcessed { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.finish(String(localized: "Se perdió la conexión ADB"), id: id) }
            }
        })
    }

    private func processStream(_ command: UInt32, arg0: UInt32, arg1: UInt32, payload: Data, connection: NWConnection, id: UUID) {
        defer { if attempt == id, isConnected { receiveHeader(connection, id: id) } }
        guard isBusy, arg1 == localStream else { return }
        if command == ADBHandshake.okay {
            guard remoteStream == 0 || remoteStream == arg0 else { finish(String(localized: "Canal ADB inválido"), id: id); return }
            remoteStream = arg0
            if inputOffset < streamInput.count {
                let end = min(inputOffset + 4096, streamInput.count)
                let bytes = streamInput.subdata(in: inputOffset..<end)
                inputOffset = end
                transferProgress = Double(end) / Double(streamInput.count)
                sendStream(ADBHandshake.write, arg0: localStream, arg1: remoteStream, payload: bytes, connection: connection, id: id)
            }
        } else if command == ADBHandshake.write {
            guard remoteStream == arg0, streamOutput.count + payload.count <= 4 * 1024 * 1024 else {
                finish(String(localized: "Respuesta ADB demasiado grande o canal inválido"), id: id); return
            }
            if syncDecoder == nil { streamOutput.append(payload) }
            sendStream(ADBHandshake.okay, arg0: localStream, arg1: remoteStream, connection: connection, id: id)
            if let syncDecoder {
                do {
                    if let result = try syncDecoder.feed(payload) {
                        sendStream(ADBHandshake.close, arg0: localStream, arg1: remoteStream, connection: connection, id: id)
                        completeStream(.success(result))
                    }
                } catch {
                    sendStream(ADBHandshake.close, arg0: localStream, arg1: remoteStream, connection: connection, id: id)
                    completeStream(.failure(error))
                }
            }
        } else if command == ADBHandshake.close {
            sendStream(ADBHandshake.close, arg0: localStream, arg1: arg0, connection: connection, id: id)
            if syncReceiving != nil { completeStream(.failure(ADBToolError.invalidData)) }
            else { completeStream(.success(streamOutput)) }
        } else { finish(String(localized: "Respuesta ADB inesperada"), id: id) }
    }

    private func completeStream(_ result: Result<Data, any Error>) {
        let completion = streamCompletion
        streamCompletion = nil
        streamTimeout?.cancel(); streamTimeout = nil
        isBusy = false
        syncDecoder = nil
        streamInput = Data(); streamOutput = Data(); inputOffset = 0
        completion?.resume(with: result)
    }

    private func finish(_ result: String, id: UUID) {
        guard attempt == id else { return }
        cancel()
        status = result
        nextRetry = Date().addingTimeInterval(retryDelay)
        retryDelay = min(30, retryDelay * 2)
    }
}
