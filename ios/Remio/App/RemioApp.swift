import SwiftUI

@main
struct RemioApp: App {
    @State private var remote = RemoteModel()
    @State private var selectedTab = 0
    @State private var icons = AppIconStore()
    @State private var administration = AdministrationModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("Mando", systemImage: "cursorarrow.motionlines", value: 0) { RemoteView() }
                Tab("Herramientas", systemImage: "square.grid.2x2", value: 1) { AdministrationView() }
                Tab("Ajustes", systemImage: "gear", value: 2) { SettingsView() }
            }
            .tint(RemioTheme.accent)
            .preferredColorScheme(.dark)
            .environment(remote)
            .environment(icons)
            .environment(administration)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await remote.monitor()
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await administration.monitor(fallback: remote.endpoint)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { remote.suspend() }
                if phase == .background { administration.cancel() }
            }
            .sheet(isPresented: $remote.showConnection) { ConnectionView().environment(remote).environment(administration) }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectHidden(true, for: .top)
            #if DEBUG && targetEnvironment(simulator)
            .task {
                if ProcessInfo.processInfo.environment["REMIO_TOOLS_PREVIEW"] == "1" { selectedTab = 1 }
                if ProcessInfo.processInfo.arguments.contains("--keychain-self-test") { keychainSelfTest() }
                if ProcessInfo.processInfo.environment["REMIO_CONNECTION_PREVIEW"] == "1" { remote.showConnection = true }
            }
            .onChange(of: administration.status) { _, status in
                if ProcessInfo.processInfo.environment["REMIO_ADB_DIAGNOSTIC"] == "1",
                   let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    try? status.write(to: folder.appendingPathComponent("adb-state.txt"), atomically: true, encoding: .utf8)
                }
            }
            #endif
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Opt-in integration check in the real app sandbox, using an isolated temporary account.
    /// Does not use or modify the Portal's session, or send any network request.
    private func keychainSelfTest() {
        let account = "self-test-\(UUID().uuidString)"
        var result: String
        do {
            defer { try? PortalVault.forget(account: account) }
            guard try PortalVault.load(account: account) == nil else { throw PortalError.keychain }
            let endpoint = try PortalEndpoint(host: "192.168.0.1")
            let original = PortalCredential(endpoint: endpoint, name: "Local test", token: "synthetic-test-token")
            try PortalVault.save(original, account: account)
            guard try PortalVault.load(account: account)?.token == original.token else { throw PortalError.keychain }
            let updated = PortalCredential(endpoint: endpoint, name: "Updated test", token: "synthetic-updated-token")
            try PortalVault.save(updated, account: account)
            guard try PortalVault.load(account: account)?.token == updated.token else { throw PortalError.keychain }
            try PortalVault.forget(account: account)
            guard try PortalVault.load(account: account) == nil else { throw PortalError.keychain }
            result = "PASS: Keychain empty/read/create/update/delete in signed simulator app."
        } catch { result = "FAIL: \(error.localizedDescription)" }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? result.write(to: documents.appendingPathComponent("keychain-self-test.txt"), atomically: true, encoding: .utf8)
        }
    }
    #endif
}
