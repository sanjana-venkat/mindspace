import AppKit
import ImageIO

/// Screenshots, loaded once.
///
/// The grid used to call `NSImage(contentsOfFile:)` on every redraw, for every
/// tile, which on a note with a dozen full-window captures is a dozen decodes
/// each time anything moves. The viewer needs the same images, so they share
/// one cache.
@MainActor
enum ScreenshotStore {
    private static let images = NSCache<NSString, NSImage>()
    private static var aspects: [String: CGFloat] = [:]

    static func image(_ path: String) -> NSImage? {
        if let hit = images.object(forKey: path as NSString) { return hit }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        images.setObject(image, forKey: path as NSString)
        return image
    }

    /// Width over height, read from the file's header without decoding it,
    /// so the grid can lay a tile out before the picture has loaded.
    static func aspect(_ path: String) -> CGFloat? {
        if let known = aspects[path] { return known }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat, h > 0
        else { return nil }
        aspects[path] = w / h
        return w / h
    }
}
