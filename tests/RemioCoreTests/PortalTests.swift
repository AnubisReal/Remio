import Foundation
import Testing
import Security
@testable import RemioCore

private struct CapturedRequest: Sendable {
    let method: String
    let path: String
    let authorization: String?
    let body: Data?
}

private actor StubPortal: PortalTransport {
    var requests: [CapturedRequest] = []
    var status = 200
    var customReply: String?
    var cursorFails = false
    var inputFocus: Bool?
    var legacyFocus: Bool?
    var iconReply: Data?

    func configureIcon(_ data: Data) { iconReply = data }

    func configure(status: Int = 200, reply: String? = nil, cursorFails: Bool = false, inputFocus: Bool? = nil, legacyFocus: Bool? = nil) {
        self.status = status; self.customReply = reply; self.cursorFails = cursorFails
        self.inputFocus = inputFocus
        self.legacyFocus = legacyFocus
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        let path = request.url!.path
        requests.append(CapturedRequest(method: request.httpMethod ?? "", path: path,
            authorization: request.value(forHTTPHeaderField: "Authorization"), body: request.httpBody))
        if (path == "/remote/icon" || path == "/remote/art"), let iconReply { return (iconReply, status) }
        if cursorFails, path == "/remote/cursor" {
            return (Data(#"{"ok":false,"error":"no_gestures"}"#.utf8), 503)
        }
        if path == "/remote/input-state" {
            guard let inputFocus else {
                return (Data(#"{"ok":false,"error":"not_found"}"#.utf8), 404)
            }
            return (Data("{\"ok\":true,\"input\":{\"editable\":\(inputFocus)}}".utf8), status)
        }
        if path == "/remote/text", let legacyFocus {
            return (Data("{\"ok\":true,\"applied\":\(legacyFocus)}".utf8), status)
        }
        let reply: String
        if let customReply { reply = customReply }
        else {
            switch path {
            case "/remote/devices": reply = #"{"ok":true,"self":"Portal+ Test","devices":[]}"#
            case "/remote/apps": reply = #"{"ok":true,"apps":[{"label":"Music","packageName":"org.test.music"}]}"#
            case "/remote/nowplaying": reply = #"{"ok":true,"np":{"active":false}}"#
            case "/remote/pair": reply = #"{"ok":true,"name":"Test","token":"0123456789abcdef0123456789abcdef"}"#
            default: reply = #"{"ok":true,"dispatched":true}"#
            }
        }
        return (Data(reply.utf8), status)
    }
}

private final class MemoryStorage: PortalSessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: PortalCredential?
    init(_ credential: PortalCredential? = nil) { self.credential = credential }
    func load() -> PortalCredential? { lock.withLock { credential } }
    func save(_ credential: PortalCredential) { lock.withLock { self.credential = credential } }
    func forget() { lock.withLock { credential = nil } }
}

private func credential() throws -> PortalCredential {
    PortalCredential(endpoint: try PortalEndpoint(host: "192.168.0.132"), name: "Test", token: "0123456789abcdef0123456789abcdef")
}

private func api(_ stub: StubPortal, token: String? = "test-token") throws -> PortalAPI {
    PortalAPI(endpoint: try PortalEndpoint(host: "192.168.0.132"), token: token, transport: stub)
}

@Test(arguments: ["8.8.8.8", "127.0.0.1", "169.254.1.2", "172.32.0.1", "192.168.0.132.evil.com",
                  "https://192.168.0.132:8723", "http://user:secret@192.168.0.132", "http://192.168.0.132/remote/key",
                  "http://192.168.0.132/#pin=123456", "http://192.168.0.132/?token=secret", "192.168.000.132", "2130706433"])
func rejectsUntrustedAddresses(_ address: String) {
    #expect(throws: PortalError.invalidAddress) { try PortalEndpoint(address: address) }
}

@Test(arguments: ["10.0.0.1", "172.16.0.1:8723", "172.31.255.1:9000", "http://192.168.0.132:8723/remote/ui"])
func acceptsPrivateAddresses(_ address: String) throws {
    #expect(try PortalEndpoint(address: address).port > 0)
}

@Test func endpointDecodingRevalidatesDestination() {
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(PortalEndpoint.self, from: Data(#"{"host":"8.8.8.8","port":8723}"#.utf8))
    }
}

@Test func pairingDoesNotSendExistingToken() async throws {
    let stub = StubPortal()
    let reply = try await api(stub).pair(pin: "123456")
    #expect(reply.token?.count == 32)
    let requests = await stub.requests
    #expect(requests.count == 1)
    #expect(requests[0].method == "POST")
    #expect(requests[0].path == "/remote/pair")
    #expect(requests[0].authorization == nil)
}

@Test func malformedPINDoesNotReachNetwork() async throws {
    let stub = StubPortal()
    await #expect(throws: PortalError.invalidPIN) { try await api(stub).pair(pin: "１２３４５６") }
    #expect(await stub.requests.isEmpty)
}

@Test func missingCredentialDoesNotReachNetwork() async throws {
    let stub = StubPortal()
    await #expect(throws: PortalError.unauthorized) { try await api(stub, token: nil).devices() }
    #expect(await stub.requests.isEmpty)
}

@Test func unauthorizedCommandIsNeverRetried() async throws {
    let stub = StubPortal()
    await stub.configure(status: 401, reply: #"{"ok":false,"error":"unauthorized"}"#)
    await #expect(throws: PortalError.unauthorized) { try await api(stub).send(.tap) }
    let requests = await stub.requests
    #expect(requests.count == 1)
    #expect(requests[0].method == "POST")
    #expect(requests[0].authorization == "Bearer test-token")
}

@Test func responseFlagsAreNotSilentlyIgnored() async throws {
    let stub = StubPortal()
    await stub.configure(reply: #"{"ok":true,"applied":false}"#)
    await #expect(throws: PortalError.noFocusedField) { try await api(stub).send(.text("Hola")) }
    await stub.configure(reply: #"{"ok":true,"dispatched":false}"#)
    await #expect(throws: PortalError.notDispatched) { try await api(stub).send(.tap) }
    await stub.configure(status: 503, reply: #"{"ok":false,"error":"no_gestures"}"#)
    await #expect(throws: PortalError.unavailableInput) { try await api(stub).send(.cursor(1, 2)) }
}

@Test func redirectIsNotSuccess() async throws {
    let stub = StubPortal()
    await stub.configure(status: 302, reply: "")
    await #expect(throws: PortalError.server(302)) { try await api(stub).devices() }
    #expect(await stub.requests.count == 1)
}

@Test func invalidMovementDoesNotReachNetwork() async throws {
    let stub = StubPortal()
    await #expect(throws: PortalError.incompatible) { try await api(stub).send(.cursor(.nan, 0)) }
    await #expect(throws: PortalError.incompatible) { try await api(stub).send(.seek(-1)) }
    #expect(await stub.requests.isEmpty)
}

@MainActor private func waitUntil(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw PortalError.busy }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@Test @MainActor func coalescesMovementBeforeClick() async throws {
    let stub = StubPortal()
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.isConnected }
    model.move(dx: 10, dy: 5)
    model.move(dx: 4, dy: 2)
    model.enqueue(.tap)
    try await waitUntil { await stub.requests.contains { $0.path == "/remote/tap" } }
    let commands = await stub.requests.filter { $0.method == "POST" }
    #expect(commands.map(\.path) == ["/remote/cursor", "/remote/tap"])
    let delta = try #require(JSONSerialization.jsonObject(with: commands[0].body!) as? [String: Double])
    #expect(abs(delta["dx"]! - 30.8) < 0.001)
    #expect(abs(delta["dy"]! - 15.4) < 0.001)
}

@Test @MainActor func unavailableGesturesDiscardQueuedClick() async throws {
    let stub = StubPortal()
    await stub.configure(cursorFails: true)
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.isConnected }
    model.move(dx: 10, dy: 5)
    model.enqueue(.tap)
    try await waitUntil { model.inputUnavailable }
    #expect(await stub.requests.allSatisfy { $0.path != "/remote/tap" })
    #expect(!model.canUseTouchpad)
}

@Test @MainActor func backgroundDiscardsPendingActions() async throws {
    let stub = StubPortal()
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.isConnected }
    model.move(dx: 10, dy: 5)
    model.enqueue(.tap)
    monitor.cancel()
    model.suspend()
    try await Task.sleep(for: .milliseconds(70))
    #expect(await stub.requests.allSatisfy { $0.method == "GET" })
    #expect(!model.isConnected)
}

@Test @MainActor func pairingPersistsLocallyWithoutSendingControl() async throws {
    let stub = StubPortal()
    let storage = MemoryStorage()
    let model = RemoteModel(transport: stub, storage: storage)
    await model.pair(address: "192.168.0.132:8723", pin: "123456")
    #expect(!model.needsPairing)
    #expect(storage.load()?.endpoint.host == "192.168.0.132")
    #expect(await stub.requests.map(\.path) == ["/remote/pair"])
}

@Test func nativeEditUsesAppendAndBackspaceWithoutSet() async throws {
    let stub = StubPortal()
    _ = try await api(stub).send(.editText(PortalTextEdit(previous: "hola", next: "holá")))
    let requests = await stub.requests
    #expect(requests.count == 2)
    let bodies = try requests.map { try JSONDecoder().decode([String: String].self, from: $0.body!) }
    #expect(bodies.map { $0["mode"] } == ["backspace", "append"])
    #expect(bodies[1]["text"] == "á")
}

@Test @MainActor func fastTypingAndDeleteCoalesceWithoutDroppingCharacters() async throws {
    let stub = StubPortal()
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.isConnected }
    #expect(model.editText(PortalTextEdit(previous: "", next: "h")))
    #expect(model.editText(PortalTextEdit(previous: "h", next: "ho")))
    #expect(model.editText(PortalTextEdit(previous: "ho", next: "hol")))
    #expect(model.editText(PortalTextEdit(previous: "hol", next: "hola")))
    #expect(model.editText(PortalTextEdit(previous: "hola", next: "hol")))
    try await waitUntil { await stub.requests.contains { $0.path == "/remote/text" } }
    let writes = await stub.requests.filter { $0.path == "/remote/text" }
    #expect(writes.count == 1)
    let body = try JSONDecoder().decode([String: String].self, from: writes[0].body!)
    #expect(body["mode"] == "append")
    #expect(body["text"] == "hol")
}

@Test @MainActor func focusChangesCloseKeyboardContextBeforeMoreTyping() async throws {
    let stub = StubPortal()
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.isConnected }
    let oldContext = model.keyboardContext
    model.enqueue(.tap)
    #expect(model.keyboardContext != oldContext)
}

@Test func failedDeleteStopsTheRestOfTheTextEdit() async throws {
    let stub = StubPortal()
    await stub.configure(reply: #"{"ok":true,"applied":false}"#)
    await #expect(throws: PortalError.noFocusedField) {
        try await api(stub).send(.editText(PortalTextEdit(previous: "abc", next: "x")))
    }
    #expect(await stub.requests.count == 1)
}

@Test @MainActor func disabledAutomaticKeyboardNeverProbesAfterTap() async throws {
    let stub = StubPortal()
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.isConnected }
    model.automaticKeyboardEnabled = false
    model.enqueue(.tap)
    try await waitUntil { !model.isSending }
    #expect(await stub.requests.allSatisfy { $0.path != "/remote/text" })
}

@Test func emptyAppendCannotBeUsedToProbeFocus() async throws {
    let stub = StubPortal()
    await #expect(throws: PortalError.incompatible) { try await api(stub).send(.appendText("")) }
    #expect(await stub.requests.isEmpty)
}

@Test func focusQueryIsAuthenticatedReadWithoutText() async throws {
    let stub = StubPortal()
    await stub.configure(inputFocus: true)
    #expect(try await api(stub).inputState().editable)
    let requests = await stub.requests
    #expect(requests.count == 1)
    #expect(requests[0].path == "/remote/input-state")
    #expect(requests[0].method == "GET")
    #expect(requests[0].body == nil)
    #expect(requests[0].authorization == "Bearer test-token")
}

@Test @MainActor func automaticKeyboardClearsAfterReadOnlyFocus() async throws {
    let stub = StubPortal()
    await stub.configure(inputFocus: true)
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.keyboardDetectionAvailable == true }
    let original = model.keyboardDetected
    model.enqueue(.tap)
    try await waitUntil { model.keyboardDetected != original }
    let requests = await stub.requests
    #expect(requests.filter { $0.method == "POST" }.map(\.path) == ["/remote/tap", "/remote/text"])
    #expect(requests.filter { $0.path == "/remote/input-state" }.count == 2)
    #expect(model.message == nil)
}

@Test @MainActor func nonEditableFieldDoesNotOpenOrShowError() async throws {
    let stub = StubPortal()
    await stub.configure(inputFocus: false)
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.keyboardDetectionAvailable == true }
    let original = model.keyboardDetected
    model.enqueue(.tap)
    try await waitUntil { await stub.requests.filter { $0.path == "/remote/input-state" }.count == 2 }
    try await waitUntil { !model.isSending }
    #expect(model.keyboardDetected == original)
    #expect(model.message == nil)
    #expect(await stub.requests.allSatisfy { $0.path != "/remote/text" })
}

@Test @MainActor func legacyAgentOpensKeyboardAfterTap() async throws {
    let stub = StubPortal()
    await stub.configure(legacyFocus: true)
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.keyboardDetectionAvailable == false }
    let original = model.keyboardDetected
    model.enqueue(.tap)
    try await waitUntil { model.keyboardDetected != original }
    let requests = await stub.requests.filter { $0.method == "POST" }
    #expect(requests.map(\.path) == ["/remote/tap", "/remote/text", "/remote/text"])
    let body = try #require(requests.last?.body)
    let payload = try JSONDecoder().decode([String: String].self, from: body)
    #expect(payload == ["mode": "clear", "text": ""])
    #expect(model.message == nil)
}

@Test @MainActor func legacyNonEditableFieldRemainsSilent() async throws {
    let stub = StubPortal()
    await stub.configure(legacyFocus: false)
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.keyboardDetectionAvailable == false }
    let original = model.keyboardDetected
    model.enqueue(.tap)
    try await waitUntil { await stub.requests.contains { $0.path == "/remote/text" } }
    try await waitUntil { !model.isSending }
    #expect(model.keyboardDetected == original)
    #expect(model.message == nil)
}

@Test @MainActor func firstEditReplacesHintAndLaterEditsAppend() async throws {
    let stub = StubPortal()
    await stub.configure(legacyFocus: true)
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.keyboardDetectionAvailable == false }
    let original = model.keyboardDetected
    model.enqueue(.tap)
    try await waitUntil { model.keyboardDetected != original }
    #expect(model.editText(PortalTextEdit(previous: "", next: "r")))
    try await waitUntil { await stub.requests.filter { $0.path == "/remote/text" }.count == 3 }
    try await waitUntil { !model.isSending }
    #expect(model.editText(PortalTextEdit(previous: "r", next: "re")))
    try await waitUntil { await stub.requests.filter { $0.path == "/remote/text" }.count == 4 }
    try await waitUntil { !model.isSending }
    let requests = await stub.requests.filter { $0.path == "/remote/text" }
    let payloads = try requests.map { try JSONDecoder().decode([String: String].self, from: #require($0.body)) }
    #expect(payloads == [["mode": "append", "text": ""], ["mode": "clear", "text": ""],
                         ["mode": "set", "text": "r"], ["mode": "append", "text": "e"]])
}

@Test @MainActor func emptyLocalDeleteNeverTouchesRemoteAndRetypingReplacesHint() async throws {
    let stub = StubPortal()
    await stub.configure(legacyFocus: true)
    let model = RemoteModel(transport: stub, storage: MemoryStorage(try credential()))
    let monitor = Task { await model.monitor() }
    defer { monitor.cancel(); model.suspend() }
    try await waitUntil { model.keyboardDetectionAvailable == false }
    let original = model.keyboardDetected
    model.enqueue(.tap)
    try await waitUntil { model.keyboardDetected != original }
    #expect(model.editText(PortalTextEdit(previous: "", next: "hola")))
    try await waitUntil { await stub.requests.filter { $0.path == "/remote/text" }.count == 3 }
    try await waitUntil { !model.isSending }
    #expect(model.editText(PortalTextEdit(previous: "hola", next: "")))
    try await waitUntil { await stub.requests.filter { $0.path == "/remote/text" }.count == 7 }
    try await waitUntil { !model.isSending }
    let count = await stub.requests.count
    for _ in 0..<10 { #expect(model.deleteFromKeyboard()) }
    await Task.yield()
    #expect(await stub.requests.count == count)
    #expect(!model.isSending)
    #expect(model.editText(PortalTextEdit(previous: "", next: "x")))
    try await waitUntil { await stub.requests.filter { $0.path == "/remote/text" }.count == 8 }
    let request = try #require(await stub.requests.last)
    let payload = try JSONDecoder().decode([String: String].self, from: #require(request.body))
    #expect(payload == ["mode": "set", "text": "x"])
}

@Test func appIconsUsePublicLocalReadAndRejectUnboundedImages() async throws {
    let stub = StubPortal()
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQ0AAAAASUVORK5CYII="))
    await stub.configureIcon(png)
    #expect(try await api(stub).appIcon(package: "org.test.music") == png)
    let request = try #require(await stub.requests.first)
    #expect(request.path == "/remote/icon")
    #expect(request.method == "GET")
    #expect(request.authorization == nil)
    #expect(request.body == nil)
    var oversized = png
    oversized.replaceSubrange(16..<20, with: [0, 0, 8, 0])
    await stub.configureIcon(oversized)
    await #expect(throws: PortalError.oversizedResponse) { try await api(stub).appIcon(package: "org.test.music") }
    await #expect(throws: PortalError.incompatible) { try await api(stub).appIcon(package: "org.test/?token=x") }
    #expect(await stub.requests.count == 2)
}

@Test func mediaTimesHandleHoursUnknownAndInvalidValues() {
    #expect(PortalMedia.timeLabel(0) == "0:00")
    #expect(PortalMedia.timeLabel(125_999) == "2:05")
    #expect(PortalMedia.timeLabel(3_661_000) == "1:01:01")
    #expect(PortalMedia.timeLabel(nil) == "--:--")
    #expect(PortalMedia.timeLabel(-1) == "--:--")
    #expect(PortalMedia.timeLabel(.infinity) == "--:--")
    #expect(PortalMedia.timeLabel(.nan) == "--:--")
}

@Test func artworkUsesLocalPublicEndpointAndMetadataRemainsBackwardCompatible() async throws {
    let stub = StubPortal()
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQ0AAAAASUVORK5CYII="))
    await stub.configureIcon(png)
    #expect(try await api(stub).artwork() == png)
    let request = try #require(await stub.requests.first)
    #expect(request.path == "/remote/art")
    #expect(request.method == "GET")
    #expect(request.authorization == nil)
    let full = try JSONDecoder().decode(PortalMedia.self, from: Data(#"{"active":true,"title":"Track","artist":"Artist","album":"Album","durationMs":240000,"positionMs":65000,"playing":true,"hasArt":true,"artVersion":42,"source":"org.test.player"}"#.utf8))
    #expect(full.hasArt == true)
    #expect(full.artVersion == 42)
    #expect(full.source == "org.test.player")
    #expect(PortalMedia.timeLabel(full.positionMs) == "1:05")
    let inactive = try JSONDecoder().decode(PortalMedia.self, from: Data(#"{"active":false}"#.utf8))
    #expect(inactive.hasArt == nil)
    #expect(full.artworkKey != inactive.artworkKey)
}

@Test func mediaCounterAdvancesFromRemotePositionAndStopsOnPause() {
    let sample = Date(timeIntervalSince1970: 1000)
    let later = sample.addingTimeInterval(4)
    #expect(PortalMedia.interpolatedPosition(base: 600_000, sampledAt: sample, now: later,
                                            playing: true, duration: 1_180_000) == 604_000)
    #expect(PortalMedia.interpolatedPosition(base: 604_000, sampledAt: later, now: later.addingTimeInterval(10),
                                            playing: false, duration: 1_180_000) == 604_000)
    #expect(PortalMedia.interpolatedPosition(base: 1_179_000, sampledAt: sample, now: later,
                                            playing: true, duration: 1_180_000) == 1_180_000)
    #expect(PortalMedia.interpolatedPosition(base: 600_000, sampledAt: later, now: sample,
                                            playing: true, duration: nil) == 600_000)
}

@Test func adbHandshakeIsReadOnlyAndBoundsResponses() throws {
    let hello = ADBHandshake.hello()
    #expect(hello.count == 31)
    #expect(String(data: hello.suffix(7), encoding: .utf8) == "host::\0")
    let connect = try ADBHandshake.response(Data(hello.prefix(24)))
    #expect(connect.command == ADBHandshake.connect)
    var auth = Data()
    for word: UInt32 in [ADBHandshake.auth, 1, 0, 20, 0, ADBHandshake.auth ^ 0xffffffff] {
        var little = word.littleEndian
        withUnsafeBytes(of: &little) { auth.append(contentsOf: $0) }
    }
    #expect(try ADBHandshake.response(auth).command == ADBHandshake.auth)
    var invalid = auth
    invalid[20] ^= 1
    #expect(throws: PortalError.incompatible) { try ADBHandshake.response(invalid) }
    #expect(throws: PortalError.incompatible) { try ADBHandshake.response(Data()) }
    auth[12] = 255
    auth[13] = 255
    #expect(throws: PortalError.incompatible) { try ADBHandshake.response(auth) }
}

@Test func adbPublicKeyEncodingMatchesMontgomeryReference() throws {
    // Synthetic n = 2^2048 - 159: 2^4096 mod n = 159^2 = 25281.
    var modulus = Array(repeating: UInt8(255), count: 256)
    modulus[255] = 97
    var der = Data([0x30, 0x82, 1, 10, 2, 0x82, 1, 1, 0])
    der.append(contentsOf: modulus)
    der.append(contentsOf: [2, 3, 1, 0, 1])
    let blob = try ADBIdentity.androidPublicKey(der: der)
    #expect(blob.count == 524)
    let bytes = Array(blob)
    func word(_ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
    #expect(word(0) == 64)
    #expect(word(4) &* word(8) == UInt32.max)
    #expect(word(264) == 25281)
    #expect(bytes[268..<520].allSatisfy { $0 == 0 })
    #expect(word(520) == 65537)
    #expect(throws: PortalError.incompatible) { try ADBIdentity.androidPublicKey(der: Data([0x30])) }
}

@Test func adbChallengeSignsDigestAndPublicPayloadIsAndroidCompatible() throws {
    var error: Unmanaged<CFError>?
    let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                    kSecAttrKeySizeInBits as String: 2048]
    let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
    let challenge = Data(repeating: 42, count: 20)
    let signature = try ADBIdentity.sign(challenge, key: key)
    let publicKey = try #require(SecKeyCopyPublicKey(key))
    #expect(signature.count == 256)
    #expect(SecKeyVerifySignature(publicKey, .rsaSignatureDigestPKCS1v15SHA1, challenge as CFData,
                                 signature as CFData, &error))
    let payload = try ADBIdentity.publicPayload(key: key)
    #expect(payload.last == 0)
    let text = try #require(String(data: payload, encoding: .utf8))
    let base64 = try #require(text.split(separator: " ").first)
    #expect(Data(base64Encoded: String(base64))?.count == 524)
    #expect(text.hasSuffix(" Remio@iOS\0"))
    #expect(throws: PortalError.incompatible) { try ADBIdentity.sign(Data(), key: key) }
    let packet = ADBHandshake.packet(command: ADBHandshake.auth, arg0: 2, payload: signature)
    #expect(packet.count == 280)
}

@Test func adbToolCommandsAndSyncFramesAreBounded() throws {
    #expect(try ADBTools.package("com.example.app") == "com.example.app")
    #expect(throws: ADBToolError.self) { try ADBTools.package("com.foo;reboot") }
    #expect(try ADBTools.quote("a'b") == "'a'\\''b'")
    #expect(throws: ADBToolError.self) { try ADBTools.quote("x\ny") }
    let data = ADBTools.sync("DATA", Data("hello".utf8))
    #expect(try ADBTools.syncResult(data, receiving: true) == nil)
    #expect(try ADBTools.syncResult(data + ADBTools.sync("DONE", Data(), value: 0), receiving: true) == Data("hello".utf8))
    #expect(try ADBTools.syncResult(ADBTools.sync("OKAY", Data()), receiving: false) == Data())
    #expect(throws: ADBToolError.self) { try ADBTools.syncResult(ADBTools.sync("FAIL", Data("denied".utf8)), receiving: false) }
}

@Test func toolkitArchiveValidatesRoundTripChecksumAndPaths() throws {
    let entries = ["manifest.json": Data("{}".utf8), "apps/com.example.test/base.apk": Data([80,75,3,4,1,2])]
    let zip = try ToolkitArchive.encode(entries)
    #expect(try ToolkitArchive.decode(zip) == entries)
    #expect(ToolkitArchive.crc(Data("123456789".utf8)) == 0xcbf43926)
    #expect(throws: ADBToolError.self) { try ToolkitArchive.encode(["../bad": Data([1])]) }
    #expect(!ToolkitArchive.safe("/sdcard/a"))
    #expect(!ToolkitArchive.safe("apps/../a"))
    var corrupt = zip
    corrupt[30 + "apps/com.example.test/base.apk".utf8.count] ^= 1
    #expect(throws: ADBToolError.self) { try ToolkitArchive.decode(corrupt) }
}

@Test func toolkitArchiveReadsAndroidStyleDeflatedZipAndFragmentedSync() throws {
    let encoded = "UEsDBBQAAAAIAGQsV11oPTxFFwAAABUAAAANAAAAbWFuaWZlc3QuanNvbqtWKkktLlGyUkrOzy0oSi0uTk1RqgUAUEsBAhQDFAAAAAgAZCxXXWg9PEUXAAAAFQAAAA0AAAAAAAAAAAAAAIABAAAAAG1hbmlmZXN0Lmpzb25QSwUGAAAAAAEAAQA7AAAAQgAAAAAA"
    let zip = try #require(Data(base64Encoded: encoded))
    #expect(try ToolkitArchive.decode(zip)["manifest.json"] == Data(#"{"test":"compressed"}"#.utf8))
    let decoder = ADBSyncDecoder(receiving: true)
    let bytes = ADBTools.sync("DATA", Data("abcdef".utf8)) + ADBTools.sync("DONE", Data(), value: 0)
    for byte in bytes.dropLast() { #expect(try decoder.feed(Data([byte])) == nil) }
    #expect(try decoder.feed(Data([try #require(bytes.last)])) == Data("abcdef".utf8))
}

@Test func adbStreamsCarryLocalAndRemoteIdentifiers() throws {
    let packet = ADBHandshake.packet(command: ADBHandshake.write, arg0: 41, arg1: 93, payload: Data("hello".utf8))
    let header = try ADBHandshake.response(Data(packet.prefix(24)))
    #expect(header.command == ADBHandshake.write)
    #expect(header.arg0 == 41)
    #expect(header.arg1 == 93)
    #expect(header.length == 5)
    #expect(header.checksum == Data("hello".utf8).reduce(UInt32(0)) { $0 + UInt32($1) })
    let ack = ADBHandshake.packet(command: ADBHandshake.okay, arg0: 93, arg1: 41, payload: Data())
    #expect(try ADBHandshake.response(ack).length == 0)
}
