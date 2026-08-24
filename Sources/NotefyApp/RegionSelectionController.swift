import AppKit
import NotefyCore

@MainActor
final class RegionSelectionController {
    private var panel: NSPanel?
    private var sourceURL: URL?
    private var completion: ((Result<URL, Error>) -> Void)?

    func begin(outputDirectory: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard panel == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            completion(.failure(Self.error("Grant Screen & System Audio Recording access, then reopen Noted.")))
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            completion(.failure(Self.error("Could not determine which display to capture.")))
            return
        }

        let sourceURL = outputDirectory.appendingPathComponent(".region-source-\(UUID().uuidString).png")
        self.sourceURL = sourceURL
        self.completion = completion

        Task {
            let captured = await ScreenCapturer.takeScreenshot(
                saveTo: sourceURL,
                displayID: CGDirectDisplayID(number.uint32Value)
            )
            guard captured else {
                finish(.failure(Self.error("The display could not be captured.")))
                return
            }
            showOverlay(on: screen, outputDirectory: outputDirectory)
        }
    }

    private func showOverlay(on screen: NSScreen, outputDirectory: URL) {
        let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onSelected = { [weak self] rect in
            self?.saveSelection(rect, viewSize: screen.frame.size, outputDirectory: outputDirectory)
        }
        view.onCancel = { [weak self] in
            self?.finish(.failure(Self.error("Region capture cancelled.")))
        }

        let panel = RegionSelectionPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
        self.panel = panel
    }

    private func saveSelection(_ rect: NSRect, viewSize: NSSize, outputDirectory: URL) {
        guard rect.width >= 8, rect.height >= 8,
              let sourceURL,
              let image = NSImage(contentsOf: sourceURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            finish(.failure(Self.error("Drag a larger region to capture it.")))
            return
        }

        let scaleX = CGFloat(cgImage.width) / viewSize.width
        let scaleY = CGFloat(cgImage.height) / viewSize.height
        let crop = CGRect(
            x: rect.minX * scaleX,
            y: (viewSize.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral

        guard let cropped = cgImage.cropping(to: crop) else {
            finish(.failure(Self.error("The selected region could not be cropped.")))
            return
        }

        let outputURL = outputDirectory.appendingPathComponent("region_\(UUID().uuidString).png")
        let data = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
        do {
            guard let data else { throw Self.error("The selected image could not be encoded.") }
            try data.write(to: outputURL, options: .atomic)
            finish(.success(outputURL))
        } catch {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        NSCursor.arrow.set()
        panel?.orderOut(nil)
        panel = nil
        if let sourceURL { try? FileManager.default.removeItem(at: sourceURL) }
        sourceURL = nil
        let callback = completion
        completion = nil
        callback?(result)
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "Notefy.RegionSelection", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private final class RegionSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RegionSelectionView: NSView {
    var onSelected: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?
    private var startPoint: NSPoint?
    private var selection: NSRect = .zero

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        selection = NSRect(
            x: min(startPoint.x, current.x),
            y: min(startPoint.y, current.y),
            width: abs(current.x - startPoint.x),
            height: abs(current.y - startPoint.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        onSelected?(selection)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.12, alpha: 0.45).setFill()
        bounds.fill()

        if selection.isEmpty {
            let instruction = "DRAG TO CAPTURE  ·  ESC TO CANCEL" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "Quicksand", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor(calibratedRed: 0.973, green: 0.957, blue: 0.925, alpha: 1)
            ]
            let textSize = instruction.size(withAttributes: attributes)
            let pill = NSRect(
                x: bounds.midX - textSize.width / 2 - 18,
                y: bounds.midY - textSize.height / 2 - 10,
                width: textSize.width + 36,
                height: textSize.height + 20
            )
            NSColor(calibratedWhite: 0.12, alpha: 0.94).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            instruction.draw(at: NSPoint(x: pill.minX + 18, y: pill.minY + 10), withAttributes: attributes)
            return
        }
        NSColor.clear.setFill()
        selection.fill(using: .copy)
        NSColor(calibratedRed: 0.973, green: 0.957, blue: 0.925, alpha: 1).setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1.5
        border.setLineDash([6, 4], count: 2, phase: 0)
        border.stroke()

        let rose = NSColor(calibratedRed: 0.78, green: 0.604, blue: 0.565, alpha: 1)
        rose.setFill()
        for point in [
            NSPoint(x: selection.minX, y: selection.minY),
            NSPoint(x: selection.maxX, y: selection.minY),
            NSPoint(x: selection.minX, y: selection.maxY),
            NSPoint(x: selection.maxX, y: selection.maxY)
        ] {
            NSBezierPath(ovalIn: NSRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)).fill()
        }

        let label = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Quicksand", size: 10) ?? .systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.973, green: 0.957, blue: 0.925, alpha: 1)
        ]
        let textSize = label.size(withAttributes: attributes)
        let candidateX = min(bounds.maxX - textSize.width - 22, selection.maxX + 9)
        let candidateY = max(bounds.minY + 8, selection.minY - textSize.height - 16)
        let pillRect = NSRect(x: candidateX, y: candidateY, width: textSize.width + 16, height: textSize.height + 8)
        NSColor(calibratedWhite: 0.12, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2).fill()
        label.draw(at: NSPoint(x: pillRect.minX + 8, y: pillRect.minY + 4), withAttributes: attributes)
    }
}
