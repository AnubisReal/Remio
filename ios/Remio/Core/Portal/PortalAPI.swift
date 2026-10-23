import Foundation

struct PortalApp: Decodable, Sendable, Identifiable {
    let label: String
    let packageName: String
    var id: String { packageName }
}

struct PortalMedia: Decodable, Sendable, Equatable {
    let active: Bool
    let title: String?
    let artist: String?
    let durationMs: Double?
    let positionMs: Double?
    let playing: Bool?
    let album: String?
    let source: String?
    let hasArt: Bool?
    let artVersion: Int?

    var artworkKey: String { "\(active)/\(hasArt == true)/\(artVersion ?? 0)/\(title ?? "")/\(artist ?? "")/\(album ?? "")" }

    /// Smooth progression from a remote sample; assumes 1× because the API omits speed.
    static func interpolatedPosition(base: Double, sampledAt: Date, now: Date, playing: Bool, duration: Double?) -> Double {
        let elapsed = playing ? max(0, now.timeIntervalSince(sampledAt)) * 1000 : 0
        let position = max(0, base + elapsed)
        if let duration, duration.isFinite, duration > 0 { return min(duration, position) }
        return position
    }

    static func timeLabel(_ milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite, milliseconds >= 0, milliseconds < 1e12 else { return "--:--" }
        let seconds = Int(milliseconds / 1000)
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct PortalInputState: Decodable, Sendable {
    let editable: Bool
}

struct PortalReply: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let token: String?
    let name: String?
    let deviceName: String?
    let apps: [PortalApp]?
    let np: PortalMedia?
    let applied: Bool?
    let dispatched: Bool?
    let input: PortalInputState?
    enum CodingKeys: String, CodingKey {
        case ok, error, token, name, apps, np, applied, dispatched, input
        case deviceName = "self"
    }
}

enum PortalCommand: Sendable, Equatable {
    case cursor(Double, Double), tap, back, home, recentApps, screensaver
    case scrollUp, scrollDown, text(String), backspace
    case clearText, appendText(String), editText(PortalTextEdit)
    case playPause, previous, next, volumeUp, volumeDown, mute, seek(Double), launch(String)

    var route: String {
        switch self {
        case .cursor: "cursor"
        case .tap: "tap"
        case .back, .home, .recentApps, .screensaver: "key"
        case .scrollUp, .scrollDown: "scroll"
        case .text, .clearText, .backspace, .appendText, .editText: "text"
        case .playPause, .previous, .next, .seek: "media"
        case .volumeUp, .volumeDown, .mute: "volume"
        case .launch: "launch"
        }
    }

    func body() throws -> Data {
        let values: [String: Any]
        switch self {
        case .cursor(let dx, let dy):
            guard dx.isFinite, dy.isFinite else { throw PortalError.incompatible }
            values = ["dx": dx, "dy": dy]
        case .tap: values = [:]
        case .back: values = ["action": "back"]
        case .home: values = ["action": "home"]
        case .recentApps: values = ["action": "apps"]
        case .screensaver: values = ["action": "screensaver"]
        case .scrollUp: values = ["dir": "up"]
        case .scrollDown: values = ["dir": "down"]
        case .text(let text):
            guard text.utf8.count <= 8192 else { throw PortalError.oversizedResponse }
            values = ["mode": "set", "text": text]
        case .clearText: values = ["mode": "clear", "text": ""]
        case .backspace: values = ["mode": "backspace", "text": ""]
        case .appendText(let text):
            guard !text.isEmpty else { throw PortalError.incompatible }
            guard text.utf8.count <= 8192 else { throw PortalError.oversizedResponse }
            values = ["mode": "append", "text": text]
        case .editText: throw PortalError.incompatible // Expanded serially in send(_:).
        case .playPause: values = ["action": "playpause"]
        case .previous: values = ["action": "prev"]
        case .next: values = ["action": "next"]
        case .volumeUp: values = ["dir": "up"]
        case .volumeDown: values = ["dir": "down"]
        case .mute: values = ["dir": "mute"]
        case .seek(let ms):
            guard ms.isFinite, ms >= 0 else { throw PortalError.incompatible }
            values = ["action": "seek", "positionMs": ms]
        case .launch(let package): values = ["packageName": package]
        }
        return try JSONSerialization.data(withJSONObject: values, options: .sortedKeys)
    }
}

protocol PortalTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor HTTPPortalTransport: PortalTransport {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        config.allowsCellularAccess = false
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw PortalError.incompatible }
            guard response.expectedContentLength <= 1_048_576 else { throw PortalError.oversizedResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_048_576 else { throw PortalError.oversizedResponse }
                data.append(byte)
            }
            return (data, response.statusCode)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as PortalError { throw error }
        catch { throw PortalError.inaccessible }
    }
}

/// A closed set of remote-control routes. No fleet, provisioning, config or preset APIs.
struct PortalAPI: Sendable {
    let endpoint: PortalEndpoint
    let token: String?
    let transport: any PortalTransport

    func pair(pin: String) async throws -> PortalReply {
        guard pin.count == 6, pin.utf8.allSatisfy({ (48...57).contains($0) }) else { throw PortalError.invalidPIN }
        let body = try JSONEncoder().encode(["pin": pin])
        return try await request("pair", method: "POST", body: body, authenticated: false)
    }

    func devices() async throws -> PortalReply { try await request("devices") }
    func apps() async throws -> PortalReply { try await request("apps") }
    /// Public PNG endpoint; credentials never appear in image URLs or headers.
    func appIcon(package: String) async throws -> Data {
        guard !package.isEmpty, package.utf8.count <= 255,
              package.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 46 || $0 == 95 }) else {
            throw PortalError.incompatible
        }
        var components = URLComponents(url: endpoint.baseURL.appendingPathComponent("remote/icon"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "pkg", value: package)]
        guard let url = components.url else { throw PortalError.incompatible }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("image/png", forHTTPHeaderField: "Accept")
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard status == 200 else { throw PortalError.server(status) }
        return try validatedPNG(data, maximumDimension: 1024)
    }

    func artwork() async throws -> Data {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("remote/art"))
        request.httpMethod = "GET"
        request.setValue("image/png", forHTTPHeaderField: "Accept")
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard status == 200 else { throw PortalError.server(status) }
        return try validatedPNG(data, maximumDimension: 2048)
    }

    private func validatedPNG(_ data: Data, maximumDimension: UInt32) throws -> Data {
        // Bound dimensions before UIKit decodes device-supplied images.
        guard data.count >= 24, data.count <= 1_048_576,
              data.prefix(8).elementsEqual([137, 80, 78, 71, 13, 10, 26, 10]),
              data[12..<16].elementsEqual([73, 72, 68, 82]) else { throw PortalError.incompatible }
        let width = data[16..<20].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let height = data[20..<24].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard (1...maximumDimension).contains(width), (1...maximumDimension).contains(height) else { throw PortalError.oversizedResponse }
        return data
    }

    func nowPlaying() async throws -> PortalReply { try await request("nowplaying") }

    /// Capability and focus lookup for compatible agents. Never falls back to writing.
    func inputState() async throws -> PortalInputState {
        guard let state = try await request("input-state").input else { throw PortalError.incompatible }
        return state
    }

    /// Legacy compatibility explicitly requested by the owner. This is a writing
    /// heuristic: Immortal may reapply hint text as content. It does NOT return text.
    func legacyEditableField() async throws -> Bool {
        let body = try JSONEncoder().encode(["mode": "append", "text": ""])
        do { return try await request("text", method: "POST", body: body).applied == true }
        catch PortalError.noFocusedField { return false }
    }

    func send(_ command: PortalCommand) async throws -> PortalReply {
        if case .editText(let edit) = command {
            try edit.validate()
            var last: PortalReply?
            for _ in 0..<edit.deletedUTF16Count {
                try Task.checkCancellation()
                last = try await send(.backspace)
            }
            if !edit.appendedText.isEmpty { last = try await send(.appendText(edit.appendedText)) }
            guard let last else { throw PortalError.incompatible }
            return last
        }
        return try await request(command.route, method: "POST", body: command.body())
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         authenticated: Bool = true) async throws -> PortalReply {
        try Task.checkCancellation()
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("remote/\(path)"))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let token, !token.isEmpty, !token.contains("\r"), !token.contains("\n") else { throw PortalError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw PortalError.unauthorized }
        let reply = try? JSONDecoder().decode(PortalReply.self, from: data)
        if reply?.error == "no_gestures" || reply?.error == "no_accessibility" { throw PortalError.unavailableInput }
        guard (200..<300).contains(status) else { throw PortalError.server(status) }
        guard let reply, reply.ok else { throw PortalError.incompatible }
        if reply.applied == false { throw PortalError.noFocusedField }
        if reply.dispatched == false { throw PortalError.notDispatched }
        return reply
    }
}
