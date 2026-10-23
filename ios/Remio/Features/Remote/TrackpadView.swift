import SwiftUI

struct TrackpadView: View {
    @Environment(RemoteModel.self) private var remote
    @Binding var isDragging: Bool
    @State private var previous = CGSize.zero
    @State private var startedAt: Date?
    @State private var moved = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34).fill(RemioTheme.surface)
            RoundedRectangle(cornerRadius: 34)
                .strokeBorder(RemioTheme.accent.opacity(0.12), lineWidth: 1)
        }
        .aspectRatio(0.85, contentMode: .fit)
        .contentShape(.rect(cornerRadius: 34))
        .highPriorityGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard remote.canUseTouchpad else { return }
                if startedAt == nil { startedAt = Date(); isDragging = true }
                if abs(value.translation.width) > 6 || abs(value.translation.height) > 6 { moved = true }
                if moved {
                    remote.move(dx: value.translation.width - previous.width, dy: value.translation.height - previous.height)
                    previous = value.translation
                }
            }
            .onEnded { _ in
                if remote.canUseTouchpad, !moved, let startedAt, Date().timeIntervalSince(startedAt) < 0.35 { remote.enqueue(.tap) }
                reset()
            })
        .onChange(of: remote.canUseTouchpad) { _, _ in reset() }
        .onDisappear { reset() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Trackpad del Portal"))
        .accessibilityHint(String(localized: "Desliza para mover el cursor en el Portal y toca para hacer clic"))
        .accessibilityAction(named: Text(String(localized: "Clic"))) { remote.enqueue(.tap) }
        .accessibilityAction(named: Text(String(localized: "Mover arriba"))) { remote.move(dx: 0, dy: -30) }
        .accessibilityAction(named: Text(String(localized: "Mover abajo"))) { remote.move(dx: 0, dy: 30) }
        .accessibilityAction(named: Text(String(localized: "Mover izquierda"))) { remote.move(dx: -30, dy: 0) }
        .accessibilityAction(named: Text(String(localized: "Mover derecha"))) { remote.move(dx: 30, dy: 0) }
    }

    private func reset() {
        previous = .zero
        startedAt = nil
        moved = false
        isDragging = false
    }
}


struct RemoteControlSurface: View {
    @AppStorage("remio.directionalControl.enabled") private var directionalControlEnabled = false
    @Environment(AdministrationModel.self) private var adb
    @Binding var isDragging: Bool
    @State private var directional = false
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if directionalControlEnabled && directional {
                    RoundedRectangle(cornerRadius: 34).fill(RemioTheme.surface)
                    VStack(spacing: 16) {
                        GeometryReader { geometry in
                            let diameter = min(geometry.size.width - 32, geometry.size.height - 16)
                            ZStack {
                                Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                                key(String(localized: "Arriba"), symbol: "chevron.up", code: 19).offset(y: -diameter * 0.34)
                                key(String(localized: "Abajo"), symbol: "chevron.down", code: 20).offset(y: diameter * 0.34)
                                key(String(localized: "Izquierda"), symbol: "chevron.left", code: 21).offset(x: -diameter * 0.34)
                                key(String(localized: "Derecha"), symbol: "chevron.right", code: 22).offset(x: diameter * 0.34)
                                key(String(localized: "Seleccionar"), symbol: "circle.fill", code: 23)
                                    .background(.primary.opacity(0.06), in: Circle())
                            }
                            .frame(width: diameter, height: diameter)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if !adb.isConnected { Text(String(localized: "Conecta ADB para usar las flechas")).font(.caption).foregroundStyle(.secondary) }
                    }.padding(20)
                } else {
                    TrackpadView(isDragging: $isDragging)
                }
            }
            .aspectRatio(0.85, contentMode: .fit)
            .overlay(alignment: directional ? .leading : .trailing) {
                if directionalControlEnabled {
                Color.clear.frame(width: 28).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                        guard abs(value.translation.width) > 45, abs(value.translation.width) > abs(value.translation.height) else { return }
                        if (!directional && value.translation.width < 0) || (directional && value.translation.width > 0) { changeMode() }
                    })
                }
            }
            if directionalControlEnabled {
            HStack(spacing: 10) {
                modeButton("Trackpad", selected: !directional, mode: false)
                modeButton(String(localized: "Mando direccional"), selected: directional, mode: true)
            }
            }
        }
        .onChange(of: directionalControlEnabled) { _, enabled in
            if !enabled { directional = false; isDragging = false }
        }
        .alert(String(localized: "Mando direccional"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(String(localized: "Aceptar"), role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func modeButton(_ label: String, selected: Bool, mode: Bool) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { directional = mode } } label: {
            Circle().fill(selected ? Color.primary : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                .frame(width: 28, height: 22).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func changeMode() {
        isDragging = false
        withAnimation(.easeInOut(duration: 0.2)) { directional.toggle() }
    }

    private func key(_ label: String, symbol: String, code: Int) -> some View {
        Button {
            guard !sending else { return }
            sending = true
            Task { @MainActor in
                defer { sending = false }
                do { _ = try await adb.service("shell:input keyevent \(code)") }
                catch { self.error = error.localizedDescription }
            }
        } label: {
            Image(systemName: symbol).font(.system(size: symbol == "circle.fill" ? 18 : 25, weight: .medium))
                .frame(width: 64, height: 64).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
        .disabled(!adb.isConnected || adb.isBusy || sending)
    }
}
