import SwiftUI

/// The quick flip between light and dark, parked in the bottom-right corner.
/// The icon is the mode you're *in* — a moon at night, a sun by day — and one
/// click writes the explicit choice, so a Mac set to switch at sunset stops
/// overriding what you just picked.
struct AuroraThemeToggle: View {
    /// Set when the toggle is pressed, so the workspace can run the swipe
    /// between the ice and the sky while the theme changes underneath it.
    @Binding var swipe: AuroraThemeSwipe.Move?

    @AppStorage(AuroraAppearance.storageKey) private var appearanceRaw = AuroraAppearance.system.rawValue
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false
    @State private var presses = 0

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        Button {
            let toLight = isDark
            presses += 1
            swipe = AuroraThemeSwipe.Move(toLight: toLight, id: presses)
            // The theme lands early, while the leaving surface still covers
            // the window — so what the wipe uncovers is already the new mode.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                appearanceRaw = (toLight ? AuroraAppearance.light : .dark).rawValue
            }
        } label: {
            Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isDark ? Color(red: 0.88, green: 0.93, blue: 1.0) : Aurora.ink)
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Aurora.line, lineWidth: 1))
                .scaleEffect(hover ? 1.06 : 1)
                // The swap reads as the sky turning over rather than a
                // glyph being replaced.
                .rotationEffect(.degrees(isDark ? 0 : 180))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.smooth(duration: 0.2), value: hover)
        .help(isDark ? "Switch to light" : "Switch to dark")
    }
}
