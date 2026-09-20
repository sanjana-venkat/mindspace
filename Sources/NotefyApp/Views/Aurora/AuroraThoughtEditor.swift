import SwiftUI
import AppKit

/// A place to write a thought, with a placeholder that cannot drift.
///
/// SwiftUI's `TextEditor` insets its text by an amount it does not publish, so
/// a placeholder laid over it is positioned by guesswork — and the guess was
/// wrong by a few points in every one of the three places this app asks for a
/// thought. The prompt sat slightly off from where the caret then appeared.
///
/// Here the placeholder is drawn by the text view itself, at the origin the
/// text container will actually use, in the same font. It cannot be off,
/// because it is measured from the same layout the typing uses.
struct AuroraThoughtEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont
    var textColor: NSColor
    var lineSpacing: CGFloat = 0
    var limit: Int?
    /// Inset from the edge of the control to the text, applied to both.
    var inset: CGSize = CGSize(width: 6, height: 8)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let view = AuroraPlaceholderTextView()
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.isEditable = true
        view.isSelectable = true
        view.allowsUndo = true
        view.textContainerInset = inset
        // The placeholder is drawn at the same origin the glyphs use, so this
        // has to be known rather than left to the default.
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true

        scroll.documentView = view
        apply(to: view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? AuroraPlaceholderTextView else { return }
        if view.string != text { view.string = text }
        apply(to: view)
    }

    private func apply(to view: AuroraPlaceholderTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing

        view.font = font
        view.textColor = textColor
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]
        view.placeholder = placeholder
        // Faded, not a different thing: same face, same size, same place.
        view.placeholderColor = textColor.withAlphaComponent(0.45)
        view.placeholderParagraphStyle = paragraph
        view.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: AuroraThoughtEditor

        init(_ parent: AuroraThoughtEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            if let limit = parent.limit, view.string.count > limit {
                view.string = String(view.string.prefix(limit))
            }
            parent.text = view.string
            view.needsDisplay = true
        }
    }
}

/// The text view that draws its own prompt.
final class AuroraPlaceholderTextView: NSTextView {
    var placeholder: String = ""
    var placeholderColor: NSColor = .secondaryLabelColor
    var placeholderParagraphStyle: NSParagraphStyle = .default

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty, let font else { return }

        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerInset.height)
        let width = bounds.width - origin.x - textContainerInset.width
        placeholder.draw(
            with: NSRect(origin: origin, size: NSSize(width: max(0, width), height: bounds.height)),
            options: [.usesLineFragmentOrigin],
            attributes: [
                .font: font,
                .foregroundColor: placeholderColor,
                .paragraphStyle: placeholderParagraphStyle,
            ])
    }
}

extension NSFont {
    /// The AppKit twin of `Aurora.serif` — the editors are AppKit now, and the
    /// prompt has to be the same face as the words that replace it.
    static func auroraSerif(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif),
              let serif = NSFont(descriptor: descriptor, size: size) else { return base }
        return serif
    }
}
