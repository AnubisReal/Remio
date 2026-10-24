import SwiftUI
import UniformTypeIdentifiers

struct APKProfile: Codable, Identifiable {
    let id: UUID
    let name: String
    let files: [String]
}

struct APKProfilesView: View {
    @Bindable var tools: ToolkitModel
    @State private var profiles: [APKProfile] = []
    @State private var importing = false
    @State private var urls: [URL] = []
    @State private var name = ""
    @State private var naming = false
    @State private var selected: APKProfile?
    @State private var confirmApply = false
    @State private var confirmDelete = false

    private var root: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("APKProfiles", isDirectory: true) }
    var body: some View {
        Section {
            Button(String(localized: "Crear lote de APK"), systemImage: "plus") { importing = true }.disabled(tools.busy)
            ForEach(profiles) { profile in
                Menu {
                    Button(String(localized: "Instalar lote"), systemImage: "square.and.arrow.down") { selected = profile; confirmApply = true }
                        .disabled(!tools.adb.isConnected || tools.busy)
                    Button(String(localized: "Eliminar lote del iPhone"), systemImage: "trash", role: .destructive) { selected = profile; confirmDelete = true }.disabled(tools.busy)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name).foregroundStyle(.primary)
                            Text("\(profile.files.count) APK").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "ellipsis")
                    }
                }
            }
        } footer: { Text(String(localized: "Guarda varios APK como un lote para instalarlos juntos.")) }
        .onAppear { load() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "apk") ?? .data], allowsMultipleSelection: true) { result in
            do { urls = try result.get(); guard !urls.isEmpty, urls.count <= 30 else { throw ADBToolError.invalidData }; name = ""; naming = true }
            catch { tools.error = error.localizedDescription }
        }
        .alert(String(localized: "Nombre del lote"), isPresented: $naming) {
            TextField(String(localized: "Nombre"), text: $name)
            Button(String(localized: "Guardar")) { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(localized: "Cancelar"), role: .cancel) { urls = [] }
        }
        .confirmationDialog(String(localized: "¿Instalar todos los APK del lote?"), isPresented: $confirmApply, titleVisibility: .visible) {
            Button(String(localized: "Instalar lote")) {
                guard let selected else { return }
                tools.perform(.installBatch(selected.name)) {
                    let files = try selected.files.map { file -> URL in
                        guard !file.contains("/"), file.hasSuffix(".apk") else { throw ADBToolError.invalidData }
                        return root.appendingPathComponent(selected.id.uuidString).appendingPathComponent(file)
                    }
                    try await tools.installBatch(files)
                }
            }
        }
        .confirmationDialog(String(localized: "¿Eliminar este lote del iPhone?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "Eliminar lote"), role: .destructive) {
                guard let selected else { return }
                do {
                    try FileManager.default.removeItem(at: root.appendingPathComponent(selected.id.uuidString))
                    profiles.removeAll { $0.id == selected.id }; persist()
                } catch { tools.error = error.localizedDescription }
            }
        } message: { Text(String(localized: "No desinstala las apps del Portal.")) }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "remio.apk.profiles"),
              let values = try? JSONDecoder().decode([APKProfile].self, from: data) else { return }
        profiles = values
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "remio.apk.profiles") }
    }
    private func save() {
        let id = UUID(), destination = root.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            var files: [String] = []
            var total = 0
            for (index, url) in urls.enumerated() {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                total += size
                guard size > 0, total <= ADBTools.limit else { throw ADBToolError.tooLarge }
                let handle = try FileHandle(forReadingFrom: url)
                let signature = try handle.read(upToCount: 4)
                try handle.close()
                guard signature == Data([80,75,3,4]) else { throw ADBToolError.invalidData }
                let file = "\(index).apk"
                try FileManager.default.copyItem(at: url, to: destination.appendingPathComponent(file))
                files.append(file)
            }
            profiles.append(APKProfile(id: id, name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64)), files: files))
            persist(); urls = []
        } catch { try? FileManager.default.removeItem(at: destination); tools.error = error.localizedDescription }
    }
}
