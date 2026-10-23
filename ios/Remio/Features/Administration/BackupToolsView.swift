import SwiftUI
import UniformTypeIdentifiers

struct PortalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ADBToolError.invalidData }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupToolsView: View {
    @Bindable var tools: ToolkitModel
    @State private var selected: Set<String> = []
    @State private var document: PortalBackupDocument?
    @State private var export = false
    @State private var importing = false
    @State private var entries: [String: Data]?
    @State private var preview: ToolkitBackup?
    @State private var confirmRestore = false
    @State private var restoreSettings = false

    var body: some View {
        Section {
            Button("Cargar apps del Portal", systemImage: "arrow.clockwise") {
                tools.perform("Consultar apps para copia") { try await tools.refreshPackages() }
            }.disabled(!ready)
            ForEach(tools.packages) { app in
                Button {
                    if selected.contains(app.packageName) { selected.remove(app.packageName) } else { selected.insert(app.packageName) }
                } label: {
                    HStack {
                        Text(app.packageName).font(.footnote).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: selected.contains(app.packageName) ? "checkmark.circle.fill" : "circle")
                    }
                }.disabled(tools.busy)
            }
            Button("Crear copia · \(selected.count) apps", systemImage: "square.and.arrow.up") {
                let packages = selected
                tools.perform("Crear copia de seguridad") {
                    document = PortalBackupDocument(data: try await tools.createBackup(packages: packages))
                    export = true
                }
            }.disabled(!ready || selected.isEmpty)
        } header: { Text("Nueva copia") } footer: {
            Text("Incluye APK y ajustes seleccionados del sistema. No incluye datos privados de las apps, fotos ni sesiones.")
        }
        Section {
            Button("Abrir copia ZIP", systemImage: "doc.zipper") { importing = true }.disabled(tools.busy)
            if let preview {
                LabeledContent("Modelo", value: preview.device.model)
                LabeledContent("Aplicaciones", value: String(preview.apps.count))
                LabeledContent("Ajustes", value: String(preview.settings.count))
                Toggle("Restaurar también ajustes", isOn: $restoreSettings)
                Button("Restaurar copia", role: .destructive) { confirmRestore = true }.disabled(!ready)
            }
        } header: { Text("Restaurar") }
        .fileExporter(isPresented: $export, document: document, contentType: .zip,
                      defaultFilename: "Remio-Portal-\(Date().formatted(.iso8601.year().month().day()))") { result in
            if case .failure(let error) = result { tools.error = error.localizedDescription }
            document = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= ToolkitArchive.maxBytes else { throw ADBToolError.tooLarge }
                let data = try Data(contentsOf: url)
                tools.perform("Validar copia ZIP", requiresPortal: false) {
                    let decoded = try await Task.detached { try ToolkitArchive.decode(data) }.value
                    let manifest = try ToolkitBackup.inspect(decoded)
                    entries = decoded; preview = manifest; restoreSettings = false
                }
            } catch { tools.error = error.localizedDescription }
        }
        .confirmationDialog("¿Restaurar esta copia en el Portal?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restaurar", role: .destructive) {
                guard let entries else { return }
                let settings = restoreSettings
                tools.perform("Restaurar copia de seguridad") { try await tools.restoreBackup(entries, settings: settings) }
            }
        } message: {
            Text(restoreSettings ? "Instalará las apps y modificará los ajustes incluidos. Debe coincidir el modelo y la versión de Android." : "Instalará las apps de la copia. No restaurará ajustes del sistema.")
        }
    }
    private var ready: Bool { tools.adb.isConnected && !tools.busy }
}
