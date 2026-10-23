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
    case devices, apps, profiles, photos, backups, device, updates, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .devices: String(localized: "Dispositivos")
        case .apps: String(localized: "Aplicaciones")
        case .profiles: String(localized: "Lotes de APK")
        case .photos: String(localized: "Fotos")
        case .backups: String(localized: "Copias")
        case .device: String(localized: "Información del Portal")
        case .updates: String(localized: "Actualizaciones")
        case .history: String(localized: "Historial")
        }
    }
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
        case .devices: String(localized: "Conexiones y equipos guardados")
        case .apps: String(localized: "Gestión de APK")
        case .profiles: String(localized: "Agrupar instalaciones")
        case .photos: String(localized: "Fototeca y Archivos")
        case .backups: String(localized: "Guardar y restaurar")
        case .device: String(localized: "Android, memoria y almacenamiento")
        case .updates: String(localized: "Gestionar actualizaciones del sistema")
        case .history: String(localized: "Actividad de las herramientas")
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
                    toolGroup(String(localized: "Contenido"), pages: [.apps, .photos])
                    toolGroup(String(localized: "Organización"), pages: [.profiles, .backups])
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Equipo")).font(.headline)
                        VStack(spacing: 0) {
                            ForEach([ToolPage.devices, .device, .updates, .history]) { page in
                                NavigationLink(value: page) {
                                    HStack(spacing: 14) {
                                        Image(systemName: page.symbol).font(.system(size: 20)).frame(width: 28)
                                        Text(page.title).font(.body)
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
            .navigationTitle(String(localized: "Herramientas"))
            .navigationDestination(for: ToolPage.self) { page in
                ToolDetail(page: page, tools: tools)
            }
            #if DEBUG && targetEnvironment(simulator)
            .task(id: tools.adb.isConnected) {
                if tools.adb.isConnected, ProcessInfo.processInfo.environment["REMIO_TOOLS_PREVIEW"] == "1" {
                    tools.perform(.verify) {
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
            .alert(String(localized: "Herramientas"), isPresented: Binding(get: { tools.error != nil }, set: { if !$0 { tools.error = nil } })) {
                Button(String(localized: "Aceptar"), role: .cancel) { tools.error = nil }
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
                                Text(page.title).font(.headline)
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
                Section { Button(String(localized: "Conectar Portal")) { remote.showConnection = true } }
            }
            switch page {
            case .devices: SavedPortalsView(adb: tools.adb)
            case .apps: apps
            case .profiles: APKProfilesView(tools: tools)
            case .photos: photoSection
            case .device:
                Section {
                    ForEach(tools.information.keys.sorted(), id: \.self) { key in LabeledContent(key, value: tools.information[key] ?? "—") }
                    Button(String(localized: "Actualizar información"), systemImage: "arrow.clockwise") { refresh() }.disabled(!ready)
                }
            case .updates: updates
            case .history:
                Section {
                    ForEach(tools.history) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: entry.success ? "checkmark.circle" : "exclamationmark.circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.displayTitle)
                                Text(entry.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if tools.history.isEmpty { Text(String(localized: "Todavía no hay actividad")).foregroundStyle(.secondary) }
                    else { Button(String(localized: "Borrar historial"), role: .destructive) { tools.clearHistory() } }
                }
            case .backups:
                BackupToolsView(tools: tools)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
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
                    guard url.pathExtension.lowercased() == "apk" else { throw ADBToolError.refused(String(localized: "Selecciona un archivo APK.")) }
                    selectedAPK = url
                    confirmInstall = true
                } else {
                    guard urls.count <= 30 else { throw ADBToolError.refused(String(localized: "Selecciona un máximo de 30 imágenes.")) }
                    imageFiles = urls
                    confirmImageFiles = !urls.isEmpty
                }
            } catch { tools.error = error.localizedDescription }
        }
        .confirmationDialog(String(localized: "¿Enviar las imágenes seleccionadas?"), isPresented: $confirmImageFiles, titleVisibility: .visible) {
            Button(String(localized: "Enviar \(imageFiles.count) imágenes")) {
                let files = imageFiles
                tools.perform(.uploadFiles) {
                    for (index, url) in files.enumerated() {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= ADBTools.limit else { throw ADBToolError.tooLarge }
                        try await tools.uploadPhoto(Data(contentsOf: url, options: .mappedIfSafe), extension: url.pathExtension.lowercased())
                        tools.setProgress(String(localized: "Enviando imagen \(index + 1) de \(files.count)"))
                    }
                    imageFiles = []
                }
            }
            Button(String(localized: "Cancelar"), role: .cancel) { imageFiles = [] }
        } message: { Text(String(localized: "Se guardarán en Pictures/Remio del Portal.")) }
        .confirmationDialog(String(localized: "¿Instalar este APK en el Portal?"), isPresented: $confirmInstall, titleVisibility: .visible) {
            Button(String(localized: "Instalar")) {
                guard let selectedAPK else { return }
                guard tools.adb.isConnected else {
                    tools.error = String(localized: "Conecta el Portal por ADB antes de instalar el APK.")
                    return
                }
                tools.perform(.installAPK) {
                    let access = selectedAPK.startAccessingSecurityScopedResource()
                    defer { if access { selectedAPK.stopAccessingSecurityScopedResource() } }
                    let size = try selectedAPK.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= ADBTools.limit else { throw ADBToolError.tooLarge }
                    try await tools.install(Data(contentsOf: selectedAPK, options: .mappedIfSafe))
                    try await tools.refreshPackages()
                }
            }
            Button(String(localized: "Cancelar"), role: .cancel) { selectedAPK = nil }
        } message: { Text(selectedAPK?.lastPathComponent ?? "") }
        .confirmationDialog(String(localized: "¿Desinstalar esta app?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "Desinstalar"), role: .destructive) {
                guard let selectedPackage = selectedForDeletion else { return }
                tools.perform(.uninstall(selectedPackage.packageName)) { try await tools.uninstall(selectedPackage.packageName) }
            }
        } message: { Text(String(localized: "Se eliminarán la app y sus datos del Portal.")) }
        .confirmationDialog(String(localized: "¿Enviar las fotos seleccionadas?"), isPresented: $confirmPhotos, titleVisibility: .visible) {
            Button(String(localized: "Enviar \(photos.count) fotos")) {
                let items = photos
                tools.perform(.uploadPhotos) {
                    for (index, item) in items.enumerated() {
                        guard let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }),
                              let suffix = type.preferredFilenameExtension,
                              let data = try await item.loadTransferable(type: Data.self) else { throw ADBToolError.invalidData }
                        try await tools.uploadPhoto(data, extension: suffix)
                        tools.setProgress(String(localized: "Enviando foto \(index + 1) de \(items.count)"))
                    }
                    photos = []
                }
            }
        }
        .confirmationDialog(blockUpdates ? String(localized: "¿Bloquear las actualizaciones del Portal?") : String(localized: "¿Restablecer las actualizaciones del Portal?"), isPresented: $changeUpdates, titleVisibility: .visible) {
            Button(blockUpdates ? String(localized: "Bloquear") : String(localized: "Restablecer"), role: blockUpdates ? .destructive : nil) {
                tools.perform(.changeUpdates) { try await tools.setUpdates(blocked: blockUpdates) }
            }
        } message: { Text(String(localized: "Modifica los componentes de actualización del sistema, como Portal Toolkit.")) }
        .sheet(item: $selectedPackage) { app in
            NavigationStack {
                Form {
                    Section { Text(app.packageName).font(.footnote.monospaced()); Text(details).font(.footnote) }
                    Section {
                        Button(String(localized: "Desinstalar"), role: .destructive) {
                            selectedPackage = nil
                            Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); selectedForDeletion = app; confirmDelete = true }
                        }.disabled(!ready)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationTitle(appName(app)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "Cerrar"), systemImage: "xmark") { selectedPackage = nil } } }
            }.presentationDetents([.medium, .large])
        }
    }

    @State private var selectedForDeletion: PortalPackage?
    private var ready: Bool { tools.adb.isConnected && !tools.busy }
    private func appName(_ app: PortalPackage) -> String { remote.apps.first(where: { $0.packageName == app.packageName })?.label ?? app.packageName }
    private var apps: some View {
        Group {
            Section { Button(String(localized: "Instalar APK"), systemImage: "square.and.arrow.down") { selectingAPK = true; importFiles = true }.disabled(tools.busy) }
            Section(String(localized: "En el Portal · \(tools.packages.count)")) {
                TextField(String(localized: "Buscar app"), text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                ForEach(tools.packages.filter { search.isEmpty || appName($0).localizedCaseInsensitiveContains(search) || $0.packageName.localizedCaseInsensitiveContains(search) }) { app in
                    Button {
                        details = String(localized: "Cargando…"); selectedPackage = app
                        tools.perform(.appDetails) { details = try await tools.packageDetails(app.packageName) }
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
                Button(String(localized: "Actualizar lista"), systemImage: "arrow.clockwise") { refresh() }.disabled(!ready)
            }
        }
    }
    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $photos, maxSelectionCount: 30, matching: .images) { Label(String(localized: "Elegir de la fototeca"), systemImage: "photo.on.rectangle") }.disabled(!ready)
            Button(String(localized: "Elegir de Archivos"), systemImage: "folder") { selectingAPK = false; importFiles = true }.disabled(!ready)
            if !photos.isEmpty {
                LabeledContent(String(localized: "Seleccionadas"), value: String(photos.count))
                Button(String(localized: "Enviar al Portal"), systemImage: "square.and.arrow.up") { confirmPhotos = true }.disabled(!ready)
            }
        } footer: { Text(String(localized: "Se guardan en Pictures/Remio del Portal.")) }
    }
    private var updates: some View {
        Group {
            Section {
                ForEach(tools.otaPackages, id: \.self) { package in
                    LabeledContent(package, value: tools.disabledOTA.contains(package) ? String(localized: "Bloqueado") : String(localized: "Activo")).font(.footnote)
                }
                Button(String(localized: "Actualizar estado"), systemImage: "arrow.clockwise") { refresh() }.disabled(!ready)
            }
            Section {
                Button(String(localized: "Bloquear actualizaciones"), role: .destructive) { blockUpdates = true; changeUpdates = true }.disabled(!ready || tools.otaPackages.isEmpty)
                Button(String(localized: "Restablecer actualizaciones")) { blockUpdates = false; changeUpdates = true }.disabled(!ready || tools.otaPackages.isEmpty)
            }
        }
    }
    private func refresh() {
        guard !tools.busy else { return }
        switch page {
        case .apps: tools.perform(.applications) { try await tools.refreshPackages() }
        case .device: tools.perform(.device) { try await tools.refreshInfo() }
        case .updates: tools.perform(.updates) { try await tools.refreshUpdates() }
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
            Button(String(localized: "Buscar o añadir Portal"), systemImage: "plus") { remote.showConnection = true }.disabled(adb.isBusy)
        }
        Section(String(localized: "Guardados")) {
            ForEach(adb.savedDevices) { device in
                Menu {
                    Button(String(localized: "Conectar")) { adb.check(host: device.endpoint.host, port: String(device.endpoint.port)) }.disabled(adb.isChecking || adb.isBusy)
                    Button(String(localized: "Cambiar nombre")) { name = device.name; renaming = device }
                    Button(String(localized: "Olvidar destino"), role: .destructive) { adb.remove(device) }.disabled(adb.isBusy)
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
        .alert(String(localized: "Nombre en Remio"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(String(localized: "Nombre"), text: $name)
            Button(String(localized: "Guardar")) { if let renaming { adb.rename(renaming, to: name) }; renaming = nil }
            Button(String(localized: "Cancelar"), role: .cancel) { renaming = nil }
        } message: { Text(String(localized: "Solo cambia el nombre guardado en esta app.")) }
    }
}
