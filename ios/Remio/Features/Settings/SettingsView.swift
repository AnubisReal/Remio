import SwiftUI
import UIKit
import CoreText

struct SettingsView: View {
    @Environment(AppIconStore.self) private var icons
    @Environment(RemoteModel.self) private var remote
    @Environment(AdministrationModel.self) private var administration
    @AppStorage("remio.directionalControl.enabled") private var directionalControlEnabled = false
    @State private var confirmForget = false
    @ScaledMetric(relativeTo: .headline) private var deviceHeaderHeight = 32
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var remote = remote
        NavigationStack {
            Form {
                Section(String(localized: "Tu Portal")) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "display")
                                .resizable().scaledToFit().foregroundStyle(.secondary)
                                .frame(width: deviceHeaderHeight * 1.3, height: deviceHeaderHeight)
                                .accessibilityHidden(true)
                            deviceIdentity
                            Spacer(minLength: 8)
                            if remote.endpoint != nil {
                                Menu {
                                    Button(String(localized: "Olvidar vinculación del mando"), systemImage: "trash", role: .destructive) {
                                        confirmForget = true
                                    }
                                } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel(String(localized: "Opciones del Portal"))
                            }
                        }
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                            GridRow {
                                connectionHeading(String(localized: "Mando"), symbol: "cursorarrow.motionlines")
                                connectionHeading("ADB", symbol: "cable.connector")
                            }
                            GridRow {
                                Text(remote.status)
                                Text(administration.isConnected ? String(localized: "Conectado") : administration.status)
                            }
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        }

                    }
                    .padding(.vertical, 8)
                    Button { remote.showConnection = true } label: {
                        HStack {
                            Text(String(localized: "Gestionar conexiones"))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                    }
                }
                .listRowBackground(RemioTheme.surface)
                Section {
                    Toggle(String(localized: "Abrir teclado automáticamente"), isOn: $remote.automaticKeyboardEnabled)
                } header: { Text(String(localized: "Teclado")) } footer: {
                    Text(String(localized: "Al abrirse automáticamente, vacía el campo del Portal."))
                }
                .listRowBackground(RemioTheme.surface)
                Section {
                    Toggle(String(localized: "Mando direccional"), isOn: $directionalControlEnabled)
                } header: { Text(String(localized: "Controles")) } footer: {
                    Text(String(localized: "Desliza desde el borde del trackpad para cambiar de mando. Requiere ADB."))
                }
                .listRowBackground(RemioTheme.surface)
                Section {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(RemioIcon.allCases) { icon in iconOption(icon) }
                        }
                        VStack(spacing: 16) {
                            ForEach(RemioIcon.allCases) { icon in iconOption(icon) }
                        }
                    }
                    .padding(.vertical, 8)
                    if icons.isChanging {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(String(localized: "Cambiando icono…")).font(.footnote)
                        }
                    }
                } header: { Text(String(localized: "Icono de la app")) } footer: {
                    Text(String(localized: "Elige cómo aparece Remio en tu pantalla de inicio. iOS puede mostrar una confirmación al cambiarlo."))
                }
                .listRowBackground(RemioTheme.surface)
                Section {
                    socialProfile("GitHub", asset: "SocialGitHub", url: URL(string: "https://github.com/AnubisReal"))
                    socialProfile("Instagram", asset: "SocialInstagram", url: URL(string: "https://www.instagram.com/anubisreal/"))
                    socialProfile("X", asset: "SocialX", url: URL(string: "https://x.com/Anubisreal23"))
                } header: { Text(String(localized: "Sobre el creador")) } footer: {
                    Text("Versión \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .listRowBackground(RemioTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(RemioTheme.background)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle(String(localized: "Ajustes"))
            .confirmationDialog(String(localized: "¿Olvidar la vinculación del mando?"), isPresented: $confirmForget, titleVisibility: .visible) {
                Button(String(localized: "Olvidar en este iPhone"), role: .destructive) { remote.forget() }
            } message: { Text(String(localized: "Elimina la credencial del mando guardada en este iPhone. Tendrás que introducir el PIN de nuevo. La autorización ADB se conserva.")) }
            .onAppear { icons.refreshSelection() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { icons.refreshSelection() }
            }
            .alert(String(localized: "Icono de la app"), isPresented: Binding(get: { icons.errorMessage != nil }, set: { if !$0 { icons.errorMessage = nil } })) {
                Button(String(localized: "Aceptar"), role: .cancel) { icons.errorMessage = nil }
            } message: { Text(icons.errorMessage ?? "") }
        }
    }

    @ViewBuilder
    private func socialProfile(_ title: String, asset: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) { socialLabel(title, asset: asset) }
        } else {
            socialLabel(title, asset: asset).foregroundStyle(.secondary)
        }
    }

    private func socialLabel(_ title: String, asset: String) -> some View {
        let markSize: CGFloat = asset == "SocialGitHub" ? 21 : asset == "SocialInstagram" ? 20 : 19
        return HStack(spacing: 12) {
            Image(asset).renderingMode(.template).resizable().scaledToFit()
                .frame(width: markSize, height: markSize)
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
        }
    }

    private var deviceIdentity: some View {
        let titleFont = UIFont.preferredFont(forTextStyle: .headline)
        let detailFont = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
        let detail = remote.endpoint?.host ?? String(localized: "Sin vincular")
        func ink(_ text: String, _ font: UIFont) -> CGRect {
            CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [.font: font])), [.useGlyphPathBounds])
        }
        return HeaderInkLayout(height: deviceHeaderHeight,
                               titleInk: ink(remote.deviceName, titleFont), statusInk: ink(detail, detailFont)) {
            Text(remote.deviceName).font(Font(titleFont)).lineLimit(1)
            Text(detail).font(Font(detailFont)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func connectionHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 18)
            Text(title)
        }
        .font(.caption).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconOption(_ icon: RemioIcon) -> some View {
        let isSelected = icons.selected == icon
        return Button {
            Task { await icons.select(icon) }
        } label: {
            VStack(spacing: 12) {
                Image(icon.asset)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .clipShape(.rect(cornerRadius: 22))
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? RemioTheme.accent : .secondary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(RemioTheme.surface, in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(isSelected ? RemioTheme.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(icons.isChanging)
        .accessibilityLabel(String(localized: "Icono \(icon.title)"))
        .accessibilityValue(isSelected ? String(localized: "Seleccionado") : "")
        .accessibilityHint(isSelected ? String(localized: "Icono actual de la app") : String(localized: "Cambia el icono en la pantalla de inicio"))
    }
}
