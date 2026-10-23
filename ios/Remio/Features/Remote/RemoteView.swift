import SwiftUI
import UIKit
import CoreText

struct RemoteView: View {
    @Environment(RemoteModel.self) private var remote
    @Environment(AppIconStore.self) private var icons
    @Environment(AdministrationModel.self) private var administration
    @ScaledMetric(relativeTo: .headline) private var headerHeight = 30
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDragging = false
    @State private var showKeyboard = false
    @State private var showApps = false
    @State private var appsDetent: PresentationDetent = .medium
    @State private var showVolume = false
    @State private var screenError: String?
    @State private var sendingSleep = false
    @State private var seekPosition = 0.0
    @State private var isSeeking = false
    @State private var mediaSampledAt = Date()
    @State private var lastReportedPosition: Double?
    @State private var lastReportedPlaying: Bool?
    @State private var positionUnavailable = false
    @State private var artworkImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !remote.isConnected { connectionCard }
                    HStack(spacing: 12) {
                        Button { appsDetent = .medium; showApps = true } label: { controlLabel("Apps", "square.grid.2x2") }
                        Button { showKeyboard = true } label: { controlLabel("Teclado", "keyboard") }
                        commandButton("Fotos", "photo.stack", .screensaver)
                    }.disabled(!remote.isConnected)
                    RemoteControlSurface(isDragging: $isDragging)
                    HStack(spacing: 12) {
                        commandButton("Atrás", "chevron.backward", .back)
                        commandButton("Inicio", "house", .home)
                        commandButton("Recientes", "rectangle.on.rectangle", .recentApps)
                    }.disabled(!remote.isConnected)
                    HStack(spacing: 12) {
                        commandButton("Subir página", "arrow.up.to.line", .scrollUp)
                        commandButton("Bajar página", "arrow.down.to.line", .scrollDown)
                    }.disabled(!remote.canUseTouchpad)
                    if remote.inputUnavailable {
                        Label(remote.feedback, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }
                    mediaCard
                }
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            #if DEBUG && targetEnvironment(simulator)
            .defaultScrollAnchor(ProcessInfo.processInfo.environment["REMIO_MEDIA_PREVIEW"] == "1" ? .bottom : .top)
            #endif
            .toolbarBackground(.hidden, for: .navigationBar)
            .scrollDisabled(isDragging)
            .background(RemioTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { deviceHeader }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Volumen del Portal", systemImage: "speaker.wave.2") { showVolume = true }
                        .imageScale(.small)
                        .popover(isPresented: $showVolume) { volumeControls.presentationCompactAdaptation(.popover) }
                        .disabled(!remote.isConnected)
                    Button("Encender o apagar pantalla", systemImage: "power") {
                        guard !sendingSleep else { return }
                        sendingSleep = true
                        Task { @MainActor in
                            defer { sendingSleep = false }
                            do {
                                let state = try await administration.service("shell:dumpsys power")
                                let key = try ADBTools.screenToggleKey(from: state)
                                _ = try await administration.service("shell:input keyevent \(key)")
                            }
                            catch { screenError = error.localizedDescription }
                        }
                    }
                        .imageScale(.small)
                        .accessibilityHint("Alterna la pantalla según su estado real mediante ADB")
                        .disabled(!administration.isConnected || administration.isBusy || sendingSleep)
                }
            }
            .toolbar(showKeyboard ? .hidden : .visible, for: .tabBar)
            .onAppear { icons.refreshSelection() }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if showKeyboard && remote.isConnected {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            NativeRemoteKeyboard(onEdit: { remote.editText($0) },
                                onEmptyDelete: { remote.deleteFromKeyboard() },
                                onDismiss: { showKeyboard = false })
                                .frame(height: 48)
                                .padding(.horizontal, 18)
                                .glassEffect(.regular, in: .capsule)
                            Button { showKeyboard = false } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .accessibilityLabel("Ocultar teclado")
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            .onChange(of: remote.isConnected) { _, connected in
                if connected, ProcessInfo.processInfo.environment["REMIO_KEYBOARD_PREVIEW"] == "1" { showKeyboard = true }
                if connected, ProcessInfo.processInfo.environment["REMIO_APPS_PREVIEW"] == "1" { showApps = true }
            }
            #endif
            .onChange(of: remote.keyboardContext) { _, _ in showKeyboard = false }
            .onChange(of: remote.keyboardDetected) { _, _ in
                if remote.isConnected && remote.automaticKeyboardEnabled { showKeyboard = true }
            }
            .sheet(isPresented: $showApps) {
                appsSheet
                    .presentationDetents([.medium, .large], selection: $appsDetent)
                    .presentationDragIndicator(.visible)
            }
            .alert("Mando del Portal", isPresented: Binding(get: { remote.message != nil && !remote.showConnection }, set: { if !$0 { remote.message = nil } })) {
                Button("Aceptar", role: .cancel) { remote.message = nil }
            } message: { Text(remote.message ?? "") }
        }
    }

    private var deviceHeader: some View {
        Button { remote.showConnection = true } label: {
            HStack(spacing: 8) {
                Image(icons.selected.markAsset)
                    .resizable().scaledToFit()
                    .frame(width: headerHeight * icons.selected.markAspectRatio, height: headerHeight)
                    .accessibilityHidden(true)
                headerText.fixedSize(horizontal: true, vertical: false)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre la conexión del Portal")
        .alert("Apagar pantalla", isPresented: Binding(get: { screenError != nil }, set: { if !$0 { screenError = nil } })) {
            Button("Aceptar", role: .cancel) { screenError = nil }
        } message: {
            Text(screenError ?? "")
        }
    }

    private var volumeControls: some View {
        VStack(spacing: 16) {
            Text("Volumen del Portal").font(.headline)
            HStack(spacing: 20) {
                Button { remote.enqueue(.volumeDown) } label: {
                    Image(systemName: "speaker.minus").frame(width: 44, height: 44)
                }.accessibilityLabel("Bajar volumen")
                Button { remote.enqueue(.mute) } label: {
                    Image(systemName: "speaker.slash").frame(width: 44, height: 44)
                }.accessibilityLabel("Activar o desactivar silencio")
                Button { remote.enqueue(.volumeUp) } label: {
                    Image(systemName: "speaker.plus").frame(width: 44, height: 44)
                }.accessibilityLabel("Subir volumen")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(!remote.isConnected)
        }
        .padding(20)
    }

    private var headerText: some View {
        let titleFont = UIFont.systemFont(ofSize: UIFontMetrics(forTextStyle: .headline).scaledValue(for: 21), weight: .semibold)
        let statusFont = UIFont.preferredFont(forTextStyle: .caption2)
        return HeaderInkLayout(height: headerHeight,
                               titleInk: inkBounds(remote.deviceName, font: titleFont),
                               statusInk: inkBounds(remote.status, font: statusFont)) {
            Text(remote.deviceName).font(Font(titleFont)).foregroundStyle(.primary).lineLimit(1)
            Text(remote.status).font(Font(statusFont)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func inkBounds(_ text: String, font: UIFont) -> CGRect {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(remote.needsPairing ? "Tu Portal, a un toque" : "Buscando tu Portal")
                .font(.title3.weight(.semibold))
            Text(remote.needsPairing ? "Vincúlalo una vez. Después conectaremos por ti al abrir Remio." : "Comprueba que el Portal esté encendido y en la misma Wi-Fi.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button(remote.needsPairing ? "Conectar Portal" : "Revisar conexión") { remote.showConnection = true }
                .buttonStyle(.borderedProminent).tint(RemioTheme.accent).foregroundStyle(RemioTheme.background)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(RemioTheme.surface, in: .rect(cornerRadius: 24))
    }

    private var mediaCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Group {
                    if let artworkImage {
                        Image(uiImage: artworkImage).resizable().scaledToFit()
                    } else {
                        Image(systemName: "music.note").font(.title2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RemioTheme.background)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mediaTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(remote.media?.active == true ? remote.media?.artist ?? "Portal" : "El audio del Portal aparecerá aquí")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            if remote.media?.active == true {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let duration = validMediaDuration
                    let position = displayedPosition(at: timeline.date)
                    VStack(spacing: 2) {
                        if let duration {
                            Slider(value: Binding(get: { isSeeking ? seekPosition : position },
                                                  set: { seekPosition = $0 }), in: 0...duration) { editing in
                                if editing {
                                    seekPosition = displayedPosition(at: .now)
                                    isSeeking = true
                                } else {
                                    remote.enqueue(.seek(max(0, min(duration, seekPosition))))
                                    mediaSampledAt = .now
                                    isSeeking = false
                                }
                            }
                            .disabled(!remote.isConnected)
                            .accessibilityLabel("Posición de reproducción")
                            .accessibilityValue("\(PortalMedia.timeLabel(position)) de \(PortalMedia.timeLabel(duration))")
                        }
                        HStack {
                            Text(isSeeking ? "Saltar a \(PortalMedia.timeLabel(position))" : PortalMedia.timeLabel(position))
                            Spacer()
                            Text(PortalMedia.timeLabel(duration))
                        }
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                mediaButton("Anterior", "backward.end.fill", .previous, needsMedia: true)
                Spacer()
                skipButton(seconds: -15)
                Spacer()
                mediaButton(remote.media?.playing == true ? "Pausar" : "Reproducir", remote.media?.playing == true ? "pause.fill" : "play.fill", .playPause, needsMedia: true)
                Spacer()
                skipButton(seconds: 15)
                Spacer()
                mediaButton("Siguiente", "forward.end.fill", .next, needsMedia: true)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
            .background(RemioTheme.surface, in: .rect(cornerRadius: 24))
        .task(id: "\(remote.isConnected)/\(remote.endpoint?.baseURL.absoluteString ?? "")/\(remote.media?.artworkKey ?? "")") {
            artworkImage = nil
            if let data = await remote.artworkData(), !Task.isCancelled { artworkImage = UIImage(data: data) }
        }
        .onChange(of: remote.media?.artworkKey) { _, _ in
            isSeeking = false
            lastReportedPosition = nil
            lastReportedPlaying = nil
            positionUnavailable = false
        }
        .onChange(of: remote.mediaUpdatedAt, initial: true) { _, updatedAt in
            guard !isSeeking else { return }
            let reported = remote.media?.positionMs.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let playing = remote.media?.playing
            // Android can repeatedly expose a stale PlaybackState position, including zero.
            // Never restart the local clock for an unchanged sample.
            positionUnavailable = reported == nil
            if reported != lastReportedPosition {
                seekPosition = reported ?? 0
                mediaSampledAt = updatedAt
            } else if playing != lastReportedPlaying {
                seekPosition = PortalMedia.interpolatedPosition(base: seekPosition, sampledAt: mediaSampledAt,
                                                               now: updatedAt, playing: lastReportedPlaying == true,
                                                               duration: validMediaDuration)
                mediaSampledAt = updatedAt
            }
            lastReportedPosition = reported
            lastReportedPlaying = playing
        }
    }

    private func skipButton(seconds: Double) -> some View {
        Button {
            guard let duration = validMediaDuration else { return }
            let target = max(0, min(duration, displayedPosition(at: .now) + seconds * 1000))
            seekPosition = target
            mediaSampledAt = .now
            remote.enqueue(.seek(target))
        } label: {
            Image(systemName: seconds < 0 ? "gobackward.15" : "goforward.15")
                .font(.system(size: 24)).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "Retroceder 15 segundos" : "Avanzar 15 segundos")
        .disabled(!remote.isConnected || remote.media?.active != true || validMediaDuration == nil || positionUnavailable || isSeeking)
    }

    private var validMediaDuration: Double? {
        guard let duration = remote.media?.durationMs, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    private func displayedPosition(at date: Date) -> Double {
        PortalMedia.interpolatedPosition(base: seekPosition, sampledAt: mediaSampledAt, now: date,
                                         playing: remote.media?.playing == true && !isSeeking,
                                         duration: validMediaDuration)
    }

    private var mediaTitle: String {
        guard remote.media?.active == true else { return "Sin reproducción" }
        let title = remote.media?.title ?? ""
        return title.isEmpty ? "En reproducción" : title
    }

    private var appsSheet: some View {
        NavigationStack {
            ScrollView {
                if remote.apps.isEmpty {
                    ContentUnavailableView("Sin aplicaciones", systemImage: "square.grid.2x2",
                                           description: Text("Conecta el Portal para consultar sus aplicaciones."))
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), alignment: .center, spacing: 20) {
                        ForEach(remote.apps) { app in
                            Button {
                                remote.enqueue(.launch(app.packageName))
                                showApps = false
                            } label: {
                                VStack(spacing: 8) {
                                    PortalAppIcon(app: app)
                                    Text(app.label).font(.caption).foregroundStyle(.primary)
                                        .lineLimit(2).multilineTextAlignment(.center)
                                        .frame(height: 32, alignment: .top)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Abrir \(app.label) en el Portal")
                            .disabled(!remote.isConnected)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
                }
            }
            .containerBackground(.clear, for: .navigation)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("Aplicaciones").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showApps = false } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Cerrar aplicaciones")
                    .tint(.primary)
                }
            }
        }
    }

    private func commandButton(_ title: String, _ symbol: String, _ command: PortalCommand) -> some View {
        Button { remote.enqueue(command) } label: { controlLabel(title, symbol) }
    }

    private func controlLabel(_ title: String, _ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .frame(maxWidth: .infinity).frame(minHeight: 64)
            .background(RemioTheme.surface, in: .rect(cornerRadius: 20))
            .accessibilityLabel(title)
            .help(title)
    }

    private func mediaButton(_ title: String, _ symbol: String, _ command: PortalCommand, needsMedia: Bool = false) -> some View {
        Button { remote.enqueue(command) } label: {
            Image(systemName: symbol).font(.title3).frame(minWidth: 30, minHeight: 44)
        }.accessibilityLabel(title).disabled(!remote.isConnected || (needsMedia && remote.media?.active != true))
    }
}

struct PortalAppIcon: View {
    @Environment(RemoteModel.self) private var remote
    let app: PortalApp
    var size: CGFloat = 54
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill").resizable().scaledToFit()
                    .foregroundStyle(.secondary).padding(10)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: "\(remote.endpoint?.baseURL.absoluteString ?? "")/\(app.id)/\(remote.isConnected)") {
            image = nil
            if let data = await remote.appIconData(for: app), !Task.isCancelled { image = UIImage(data: data) }
        }
    }
}

/// Align actual glyph outlines to the mark, excluding the font's invisible line margins.
struct HeaderInkLayout: Layout {
    let height: CGFloat
    let titleInk: CGRect
    let statusInk: CGRect

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = subviews.map { $0.sizeThatFits(proposal).width }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let textProposal = ProposedViewSize(width: bounds.width, height: nil)
        let title = subviews[0].dimensions(in: textProposal)
        let status = subviews[1].dimensions(in: textProposal)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + titleInk.maxY - title[.firstTextBaseline]),
                          anchor: .topLeading, proposal: textProposal)
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY + statusInk.minY - status[.firstTextBaseline]),
                          anchor: .topLeading, proposal: textProposal)
    }
}

#Preview { RemoteView().environment(RemoteModel()).environment(AppIconStore()).preferredColorScheme(.dark) }
