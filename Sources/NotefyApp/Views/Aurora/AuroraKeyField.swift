import SwiftUI
import AppKit

/// A password field that definitely takes the keyboard.
///
/// SwiftUI's `SecureField` depends on the hosting view handing it first
/// responder, and in the onboarding window it never did: the panel took clicks
/// — buttons and tabs worked — but the field could not be typed into at all,
/// which left people at the "add your API key" step with no way to add one.
///
/// This is the AppKit control underneath, asked directly. It focuses itself
/// when it appears, so the step arrives ready to paste into, and it reports
/// every keystroke rather than only on return.
struct AuroraKeyField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var textColor: NSColor = .white
    var focusOnAppear = false
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = textColor
        field.lineBreakMode = .byTruncatingTail
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: textColor.withAlphaComponent(0.45),
                .font: NSFont.systemFont(ofSize: 13),
            ])
        field.stringValue = text

        if focusOnAppear {
            // After the view is in a window, or there is nothing to focus in.
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        // Only when they differ: assigning while someone is typing moves the
        // insertion point back to the start.
        if field.stringValue != text { field.stringValue = text }
        field.textColor = textColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: AuroraKeyField

        init(_ parent: AuroraKeyField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}
