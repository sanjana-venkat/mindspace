import AppKit
import Foundation
import ScreenCaptureKit

public enum ScreenCapturer {
    /// Captures with ScreenCaptureKit so macOS attributes the request to Notefy
    /// itself. Launching `/usr/sbin/screencapture` from the app can create a
    /// second TCC attribution path and repeatedly trigger permission prompts.
    public static func takeScreenshot(
        saveTo fileURL: URL,
        windowID: CGWindowID? = nil,
        displayID: CGDirectDisplayID? = nil
    ) async -> Bool {
        guard CGPreflightScreenCaptureAccess() else { return false }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            let filter: SCContentFilter
            if let windowID,
               let window = content.windows.first(where: { $0.windowID == windowID }) {
                filter = SCContentFilter(desktopIndependentWindow: window)
            } else if let displayID,
                      let display = content.displays.first(where: { $0.displayID == displayID }) {
                filter = SCContentFilter(display: display, excludingWindows: [])
            } else if let display = content.displays.first {
                filter = SCContentFilter(display: display, excludingWindows: [])
            } else {
                return false
            }

            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = max(1, Int(filter.contentRect.width * scale))
            configuration.height = max(1, Int(filter.contentRect.height * scale))
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let representation = NSBitmapImageRep(cgImage: image)
            guard let data = representation.representation(using: .png, properties: [:]) else {
                return false
            }
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            fputs("[screen-capture] \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    /// A small luminance signature used to detect meaningful visual changes without
    /// retaining a screenshot for every polling interval.
    public static func visualFingerprint(of fileURL: URL, width: Int = 32, height: Int = 20) -> [UInt8]? {
        guard let image = NSImage(contentsOf: fileURL),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              )
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var result = [UInt8]()
        result.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    result.append(0)
                    continue
                }
                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                result.append(UInt8(max(0, min(255, Int(luminance * 255)))))
            }
        }
        return result
    }

    public static func difference(_ lhs: [UInt8]?, _ rhs: [UInt8]?) -> Double {
        guard let lhs, let rhs, lhs.count == rhs.count, !lhs.isEmpty else { return 1 }
        let total = zip(lhs, rhs).reduce(0) { partial, pair in
            partial + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(total) / Double(lhs.count * 255)
    }
}
