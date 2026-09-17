import SwiftUI
import AppKit

/// Mindspace noticing you have joined a meeting, and offering.
///
/// Deliberately not a system notification: this is the app's own card, with
/// the app's own icon and a slow band of aurora moving behind the glass, so
/// the offer reads as coming from Mindspace rather than from Notification
/// Centre. It waits a while, then withdraws without being dismissed.
struct AuroraMeetingToast: View {
    let headline: String
    let detail: String
    var acceptLabel: String = "Take notes"
    var onAccept: () -> Void
    var onDismiss: () -> Void

    @State private var landed = false
    private let art = MoonPetArt.load()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(Aurora.ui(14.5, .semibold))
                    .foregroundStyle(Aurora.ink)
                Text(detail)
                    .font(Aurora.ui(12.5))
                    .foregroundStyle(Aurora.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(action: onAccept) {
                        Text(acceptLabel)
                            .font(Aurora.ui(12.5, .semibold))
                            .foregroundStyle(Aurora.onSolid)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Aurora.solid, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(AuroraTapDown())

                    Button(action: onDismiss) {
                        Text("Not now")
                            .font(Aurora.ui(12.5, .medium))
                            .foregroundStyle(Aurora.ink2)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(AuroraTapDown())
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 364, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)

                // The aurora, drifting behind the glass.
                AuroraToastLight()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .opacity(0.55)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Aurora.surface.opacity(0.45))

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
        }
        // Arrives from above the top edge, the way the light does.
        .offset(y: landed ? 0 : -24)
        .opacity(landed ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) { landed = true } }
    }

    /// The moon, not the app icon: everything the app says to you comes from
    /// the same character, whether it is on the desktop or in a notification.
    /// It bobs here too, gently, so a card that appears reads as someone
    /// leaning in rather than a banner being posted.
    private var icon: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            MoonPetFigure(pose: .holding, art: art)
                .frame(width: 44, height: 44)
                .offset(y: sin(t * 1.3) * 2.4)
                .rotationEffect(.degrees(sin(t * 0.9) * 2))
        }
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
    }
}

/// Two slow bands of polar light for the back of a card. Cheap enough to leave
/// running for the seconds a toast is on screen.
struct AuroraToastLight: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                context.addFilter(.blur(radius: 26))
                for index in 0..<2 {
                    let drift = sin(t * (0.32 + Double(index) * 0.17) + Double(index) * 2.1)
                    let colour = index == 0
                        ? Color(red: 0.34, green: 0.94, blue: 0.72)
                        : Color(red: 0.55, green: 0.58, blue: 0.99)
                    let y = size.height * (index == 0 ? 0.34 : 0.66) + CGFloat(drift) * size.height * 0.16
                    let band = Path(ellipseIn: CGRect(x: -size.width * 0.2 + CGFloat(drift) * 30,
                                                      y: y - size.height * 0.3,
                                                      width: size.width * 1.4,
                                                      height: size.height * 0.6))
                    context.fill(band, with: .color(colour.opacity(0.5)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Floats a toast in the top-right of the active screen, under the menu bar.
@MainActor
final class AuroraToastController {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func present(headline: String,
                 detail: String,
                 acceptLabel: String = "Take notes",
                 seconds: Double = 14,
                 onAccept: @escaping () -> Void) {
        dismiss()

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        let size = NSSize(width: 396, height: 168)
        let origin = NSPoint(x: visible.maxX - size.width - 18,
                             y: visible.maxY - size.height - 10)

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.appearance = AuroraAppearance.current.nsAppearance
        panel.contentView = NSHostingView(rootView:
            AuroraMeetingToast(
                headline: headline,
                detail: detail,
                acceptLabel: acceptLabel,
                onAccept: { [weak self] in
                    onAccept()
                    self?.dismiss()
                },
                onDismiss: { [weak self] in self?.dismiss() })
                .preferredColorScheme(AuroraAppearance.current.scheme)
                .padding(16)
        )
        panel.orderFrontRegardless()
        self.panel = panel

        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        panel?.close()
        panel = nil
    }
}
