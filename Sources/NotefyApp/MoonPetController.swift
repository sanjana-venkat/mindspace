import AppKit
import SwiftUI

/// Puts the moon on the desktop and lets you push it around.
///
/// A borderless, non-activating panel: it floats above your work, follows you
/// between spaces, never takes focus, and never appears in the window list or
/// the Dock's window menu. Dragging anywhere on it moves it, and where you
/// leave it is where it is next time.
@MainActor
final class MoonPetController {
    let state = MoonPetState()
    /// What the ring around the moon does. Set by the app before it is shown.
    var actions = MoonPetActions()

    private var panel: NSPanel?
    /// Where the pointer and the panel were when the current drag began.
    private var dragStart: (pointer: NSPoint, origin: NSPoint)?
    private var pointerTimer: Timer?
    private static let originKey = "aurora.pet.origin"

    /// Whether the moon is out. Saved, so the choice survives a relaunch.
    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = self.panel ?? makePanel()
        panel.orderFrontRegardless()
        self.panel = panel
        updateRoom(for: panel)
        watchPointer()
        UserDefaults.standard.set(true, forKey: "aurora.pet.on")
    }

    /// Puts the moon beside the capture rail the first time it appears, so it
    /// arrives where the rail is rather than in a corner on its own. Once it
    /// has been dragged anywhere, that position wins — the moon is the user's
    /// to place.
    func show(besideRail rail: NSRect) {
        let size = NSSize(width: 640, height: 340)
        let hasBeenMoved = UserDefaults.standard.array(forKey: Self.originKey) != nil
        let panel = self.panel ?? makePanel()
        if !hasBeenMoved {
            let screen = NSScreen.screens.first { $0.frame.intersects(rail) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? rail
            // Just off the rail's leading edge, level with its top.
            let x = min(max(visible.minX + 8, rail.minX - size.width + 18), visible.maxX - size.width - 8)
            let y = min(max(visible.minY + 8, rail.maxY - size.height), visible.maxY - size.height - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        updateRoom(for: panel)
        watchPointer()
        UserDefaults.standard.set(true, forKey: "aurora.pet.on")
    }

    func hide() {
        stopWatchingPointer()
        panel?.orderOut(nil)
        UserDefaults.standard.set(false, forKey: "aurora.pet.on")
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Called at launch: the moon comes back if it was out when you quit.
    func restoreIfWanted() {
        guard UserDefaults.standard.object(forKey: "aurora.pet.on") as? Bool == true else { return }
        show()
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 640, height: 340)
        let panel = MoonPetPanel(
            contentRect: NSRect(origin: savedOrigin(for: size), size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.appearance = AuroraAppearance.current.nsAppearance
        panel.onMoved = { [weak self, weak panel] in
            guard let panel else { return }
            let origin = panel.frame.origin
            UserDefaults.standard.set([origin.x, origin.y], forKey: Self.originKey)
            self?.updateRoom(for: panel)
        }

        var hosting: MoonHostingView?
        let view = MoonPetView(
            state: state,
            actions: actions,
            onDrag: { [weak self, weak panel] carrying in
                guard let self, let panel else { return }
                guard carrying else {
                    self.dragStart = nil
                    return
                }
                // Measured against the pointer on screen, not against the view
                // being dragged: the view moves with the window, so using its
                // own translation fed the movement back into itself.
                let pointer = NSEvent.mouseLocation
                guard let start = self.dragStart else {
                    self.dragStart = (pointer: pointer, origin: panel.frame.origin)
                    return
                }
                let wanted = NSPoint(x: start.origin.x + pointer.x - start.pointer.x,
                                     y: start.origin.y + pointer.y - start.pointer.y)
                panel.setFrameOrigin(self.onScreen(wanted, size: panel.frame.size))
            },
            onExpanded: { open in
                // Collapsed, only the moon takes the mouse; open, the whole
                // panel does, because the choice pills reach past any radius
                // worth guessing at. Everything else falls through to whatever
                // you are actually working in.
                hosting?.interactiveRadius = open ? 9_999 : 40
            })
            .preferredColorScheme(AuroraAppearance.current.scheme)

        let made = MoonHostingView(rootView: AnyView(view))
        made.interactiveRadius = 40
        made.onPointerOut = { [weak self] in self?.state.pointerInside = false }
        hosting = made
        made.wantsLayer = true
        made.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = made
        return panel
    }

    /// Follows the pointer to know when it has left the moon.
    ///
    /// Three mechanisms have failed at this, all for the same reason. SwiftUI's
    /// hover only hears about the pointer while the panel hit-tests it, and the
    /// panel deliberately only hit-tests within 40pt of the ball — so stepping
    /// off the moon produces no exit, ever. An `NSTrackingArea` needs an entry
    /// AppKit hit-tested, so it never fires either. A global `NSEvent` monitor
    /// for mouse-moved is silently dropped unless the app has Input Monitoring,
    /// which this app has no business asking for.
    ///
    /// So: ask where the pointer is, six times a second, while the moon is on
    /// screen. No permission, no event routing, nothing to be dropped.
    private func watchPointer() {
        stopWatchingPointer()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                let pointer = NSEvent.mouseLocation
                let middle = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
                let inside = hypot(pointer.x - middle.x, pointer.y - middle.y) <= 165
                if self.state.pointerInside != inside {
                    self.state.pointerInside = inside
                }
            }
        }
        // Common mode, or it stops counting while a menu or a drag is up.
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func stopWatchingPointer() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        state.pointerInside = false
    }

    /// Keeps the moon itself on the usable screen. The panel is far bigger
    /// than the moon — it has to hold the ring — so what is clamped is where
    /// the moon sits inside it, not the panel's own edges. `visibleFrame`
    /// already excludes the Dock and the menu bar, which is exactly the area
    /// the moon should stay within.
    private func onScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let middle = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first { NSPointInRect(middle, $0.frame) }
            ?? NSScreen.screens.first { $0.frame.intersects(NSRect(origin: origin, size: size)) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }

        let margin: CGFloat = 46
        let x = min(max(middle.x, visible.minX + margin), visible.maxX - margin)
        let y = min(max(middle.y, visible.minY + margin), visible.maxY - margin)
        return NSPoint(x: x - size.width / 2, y: y - size.height / 2)
    }

    /// Is there screen on either side of the moon for a label to read into?
    /// A label starts 58pt out and the longest of them runs about 150pt, so
    /// 210 is what it actually needs — the old 290 was the width of the column
    /// it sits in, most of which is empty, and it flipped labels that fitted.
    private func updateRoom(for panel: NSWindow) {
        let middle = panel.frame.midX
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let needed: CGFloat = 210
        state.roomRight = middle + needed <= visible.maxX
        state.roomLeft = middle - needed >= visible.minX

        // The ring reaches about 120pt up or down — ring, icon and a little
        // air — so that is what it needs to open on a given side.
        let height: CGFloat = 130
        let centre = panel.frame.midY
        state.roomAbove = centre + height <= visible.maxY
        state.roomBelow = centre - height >= visible.minY
    }

    /// Where it was left, clamped onto a screen that still exists.
    private func savedOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        if let stored = UserDefaults.standard.array(forKey: Self.originKey) as? [CGFloat], stored.count == 2 {
            let candidate = NSPoint(x: stored[0], y: stored[1])
            let anywhere = NSScreen.screens.contains { $0.frame.intersects(NSRect(origin: candidate, size: size)) }
            if anywhere { return self.onScreen(candidate, size: size) }
        }
        // First run: bottom-right, out of the way of most work.
        return NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24)
    }
}

/// A panel that can be dragged by its whole body and reports where it landed.
private final class MoonPetPanel: NSPanel {
    var onMoved: (() -> Void)?

    // It can take key status when something in it is clicked — a panel that
    // refuses it never delivers the click to the button at all — but it never
    // takes focus away from your work on its own.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Without this, AppKit refuses to let the panel's top go past the menu
    /// bar — which is what stopped the moon being carried any higher.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        onMoved?()
    }
}

/// Transparent host, so the desktop shows through everywhere the moon isn't.
final class MoonHostingView: NSHostingView<AnyView> {
    /// Called when the pointer truly leaves the moon's neighbourhood.
    var onPointerOut: (() -> Void)?
    private var watch: NSTrackingArea?

    /// How far from the middle the panel is willing to take a click. The rest
    /// of the square is transparent and belongs to whatever is underneath.
    var interactiveRadius: CGFloat = 40

    override var isOpaque: Bool { false }

    /// A click in a panel that isn't key is swallowed unless the view says it
    /// will take it. Without this the ring looked live and did nothing: the
    /// first press only brought the panel forward, and there is no second
    /// press because the moon never becomes key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let watch { removeTrackingArea(watch) }
        // A box around the moon and its ring rather than the whole panel: the
        // panel is mostly empty air, and leaving the moon should count as
        // leaving even if the pointer is still inside that air.
        let side: CGFloat = 340
        let box = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        let area = NSTrackingArea(rect: box,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self)
        addTrackingArea(area)
        watch = area
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerOut?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Open, the whole panel is live — the choice pills reach further out
        // than any radius worth guessing at.
        guard interactiveRadius < 1_000 else { return super.hitTest(point) }
        let middle = NSPoint(x: bounds.midX, y: bounds.midY)
        let distance = hypot(point.x - middle.x, point.y - middle.y)
        guard distance <= interactiveRadius else { return nil }
        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}
