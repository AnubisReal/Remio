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
            Button(String(localized: "Cargar apps del Portal"), systemImage: "arrow.clockwise") {
                tools.perform(.backupApps) { try await tools.refreshPackages() }
            }.disabled(!ready)
            HStack {
                Button(String(localized: "Seleccionar todas")) { selected = Set(tools.packages.map(\.packageName)) }
                Spacer()
                Button(String(localized: "Ninguna")) { selected.removeAll() }
            }.disabled(tools.busy)
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
            Button(String(localized: "Crear copia · \(selected.count) apps"), systemImage: "square.and.arrow.up") {
                let packages = selected
                tools.perform(.createBackup) {
                    document = PortalBackupDocument(data: try await tools.createBackup(packages: packages))
                    export = true
                }
            }.disabled(!ready)
            if selected.isEmpty { Text(String(localized: "Se creará una copia solo de ajustes.")).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text(String(localized: "Nueva copia")) } footer: {
            Text(String(localized: "Incluye APK y ajustes seleccionados del sistema. No incluye datos privados de las apps, fotos ni sesiones."))
        }
        Section {
            Button(String(localized: "Abrir copia ZIP"), systemImage: "doc.zipper") { importing = true }.disabled(tools.busy)
            if let preview {
                LabeledContent(String(localized: "Modelo"), value: preview.device.model)
                LabeledContent(String(localized: "Creada"), value: Date(timeIntervalSince1970: Double(preview.createdAt) / 1000).formatted(date: .abbreviated, time: .shortened))
                LabeledContent("SDK", value: preview.device.sdk)
                LabeledContent(String(localized: "Aplicaciones"), value: String(preview.apps.count))
                LabeledContent(String(localized: "Ajustes"), value: String(preview.settings.count))
                Toggle(String(localized: "Restaurar también ajustes"), isOn: $restoreSettings)
                Button(String(localized: "Restaurar copia"), role: .destructive) { confirmRestore = true }
                    .disabled(!ready || (preview.apps.isEmpty && !restoreSettings))
            }
        } header: { Text(String(localized: "Restaurar")) }
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
                tools.perform(.validateBackup, requiresPortal: false) {
                    let (decoded, manifest) = try await Task.detached {
                        let decoded = try ToolkitArchive.decode(data)
                        return (decoded, try ToolkitBackup.inspect(decoded))
                    }.value
                    entries = decoded; preview = manifest; restoreSettings = false
                }
            } catch { tools.error = error.localizedDescription }
        }
        .confirmationDialog(String(localized: "¿Restaurar esta copia en el Portal?"), isPresented: $confirmRestore, titleVisibility: .visible) {
            Button(String(localized: "Restaurar"), role: .destructive) {
                guard let entries else { return }
                let settings = restoreSettings
                tools.perform(.restoreBackup) { try await tools.restoreBackup(entries, settings: settings) }
            }
        } message: {
            Text(String(localized: "Las apps incompatibles pueden fallar. La restauración se detiene tras tres fallos consecutivos. Si alguna app falla, no se aplican los ajustes."))
            Text(restoreSettings ? String(localized: "Instalará las apps y modificará los ajustes incluidos. Debe coincidir el modelo y la versión de Android.") : String(localized: "Instalará las apps de la copia. No restaurará ajustes del sistema."))
        }
    }
    private var ready: Bool { tools.adb.isConnected && !tools.busy }
}
