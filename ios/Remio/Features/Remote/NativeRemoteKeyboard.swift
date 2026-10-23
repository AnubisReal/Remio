import SwiftUI
import UIKit

/// Real iOS keyboard. Transmits committed edits; marked IME composition stays local.
struct NativeRemoteKeyboard: UIViewRepresentable {
    let onEdit: (PortalTextEdit) -> Bool
    let onEmptyDelete: () -> Bool
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> RemoteTextField {
        let field = RemoteTextField()
        field.placeholder = "Escribe en el Portal"
        field.borderStyle = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .done
        field.accessibilityLabel = "Teclado del Portal, escritura en directo"
        field.accessibilityIdentifier = "portal-keyboard-input"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.onEmptyDelete = { [weak coordinator = context.coordinator, weak field] in
            guard let coordinator else { return }
            if !coordinator.parent.onEmptyDelete() { field?.resignFirstResponder(); coordinator.parent.onDismiss() }
        }
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.onAttachedToWindow = { [weak coordinator = context.coordinator, weak field] in
            guard let coordinator, !coordinator.stopped else { return }
            field?.becomeFirstResponder()
        }
        return field
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RemoteTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 240, height: 48)
    }

    func updateUIView(_ field: RemoteTextField, context: Context) {
        context.coordinator.parent = self
        let coordinator = context.coordinator
        Task { @MainActor [weak field] in
            guard !coordinator.stopped, let field, field.window != nil, !field.isFirstResponder else { return }
            field.becomeFirstResponder()
        }
    }

    static func dismantleUIView(_ field: RemoteTextField, coordinator: Coordinator) {
        coordinator.stopped = true
        field.resignFirstResponder()
        field.delegate = nil
        field.onEmptyDelete = nil
        field.onAttachedToWindow = nil
        field.text = nil
        coordinator.committed = ""
    }

    @MainActor final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NativeRemoteKeyboard
        var committed = ""
        var stopped = false
        init(_ parent: NativeRemoteKeyboard) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            guard !stopped, field.markedTextRange == nil else { return }
            let next = field.text ?? ""
            let edit = PortalTextEdit(previous: committed, next: next)
            guard !edit.isEmpty else { return }
            if parent.onEdit(edit) { committed = next }
            else {
                stopped = true
                field.resignFirstResponder()
                field.text = nil
                committed = ""
                parent.onDismiss()
            }
        }

        func textFieldDidChangeSelection(_ textField: UITextField) { changed(textField) }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            stopped = true
            textField.resignFirstResponder()
            parent.onDismiss()
            return false
        }
    }
}

final class RemoteTextField: UITextField {
    var onEmptyDelete: (() -> Void)?
    var onAttachedToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            Task { @MainActor [weak self] in
                guard let self, self.window != nil else { return }
                self.onAttachedToWindow?()
            }
        }
    }
    override func deleteBackward() {
        if (text ?? "").isEmpty, markedTextRange == nil { onEmptyDelete?() }
        else { super.deleteBackward() }
    }
}
