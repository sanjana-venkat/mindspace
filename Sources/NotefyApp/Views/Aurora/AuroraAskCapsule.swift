import SwiftUI

/// The Ask button and the question box, as one capsule.
///
/// At rest it says Ask; a click stretches the same frosted glass sideways and
/// the word becomes the place you type. Frosted like the arrows beside a
/// capture, in both states. Its own view so the offscreen renderer can draw
/// both states.
struct AuroraAskCapsule: View {
    let expanded: Bool
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    var placeholder: String
    var onExpand: () -> Void
    var onSubmit: () -> Void
    var onListen: () -> Void
    /// The ✕: puts the box away, back into the pill.
    var onCancel: () -> Void = {}

    private var dockPlaceholder: String { placeholder }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let empty = query.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 10) {
            SparkGlyph(size: 13)
            if expanded {
                TextField(dockPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(Aurora.ui(15.5, .regular))
                    .foregroundStyle(Aurora.ink)
                    .focused(focused)
                    .onSubmit { onSubmit() }
                    .transition(.opacity)
                if !query.isEmpty {
                    Button { onCancel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Aurora.ink2)
                            .contentShape(Circle())
                    }
                    .buttonStyle(AuroraTapDown())
                    .help("Close")
                }
                Button { onListen() } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                        .frame(width: 30, height: 30)
                        .background(Aurora.glassFill, in: Circle())
                        .overlay(Circle().strokeBorder(Aurora.glassEdge, lineWidth: 1))
                }
                .buttonStyle(AuroraTapDown())
                .help("Ask out loud")
                Button { onSubmit() } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Aurora.accent, in: Circle())
                }
                .buttonStyle(AuroraTapDown())
                .disabled(empty)
                .opacity(empty ? 0.45 : 1)
                .help("Ask")
            } else {
                Text("Ask")
                    .font(Aurora.ui(15, .semibold))
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .foregroundStyle(expanded ? Aurora.ink : Aurora.glassInk)
        .padding(.leading, expanded ? 18 : 22)
        .padding(.trailing, expanded ? 8 : 22)
        .frame(height: expanded ? 48 : 44)
        // Between two numbers, so the width itself springs open. The pill is
        // the field from the first frame to the last; nothing is swapped.
        .frame(minWidth: 104, maxWidth: expanded ? 620 : 104)
        .background {
            // Frosted at night. By day a plain 10% black: frosting over a
            // white page only turns it a heavier grey.
            // At rest, light glass. Open, the same capsule thickens to a
            // nearly solid frost, because now there are words to read on it.
            // Always frosted underneath, so whatever is behind cannot show
            // through and drown the word; the tint on top sets the colour.
            Capsule().fill(.regularMaterial)
                .overlay(Capsule().fill(expanded ? Aurora.readableGlass : Aurora.glassFill))
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Aurora.glassEdge, lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.12), radius: scheme == .dark ? 14 : 10, y: scheme == .dark ? 6 : 4)
        .contentShape(Capsule())
        .onTapGesture { if !expanded { onExpand() } }
        .help(expanded ? "" : "Ask anything  (⌘F)")
    }
}
