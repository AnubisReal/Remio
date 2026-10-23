import Observation
import UIKit

enum RemioIcon: String, CaseIterable, Identifiable {
    case pulse, signal
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var asset: String { "\(title)Preview" }
    var markAsset: String { "\(title)Mark" }
    var markAspectRatio: Double { self == .pulse ? 456.0 / 552 : 400.0 / 744 }
    var alternateName: String? { self == .pulse ? nil : "AppIconSignal" }
}

@MainActor @Observable
final class AppIconStore {
    private(set) var selected: RemioIcon = UIApplication.shared.alternateIconName == "AppIconSignal" ? .signal : .pulse
    private(set) var isChanging = false
    var errorMessage: String?

    func refreshSelection() {
        selected = UIApplication.shared.alternateIconName == "AppIconSignal" ? .signal : .pulse
    }

    func select(_ icon: RemioIcon) async {
        guard !isChanging, icon != selected else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "Este dispositivo no permite cambiar el icono."
            return
        }
        isChanging = true
        defer { isChanging = false }
        do {
            try await UIApplication.shared.setAlternateIconName(icon.alternateName)
            refreshSelection()
        } catch {
            errorMessage = "No se pudo cambiar el icono. Inténtalo de nuevo."
        }
    }
}
