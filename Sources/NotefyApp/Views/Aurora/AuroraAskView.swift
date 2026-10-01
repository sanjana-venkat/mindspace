import SwiftUI

/// The conversation with your own library.
///
/// Every answer carries the captures it was built from, as chips you can click
/// to land on the exact capture. That is the whole point of asking your own
/// notes rather than a chatbot: you can check it. An answer you cannot trace
/// is just a confident stranger talking.
struct AuroraAskView: View {
    let turns: [AskTurn]
    var onOpenSource: (AskSource) -> Void
    var onClose: () -> Void
    var onAsk: (String) -> Void

    @State private var follow = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        ForEach(turns) { turn in
                            AskTurnView(turn: turn, onOpenSource: onOpenSource).id(turn.id)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 28)
                    // Room at the top for the close button, which floats.
                    .padding(.top, 56).padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                // Follow the conversation as it lands, both when a question
                // is added and when its answer arrives.
                .onChange(of: turns.map(\.thinking)) {
                    withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }

            AskField(placeholder: "Ask a follow up", text: $follow, autofocus: true, onSend: send)
                .padding(.horizontal, 20).padding(.vertical, 16)
        }
        // No title bar, no label, no rule: the conversation is the content,
        // and the only control it needs is a way out.
        .overlay(alignment: .topTrailing) { closeButton.padding(16) }
        // A fixed size. Fitting the panel to its content made it grow and
        // re-centre every time an answer arrived, so the whole thing jumped.
        .frame(width: 720, height: 580)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Aurora.surface.opacity(0.72))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Aurora.line, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.36), radius: 44, y: 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Aurora.ink2)
                .frame(width: 28, height: 28)
                .background(Aurora.surface2, in: Circle())
        }
        .buttonStyle(AuroraTapDown())
        .help("Close (Esc)")
    }

    private func send() {
        let text = follow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        follow = ""
        onAsk(text)
    }
}

/// One question and its answer. The same view in the library conversation and
/// inside a note, so asking feels like one thing wherever you do it.
struct AskTurnView: View {
    let turn: AskTurn
    var onOpenSource: (AskSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 60)
                Text(turn.question)
                    .font(Aurora.ui(15, .medium))
                    .foregroundStyle(Aurora.ink)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Aurora.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textSelection(.enabled)
            }

            if turn.thinking {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(turn.status)
                        .font(Aurora.ui(14)).foregroundStyle(Aurora.ink3)
                }
            } else if let failure = turn.failure {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Aurora.warning)
                        .font(.system(size: 13))
                    Text(failure)
                        .font(Aurora.ui(14))
                        .foregroundStyle(Aurora.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Aurora.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text(turn.answer)
                    .font(Aurora.serif(17))
                    .foregroundStyle(Aurora.ink)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !turn.citedSources.isEmpty {
                    FlowRow(spacing: 8) {
                        ForEach(turn.citedSources) { source in
                            AskSourceChip(source: source) { onOpenSource(source) }
                        }
                    }
                }
            }
        }
    }
}

/// A citation you can click: its number, and what it was.
struct AskSourceChip: View {
    let source: AskSource
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(String(format: "%02d", source.index))
                    .font(Aurora.mono(9.5))
                    .foregroundStyle(Aurora.onSolid)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 20, minHeight: 16)
                    .background(Capsule().fill(Aurora.accent))
                Text(source.label)
                    .font(Aurora.mono(10.5))
                    .foregroundStyle(Aurora.ink2)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Aurora.ink3)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Capsule().fill(Aurora.accent.opacity(0.1)))
            .overlay(Capsule().strokeBorder(Aurora.accent.opacity(0.32), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(AuroraTapDown())
        .help("\(source.noteTitle) · \(source.label)")
    }
}

/// The field you ask in. One shape everywhere a question can be typed.
struct AskField: View {
    let placeholder: String
    @Binding var text: String
    var autofocus = false
    var onSend: () -> Void

    @FocusState private var focused: Bool

    private var empty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 12)).foregroundStyle(Aurora.ink3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Aurora.ui(15, .regular))
                .foregroundStyle(Aurora.ink)
                .focused($focused)
                .onSubmit(onSend)
                .onAppear { if autofocus { focused = true } }
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Aurora.accent, in: Circle())
            }
            .buttonStyle(AuroraTapDown())
            .disabled(empty)
            .opacity(empty ? 0.4 : 1)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Aurora.surface2.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(Aurora.line, lineWidth: 1))
    }
}

/// Chips wrap rather than running off the edge. `HStack` cannot, and a `Grid`
/// would give every chip the width of the longest one.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + spacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + spacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
