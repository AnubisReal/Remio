import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AdministrationView: View {
    @Environment(RemoteModel.self) private var remote
    @Environment(AdministrationModel.self) private var administration
    @State private var toolkit: ToolkitModel?

    var body: some View {
        Group {
            if let toolkit { ToolkitView(tools: toolkit) }
            else { ProgressView().task { toolkit = ToolkitModel(adb: administration) } }
        }
        .environment(remote)
    }
}

private enum ToolPage: String, CaseIterable, Identifiable, Hashable {
    case devices = "Dispositivos", apps = "Aplicaciones", profiles = "Lotes de APK", photos = "Fotos", backups = "Copias", device = "Información del Portal", updates = "Actualizaciones", history = "Historial"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .devices: "display.2"
        case .apps: "square.stack.3d.up"
        case .profiles: "square.stack"
        case .photos: "photo.on.rectangle.angled"
        case .backups: "externaldrive"
        case .device: "display"
        case .updates: "arrow.triangle.2.circlepath"
        case .history: "clock.arrow.circlepath"
        }
    }
    var detail: String {
        switch self {
        case .devices: "Conexiones y equipos guardados"
        case .apps: "Gestión de APK"
        case .profiles: "Agrupar instalaciones"
        case .photos: "Fototeca y Archivos"
        case .backups: "Guardar y restaurar"
        case .device: "Android, memoria y almacenamiento"
        case .updates: "Gestionar actualizaciones del sistema"
        case .history: "Actividad de las herramientas"
        }
    }
}

private struct ToolkitView: View {
    @Environment(RemoteModel.self) private var remote
    @Bindable var tools: ToolkitModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    toolGroup("Contenido", pages: [.apps, .photos])
                    toolGroup("Organización", pages: [.profiles, .backups])
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Equipo").font(.headline)
                        VStack(spacing: 0) {
                            ForEach([ToolPage.devices, .device, .updates, .history]) { page in
                                NavigationLink(value: page) {
                                    HStack(spacing: 14) {
                                        Image(systemName: page.symbol).font(.system(size: 20)).frame(width: 28)
                                        Text(page.rawValue).font(.body)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(16).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                if page != .history { Divider().padding(.leading, 58) }
                            }
                        }
                        .background(RemioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }
            .background(RemioTheme.background)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("Herramientas")
            .navigationDestination(for: ToolPage.self) { page in
                ToolDetail(page: page, tools: tools)
            }
            #if DEBUG && targetEnvironment(simulator)
            .task(id: tools.adb.isConnected) {
                if tools.adb.isConnected, ProcessInfo.processInfo.environment["REMIO_TOOLS_PREVIEW"] == "1" {
                    tools.perform("Verificar consultas ADB") {
                        try await tools.refreshInfo()
                        try await tools.refreshPackages()
                        let result = "PASS: info=\(tools.information.count), apps=\(tools.packages.count)"
                        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            try result.write(to: directory.appendingPathComponent("tools-read-test.txt"), atomically: true, encoding: .utf8)
                        }
                    }
                }
            }
            #endif
            .safeAreaInset(edge: .bottom) {
                if tools.busy {
                    HStack(spacing: 12) { ProgressView(); Text(tools.progress).font(.footnote); Spacer() }
                        .padding().background(.regularMaterial)
                }
            }
            .alert("Herramientas", isPresented: Binding(get: { tools.error != nil }, set: { if !$0 { tools.error = nil } })) {
                Button("Aceptar", role: .cancel) { tools.error = nil }
            } message: { Text(tools.error ?? "") }
        }
    }

    private func toolGroup(_ title: String, pages: [ToolPage]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(pages) { page in
                    NavigationLink(value: page) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: page.symbol).font(.system(size: 44, weight: .regular))
                                .frame(height: 54)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(page.rawValue).font(.headline)
                                Text(page.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
                        .padding(16)
                        .background(RemioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                        .contentShape(RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

}

private struct ToolDetail: View {
    let page: ToolPage
    @Bindable var tools: ToolkitModel
    @Environment(RemoteModel.self) private var remote
    @State private var importFiles = false
    @State private var selectingAPK = true
    @State private var selectedAPK: URL?
    @State private var confirmInstall = false
    @State private var selectedPackage: PortalPackage?
    @State private var details = ""
    @State private var confirmDelete = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var confirmPhotos = false
    @State private var imageFiles: [URL] = []
    @State private var confirmImageFiles = false
    @State private var changeUpdates = false
    @State private var blockUpdates = false
    @State private var search = ""

    var body: some View {
        List {
            if page != .history, !tools.adb.isConnected {
                Section { Button("Conectar Portal") { remote.showConnection = true } }
            }
            switch page {
            case .devices: SavedPortalsView(adb: tools.adb)
            case .apps: apps
            case .profiles: APKProfilesView(tools: tools)
            case .photos: photoSection
            case .device:
                Section {
                    ForEach(tools.information.keys.sorted(), id: \.self) { key in LabeledContent(key, value: tools.information[key] ?? "—") }
                    Button("Actualizar información", systemImage: "arrow.clockwise") { refresh() }.disabled(!ready)
                }
            case .updates: updates
            case .history:
                Section {
                    ForEach(tools.history) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: entry.success ? "checkmark.circle" : "exclamationmark.circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.action)
                                Text(entry.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if tools.history.isEmpty { Text("Todavía no hay actividad").foregroundStyle(.secondary) }
                    else { Button("Borrar historial", role: .destructive) { tools.clearHistory() } }
                }
            case .backups:
                BackupToolsView(tools: tools)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(page.rawValue).navigationBarTitleDisplayMode(.inline)
        .task(id: tools.adb.isConnected) {
            // Let the native push animation finish before publishing loading state.
            guard tools.adb.isConnected else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            switch page {
            case .apps: if tools.packages.isEmpty { refresh() }
            case .device: if tools.information.isEmpty { refresh() }
            case .updates: if tools.otaPackages.isEmpty { refresh() }
            default: break
            }
        }
        .fileImporter(isPresented: $importFiles,
                      allowedContentTypes: selectingAPK ? [UTType(filenameExtension: "apk") ?? .data] : [.image],
                      allowsMultipleSelection: !selectingAPK) { result in
            do {
                let urls = try result.get()
                if selectingAPK {
                    guard let url = urls.first else { return }
                    guard url.pathExtension.lowercased() == "apk" else { throw ADBToolError.refused("Selecciona un archivo APK.") }
                    selectedAPK = url
                    confirmInstall = true
                } else {
                    guard urls.count <= 30 else { throw ADBToolError.refused("Selecciona un máximo de 30 imágenes.") }
                    imageFiles = urls
                    confirmImageFiles = !urls.isEmpty
                }
            } catch { tools.error = error.localizedDescription }
        }
        .confirmationDialog("¿Enviar las imágenes seleccionadas?", isPresented: $confirmImageFiles, titleVisibility: .visible) {
            Button("Enviar \(imageFiles.count) imágenes") {
                let files = imageFiles
                tools.perform("Enviar imágenes desde Archivos") {
                    for (index, url) in files.enumerated() {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= ADBTools.limit else { throw ADBToolError.tooLarge }
                        try await tools.uploadPhoto(Data(contentsOf: url, options: .mappedIfSafe), extension: url.pathExtension.lowercased())
                        tools.setProgress("Enviando imagen \(index + 1) de \(files.count)")
                    }
                    imageFiles = []
                }
            }
            Button("Cancelar", role: .cancel) { imageFiles = [] }
        } message: { Text("Se guardarán en Pictures/Remio del Portal.") }
        .confirmationDialog("¿Instalar este APK en el Portal?", isPresented: $confirmInstall, titleVisibility: .visible) {
            Button("Instalar") {
                guard let selectedAPK else { return }
                guard tools.adb.isConnected else {
                    tools.error = "Conecta el Portal por ADB antes de instalar el APK."
                    return
                }
                tools.perform("Instalar APK") {
                    let access = selectedAPK.startAccessingSecurityScopedResource()
                    defer { if access { selectedAPK.stopAccessingSecurityScopedResource() } }
                    let size = try selectedAPK.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= ADBTools.limit else { throw ADBToolError.tooLarge }
                    try await tools.install(Data(contentsOf: selectedAPK, options: .mappedIfSafe))
                    try await tools.refreshPackages()
                }
            }
            Button("Cancelar", role: .cancel) { selectedAPK = nil }
        } message: { Text(selectedAPK?.lastPathComponent ?? "") }
        .confirmationDialog("¿Desinstalar esta app?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Desinstalar", role: .destructive) {
                guard let selectedPackage = selectedForDeletion else { return }
                tools.perform("Desinstalar \(selectedPackage.packageName)") { try await tools.uninstall(selectedPackage.packageName) }
            }
        } message: { Text("Se eliminarán la app y sus datos del Portal.") }
        .confirmationDialog("¿Enviar las fotos seleccionadas?", isPresented: $confirmPhotos, titleVisibility: .visible) {
            Button("Enviar \(photos.count) fotos") {
                let items = photos
                tools.perform("Enviar fotos") {
                    for (index, item) in items.enumerated() {
                        guard let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
                              let suffix = type.preferredFilenameExtension,
                              let data = try await item.loadTransferable(type: Data.self) else { throw ADBToolError.invalidData }
                        try await tools.uploadPhoto(data, extension: suffix)
                        tools.setProgress("Enviando foto \(index + 1) de \(items.count)")
                    }
                    photos = []
                }
            }
        }
        .confirmationDialog(blockUpdates ? "¿Bloquear las actualizaciones del Portal?" : "¿Restablecer las actualizaciones del Portal?", isPresented: $changeUpdates, titleVisibility: .visible) {
            Button(blockUpdates ? "Bloquear" : "Restablecer", role: blockUpdates ? .destructive : nil) {
                tools.perform("Cambiar actualizaciones del sistema") { try await tools.setUpdates(blocked: blockUpdates) }
            }
        } message: { Text("Modifica los componentes de actualización del sistema, como Portal Toolkit.") }
        .sheet(item: $selectedPackage) { app in
            NavigationStack {
                Form {
                    Section { Text(app.packageName).font(.footnote.monospaced()); Text(details).font(.footnote) }
                    Section {
                        Button("Desinstalar", role: .destructive) {
                            selectedPackage = nil
                            Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); selectedForDeletion = app; confirmDelete = true }
                        }.disabled(!ready)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationTitle(appName(app)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar", systemImage: "xmark") { selectedPackage = nil } } }
            }.presentationDetents([.medium, .large])
        }
    }

    @State private var selectedForDeletion: PortalPackage?
    private var ready: Bool { tools.adb.isConnected && !tools.busy }
    private func appName(_ app: PortalPackage) -> String { remote.apps.first(where: { $0.packageName == app.packageName })?.label ?? app.packageName }
    private var apps: some View {
        Group {
            Section { Button("Instalar APK", systemImage: "square.and.arrow.down") { selectingAPK = true; importFiles = true }.disabled(tools.busy) }
            Section("En el Portal · \(tools.packages.count)") {
                TextField("Buscar app", text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                ForEach(tools.packages.filter { search.isEmpty || appName($0).localizedCaseInsensitiveContains(search) || $0.packageName.localizedCaseInsensitiveContains(search) }) { app in
                    Button {
                        details = "Cargando…"; selectedPackage = app
                        tools.perform("Consultar app") { details = try await tools.packageDetails(app.packageName) }
                    } label: {
                        HStack(spacing: 12) {
                            PortalAppIcon(app: PortalApp(label: appName(app), packageName: app.packageName), size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(appName(app)).foregroundStyle(.primary)
                                if appName(app) != app.packageName { Text(app.packageName).font(.caption).foregroundStyle(.secondary) }
                            }
                        }.padding(.vertical, 3)
                    }.disabled(!ready)
                }
                Button("Actualizar lista", systemImage: "arrow.clockwise") { refresh() }.disabled(!ready)
            }
        }
    }
    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $photos, maxSelectionCount: 30, matching: .images) { Label("Elegir de la fototeca", systemImage: "photo.on.rectangle") }.disabled(!ready)
            Button("Elegir de Archivos", systemImage: "folder") { selectingAPK = false; importFiles = true }.disabled(!ready)
            if !photos.isEmpty {
                LabeledContent("Seleccionadas", value: String(photos.count))
                Button("Enviar al Portal", systemImage: "square.and.arrow.up") { confirmPhotos = true }.disabled(!ready)
            }
        } footer: { Text("Se guardan en Pictures/Remio del Portal.") }
    }
    private var updates: some View {
        Group {
            Section {
                ForEach(tools.otaPackages, id: \.self) { package in
                    LabeledContent(package, value: tools.disabledOTA.contains(package) ? "Bloqueado" : "Activo").font(.footnote)
                }
                Button("Actualizar estado", systemImage: "arrow.clockwise") { refresh() }.disabled(!ready)
            }
            Section {
                Button("Bloquear actualizaciones", role: .destructive) { blockUpdates = true; changeUpdates = true }.disabled(!ready || tools.otaPackages.isEmpty)
                Button("Restablecer actualizaciones") { blockUpdates = false; changeUpdates = true }.disabled(!ready || tools.otaPackages.isEmpty)
            }
        }
    }
    private func refresh() {
        guard !tools.busy else { return }
        switch page {
        case .apps: tools.perform("Consultar aplicaciones") { try await tools.refreshPackages() }
        case .device: tools.perform("Consultar dispositivo") { try await tools.refreshInfo() }
        case .updates: tools.perform("Consultar actualizaciones") { try await tools.refreshUpdates() }
        default: break
        }
    }
}

private struct SavedPortalsView: View {
    @Environment(RemoteModel.self) private var remote
    @Bindable var adb: AdministrationModel
    @State private var renaming: SavedADBPortal?
    @State private var name = ""
    var body: some View {
        Section {
            Button("Buscar o añadir Portal", systemImage: "plus") { remote.showConnection = true }.disabled(adb.isBusy)
        }
        Section("Guardados") {
            ForEach(adb.savedDevices) { device in
                Menu {
                    Button("Conectar") { adb.check(host: device.endpoint.host, port: String(device.endpoint.port)) }.disabled(adb.isChecking || adb.isBusy)
                    Button("Cambiar nombre") { name = device.name; renaming = device }
                    Button("Olvidar destino", role: .destructive) { adb.remove(device) }.disabled(adb.isBusy)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name).foregroundStyle(.primary)
                            Text(device.endpoint.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if adb.savedEndpoint == device.endpoint, adb.isConnected { Image(systemName: "checkmark") }
                        else { Image(systemName: "ellipsis") }
                    }
                }
            }
        }
        .alert("Nombre en Remio", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $name)
            Button("Guardar") { if let renaming { adb.rename(renaming, to: name) }; renaming = nil }
            Button("Cancelar", role: .cancel) { renaming = nil }
        } message: { Text("Solo cambia el nombre guardado en esta app.") }
    }
}
