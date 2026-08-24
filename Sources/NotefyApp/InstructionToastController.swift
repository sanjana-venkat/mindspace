import AppKit
import SwiftUI

@MainActor
final class InstructionToastController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String) {
        dismissTask?.cancel()
        panel?.close()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: 390, height: 70)
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 34)
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            HStack(spacing: 11) {
                OverlayIcon(kind: .text).frame(width: 23, height: 23)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message).font(NotefyFont.heading)
                    Text("Keep it highlighted, then use Text or ⌘⇧T")
                        .font(NotefyFont.caption).foregroundStyle(NotefyTheme.inkSoft)
                }
            }
            .foregroundStyle(NotefyTheme.ink)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(NotefyTheme.cardPaper, in: Capsule())
            .overlay(Capsule().stroke(NotefyTheme.ink.opacity(0.14), lineWidth: 1))
            .padding(4)
        )
        panel.orderFrontRegardless()
        self.panel = panel
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.panel?.close()
            self?.panel = nil
        }
    }
}
