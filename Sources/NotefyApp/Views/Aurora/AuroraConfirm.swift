import SwiftUI

/// A yes-or-no question asked in the app's own voice.
///
/// The system alert is a different piece of software appearing on top of this
/// one — square, grey, and in Apple's typeface. This is the same paper, the
/// same serif, the same buttons as everything else, and it darkens the room
/// behind it rather than replacing it.
struct AuroraConfirm: View {
    let title: String
    let message: String
    /// The destructive one, on the right.
    var confirmLabel: String = "Yes, delete"
    var cancelLabel: String = "Cancel"
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @State private var landed = false

    var body: some View {
        ZStack {
            // Clicking away is the same as cancelling.
            Color.black.opacity(landed ? 0.34 : 0)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Aurora.serif(21, .semibold))
                    .foregroundStyle(Aurora.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(Aurora.ui(13.5))
                    .foregroundStyle(Aurora.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Spacer()

                    Button(action: onCancel) {
                        Text(cancelLabel)
                            .font(Aurora.ui(13, .medium))
                            .foregroundStyle(Aurora.ink)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .contentShape(Capsule())
                            .overlay(Capsule().strokeBorder(Aurora.ink.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(AuroraTapDown())
                    .keyboardShortcut(.cancelAction)

                    Button(action: onConfirm) {
                        Text(confirmLabel)
                            .font(Aurora.ui(13, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Aurora.danger, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(AuroraTapDown())
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
            .padding(22)
            .frame(width: 380, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Aurora.surface.opacity(0.7))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Aurora.line, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.34), radius: 40, y: 18)
            }
            // It arrives from just behind the screen rather than snapping in.
            .scaleEffect(landed ? 1 : 0.94)
            .opacity(landed ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { landed = true }
        }
    }
}

/// Asking for one line of text, in the app's own voice — naming a new folder,
/// mostly. Same card as `AuroraConfirm`, with a field where the question was.
struct AuroraPrompt: View {
    let title: String
    var placeholder: String = ""
    var confirmLabel: String = "Create"
    var cancelLabel: String = "Cancel"
    var onConfirm: (String) -> Void
    var onCancel: () -> Void

    @State private var text = ""
    @State private var landed = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            Color.black.opacity(landed ? 0.34 : 0)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(Aurora.serif(21, .semibold))
                    .foregroundStyle(Aurora.ink)

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(Aurora.ui(15))
                    .foregroundStyle(Aurora.ink)
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Aurora.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Aurora.line, lineWidth: 1)
                    }
                    .onSubmit { if !trimmed.isEmpty { onConfirm(trimmed) } }

                HStack(spacing: 10) {
                    Spacer()

                    Button(action: onCancel) {
                        Text(cancelLabel)
                            .font(Aurora.ui(13, .medium))
                            .foregroundStyle(Aurora.ink)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .contentShape(Capsule())
                            .overlay(Capsule().strokeBorder(Aurora.ink.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(AuroraTapDown())
                    .keyboardShortcut(.cancelAction)

                    Button { onConfirm(trimmed) } label: {
                        Text(confirmLabel)
                            .font(Aurora.ui(13, .semibold))
                            .foregroundStyle(Aurora.onSolid)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Aurora.solid, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(AuroraTapDown())
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? 0.5 : 1)
                }
            }
            .padding(22)
            .frame(width: 380, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Aurora.surface.opacity(0.7))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Aurora.line, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.34), radius: 40, y: 18)
            }
            .scaleEffect(landed ? 1 : 0.94)
            .opacity(landed ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { landed = true }
            focused = true
        }
    }
}
