import Foundation
import Observation

@MainActor @Observable
final class RemoteModel {
    enum ConnectionState { case unpaired, reconnecting, connected, paused, offline }
    private(set) var connectionState: ConnectionState = .unpaired
    /// Presentation state is independent of whether commands can currently be sent.
    var shouldShowConnectionCard: Bool { needsPairing || connectionState == .offline }
    private(set) var deviceName = String(localized: "Tu Portal")
    private(set) var endpoint: PortalEndpoint?
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var isPairing = false
    private(set) var needsPairing = true
    private(set) var media: PortalMedia?
    private(set) var mediaUpdatedAt = Date()
    private(set) var apps: [PortalApp] = []
    private(set) var isSending = false
    private(set) var inputUnavailable = false
    var message: String?
    var showConnection = false
    var feedback = String(localized: "Desliza para mover · toca para seleccionar")
    private(set) var keyboardContext = UUID()
    var automaticKeyboardEnabled = true
    private(set) var keyboardDetectionAvailable: Bool?
    private(set) var keyboardDetected = UUID()

    @ObservationIgnored private var credential: PortalCredential?
    @ObservationIgnored private let transport: any PortalTransport
    @ObservationIgnored private let storage: any PortalSessionStorage
    @ObservationIgnored private var pending: [PortalCommand] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var replaceFirstKeyboardEdit = false

    init(transport: any PortalTransport = HTTPPortalTransport(), storage: any PortalSessionStorage = KeychainPortalSessionStorage()) {
        self.transport = transport
        self.storage = storage
        do {
            credential = try storage.load()
            endpoint = credential?.endpoint
            deviceName = credential?.name ?? String(localized: "Tu Portal")
            needsPairing = credential == nil
            connectionState = credential == nil ? .unpaired : .reconnecting
        } catch { message = PortalError.keychain.localizedDescription }
    }

    var status: String {
        if isPairing { return String(localized: "Vinculando…") }
        if isConnecting { return String(localized: "Conectando…") }
        if isConnected { return String(localized: "Conectado") }
        if connectionState == .paused { return String(localized: "En pausa") }
        if connectionState == .reconnecting { return String(localized: "Reconectando…") }
        return needsPairing ? String(localized: "Sin vincular") : String(localized: "Sin conexión")
    }

    var canUseTouchpad: Bool { isConnected && !inputUnavailable }
    private var api: PortalAPI? {
        guard let credential else { return nil }
        return PortalAPI(endpoint: credential.endpoint, token: credential.token, transport: transport)
    }

    /// Read-only reconnection. The app owns polling across tabs while in the foreground.
    func monitor() async {
        isActive = true
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: .seconds(isConnected ? 3 : 8)) }
            catch { break }
        }
    }

    func suspend() {
        isActive = false
        dropPending()
        isConnected = false
        if connectionState == .connected || connectionState == .reconnecting { connectionState = .paused }
        media = nil
    }

    private func dropPending() {
        replaceFirstKeyboardEdit = false
        keyboardContext = UUID()
        generation = UUID()
        worker?.cancel()
        worker = nil
        pending.removeAll()
        isSending = false
        isConnecting = false
    }

    func refresh() async {
        guard !Task.isCancelled, let api, !needsPairing, !isConnecting, !isPairing else { return }
        let generation = generation
        if !isConnected, connectionState != .offline { connectionState = .reconnecting }
        isConnecting = !isConnected
        defer { if self.generation == generation { isConnecting = false } }
        do {
            if !isConnected {
                let device = try await api.devices()
                guard !Task.isCancelled, self.generation == generation else { return }
                if let name = device.deviceName, !name.isEmpty { deviceName = name }
                else { deviceName = credential?.name ?? "Portal" }
                let list = try await api.apps()
                guard let apps = list.apps else { throw PortalError.incompatible }
                guard !Task.isCancelled, self.generation == generation else { return }
                self.apps = apps.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                isConnected = true
                connectionState = .connected
                inputUnavailable = false
                feedback = String(localized: "Desliza para mover · toca para seleccionar")
            }
            if keyboardDetectionAvailable == nil {
                await checkKeyboardCapability(api: api, generation: generation)
                guard self.generation == generation, !Task.isCancelled else { return }
            }
            let playing = try await api.nowPlaying()
            guard let media = playing.np else { throw PortalError.incompatible }
            guard !Task.isCancelled, self.generation == generation else { return }
            self.media = media
            mediaUpdatedAt = .now

        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, self.generation == generation else { return }
            handle(error, passive: true)
            if !isConnected, !needsPairing { connectionState = .offline }
        }
    }

    func pair(address: String, pin: String) async {
        guard !isPairing else { return }
        message = nil
        isPairing = true
        defer { isPairing = false }
        do {
            let endpoint = try PortalEndpoint(address: address)
            let api = PortalAPI(endpoint: endpoint, token: nil, transport: transport)
            let reply = try await api.pair(pin: pin)
            guard let token = reply.token, token.utf8.count == 32,
                  token.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw PortalError.incompatible }
            let saved = PortalCredential(endpoint: endpoint, name: reply.name ?? "Portal", token: token)
            try storage.save(saved)
            dropPending()
            credential = saved
            keyboardDetectionAvailable = nil
            self.endpoint = endpoint
            deviceName = saved.name
            needsPairing = false
            connectionState = .reconnecting
            isConnected = false
            inputUnavailable = false
            showConnection = false
        } catch is CancellationError { }
        catch {
            message = (error as? PortalError) == .unauthorized
                ? String(localized: "El PIN no coincide o ha caducado. Comprueba el código que muestra Immortal.")
                : readable(error)
        }
        // refresh() also checks isPairing; monitor will reconnect after this completes.
    }

    func forget() {
        do {
            try storage.forget() // Local only; does not revoke or alter anything on the Portal.
            suspend()
            credential = nil
            endpoint = nil
            isConnected = false
            needsPairing = true
            connectionState = .unpaired
            media = nil
            apps = []
            deviceName = String(localized: "Tu Portal")
            feedback = String(localized: "Vincula un Portal para usar el mando")
        } catch { message = PortalError.keychain.localizedDescription }
    }

    func artworkData() async -> Data? {
        guard isConnected, let media, media.active, media.hasArt == true, let api else { return nil }
        let current = generation
        let key = media.artworkKey
        do {
            let data = try await api.artwork()
            guard !Task.isCancelled, generation == current, self.media?.artworkKey == key, isConnected else { return nil }
            return data
        } catch { return nil }
    }

    func appIconData(for app: PortalApp) async -> Data? {
        guard isConnected, let api else { return nil }
        let current = generation
        do {
            let data = try await api.appIcon(package: app.packageName)
            guard !Task.isCancelled, generation == current, isConnected else { return nil }
            return data
        } catch { return nil } // A missing icon must not interrupt remote control.
    }

    func move(dx: Double, dy: Double) {
        guard canUseTouchpad, dx.isFinite, dy.isFinite else { return }
        // One finger delta is relative, matching Immortal's sensitivity.
        enqueue(.cursor(max(-400, min(400, dx * 2.2)), max(-400, min(400, dy * 2.2))))
    }

    func enqueue(_ command: PortalCommand) {
        _ = accept(command)
    }

    func editText(_ edit: PortalTextEdit) -> Bool {
        guard !edit.isEmpty else { return true }
        do { try edit.validate() }
        catch { message = String(localized: "La edición es demasiado grande. Escribe o borra un fragmento más pequeño."); return false }
        if replaceFirstKeyboardEdit {
            let accepted = accept(.text(edit.next))
            if accepted { replaceFirstKeyboardEdit = false }
            return accepted
        }
        let accepted = accept(.editText(edit))
        // Once our local text is empty, the next insertion must replace any remote hint.
        if accepted, edit.next.isEmpty { replaceFirstKeyboardEdit = true }
        return accepted
    }

    // UIKit calls this when the local field is already empty. Never edit an unknown remote prefix.
    func deleteFromKeyboard() -> Bool { true }

    private func accept(_ command: PortalCommand) -> Bool {
        guard isActive, isConnected else { return false }
        if case .cursor(let dx, let dy) = command, case .cursor(let x, let y) = pending.last {
            pending[pending.count - 1] = .cursor(max(-1200, min(1200, x + dx)), max(-1200, min(1200, y + dy)))
        } else if case .editText(let edit) = command,
                  case .editText(let last) = pending.last,
                  last.next.utf16.elementsEqual(edit.previous.utf16) {
            let merged = PortalTextEdit(previous: last.previous, next: edit.next)
            if merged.isEmpty { pending.removeLast() }
            else {
                do { try merged.validate() }
                catch { return false }
                pending[pending.count - 1] = .editText(merged)
            }
        } else {
            guard pending.count < 16 else {
                message = String(localized: "El Portal está ocupado. Espera un momento antes de seguir escribiendo.")
                return false
            }
            pending.append(command)
        }
        switch command {
        case .tap, .back, .home, .recentApps, .screensaver, .launch:
            replaceFirstKeyboardEdit = false
            keyboardContext = UUID()
        default: break
        }
        guard worker == nil else { return true }
        let generation = generation
        worker = Task { [weak self] in await self?.drain(generation: generation) }
        return true
    }

    private func drain(generation: UUID) async {
        isSending = true
        defer {
            if self.generation == generation { worker = nil; isSending = false }
        }
        while !pending.isEmpty, !Task.isCancelled, self.generation == generation, let api {
            do {
                // Coalesce pointer events for 35 ms. Tap/nav remain in the same ordered queue.
                if case .cursor = pending.first { try await Task.sleep(for: .milliseconds(35)) }
                try Task.checkCancellation()
                guard self.generation == generation, !pending.isEmpty else { return }
                let command = pending.removeFirst()
                let context = keyboardContext
                _ = try await api.send(command)
                guard self.generation == generation, !Task.isCancelled else { return }
                if command == .tap, automaticKeyboardEnabled {
                    await detectKeyboard(api: api, generation: generation, context: context)
                }
                if case .text = command { feedback = String(localized: "Texto enviado al campo seleccionado") }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, self.generation == generation else { return }
                pending.removeAll() // No replay after failures, reconnect or background.
                handle(error, passive: false)
                keyboardContext = UUID()
                return
            }
        }
    }

    private func checkKeyboardCapability(api: PortalAPI, generation: UUID) async {
        do {
            _ = try await api.inputState()
            if self.generation == generation, !Task.isCancelled { keyboardDetectionAvailable = true }
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, self.generation == generation else { return }
            switch error as? PortalError {
            case .server(404), .server(405), .incompatible: keyboardDetectionAvailable = false
            case .unauthorized, .inaccessible: handle(error, passive: true)
            default: keyboardDetectionAvailable = false
            }
        }
    }

    private func detectKeyboard(api: PortalAPI, generation: UUID, context: UUID) async {
        do {
            try await Task.sleep(for: .milliseconds(180))
            guard automaticKeyboardEnabled, self.generation == generation,
                  keyboardContext == context, pending.isEmpty, isActive else { return }
            let editable: Bool
            if keyboardDetectionAvailable == true { editable = try await api.inputState().editable }
            else { editable = try await api.legacyEditableField() }
            guard !Task.isCancelled, automaticKeyboardEnabled, self.generation == generation,
                  keyboardContext == context, pending.isEmpty, isActive else { return }
            guard editable else { return }
            // Owner-authorized fresh-field trial. Serialize clear before opening iOS input.
            try await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, automaticKeyboardEnabled, self.generation == generation,
                  keyboardContext == context, pending.isEmpty, isActive else { return }
            _ = try await api.send(.clearText)
            guard !Task.isCancelled, automaticKeyboardEnabled, self.generation == generation,
                  keyboardContext == context, pending.isEmpty, isActive else { return }
            replaceFirstKeyboardEdit = true
            keyboardDetected = UUID()
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, self.generation == generation else { return }
            switch error as? PortalError {
            case .server(404), .server(405), .incompatible: keyboardDetectionAvailable = false
            case .unauthorized, .inaccessible: handle(error, passive: true)
            default: break
            }
        }
    }

    private func handle(_ error: any Error, passive: Bool) {
        if let error = error as? PortalError {
            switch error {
            case .unauthorized:
                dropPending()
                needsPairing = true
                connectionState = .unpaired
                isConnected = false
                media = nil
                apps = []
            case .unavailableInput: inputUnavailable = true
            case .inaccessible:
                dropPending()
                connectionState = .offline
                isConnected = false
                media = nil
            default: break
            }
        }
        feedback = readable(error)
        if !passive { message = readable(error) }
    }

    private func readable(_ error: any Error) -> String {
        (error as? PortalError)?.localizedDescription ?? PortalError.inaccessible.localizedDescription
    }
}
