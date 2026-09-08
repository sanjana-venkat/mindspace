import AppKit

// MINDSPACE app icon — an aurora drawn as fine vertical hatching, its folded
// bands stacked so the mass reads as a brain. Line-work rather than glow, on a
// deep navy sky. Deterministic source: re-render it, don't replace it.

let size = 1024.0
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: rect.size)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: a)
}

let navy = rgb(30, 27, 62)
let navyDeep = rgb(22, 20, 48)
let mint = rgb(196, 240, 214)
let ice = rgb(214, 238, 246)

image.lockFocus()

let plate = NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24), xRadius: 224, yRadius: 224)
plate.addClip()
NSGradient(colors: [navy, navyDeep], atLocations: [0, 1], colorSpace: .deviceRGB)?
    .draw(in: rect, angle: 90)

/// A band of aurora: filled with evenly spaced vertical strokes that fade out
/// downward, so the light looks combed rather than painted.
func hatch(_ path: NSBezierPath, tint: NSColor, spacing: CGFloat = 9, width: CGFloat = 3.4) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let box = path.bounds
    var x = box.minX
    while x <= box.maxX {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: x, y: box.minY - 4, width: width, height: box.height + 8)).addClip()
        NSGradient(colors: [tint.withAlphaComponent(0.96),
                            tint.withAlphaComponent(0.55),
                            tint.withAlphaComponent(0.0)],
                   atLocations: [0, 0.55, 1],
                   colorSpace: .deviceRGB)?
            .draw(in: NSRect(x: box.minX - 4, y: box.minY - 4, width: box.width + 8, height: box.height + 8),
                  angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        x += spacing
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// One fold: a slab whose top and bottom edges curve, with the right end
/// curling back on itself the way the bands in an aurora do.
func fold(top: CGFloat, thickness: CGFloat, left: CGFloat, right: CGFloat,
          rise: CGFloat, curl: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: left, y: top))
    path.curve(to: NSPoint(x: right, y: top + rise),
               controlPoint1: NSPoint(x: left + (right - left) * 0.30, y: top + rise * 2.1 + 34),
               controlPoint2: NSPoint(x: right - (right - left) * 0.22, y: top + rise * 1.6 + 12))
    path.curve(to: NSPoint(x: right - curl, y: top + rise - thickness),
               controlPoint1: NSPoint(x: right + 26, y: top + rise - thickness * 0.35),
               controlPoint2: NSPoint(x: right + 10, y: top + rise - thickness))
    path.curve(to: NSPoint(x: left, y: top - thickness),
               controlPoint1: NSPoint(x: right - (right - left) * 0.30, y: top + rise * 1.7 - thickness + 18),
               controlPoint2: NSPoint(x: left + (right - left) * 0.26, y: top + rise * 1.9 - thickness + 26))
    path.close()
    return path
}

// Four folds, narrowing downward, so the silhouette gathers into a mass.
hatch(fold(top: 726, thickness: 126, left: 214, right: 806, rise: 84, curl: 150), tint: ice)
hatch(fold(top: 604, thickness: 112, left: 188, right: 764, rise: -34, curl: 168), tint: mint)
hatch(fold(top: 486, thickness: 104, left: 248, right: 736, rise: 52, curl: 140), tint: mint)
hatch(fold(top: 372, thickness: 92, left: 316, right: 668, rise: -26, curl: 118), tint: ice)

// Stars, sparse and small.
var seed: UInt64 = 0x9E3779B97F4A7C15
func rand() -> Double {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return Double(seed % 100_000) / 100_000.0
}
func star(at point: NSPoint, radius: CGFloat) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: point.x, y: point.y + radius))
    path.curve(to: NSPoint(x: point.x + radius, y: point.y),
               controlPoint1: point, controlPoint2: point)
    path.curve(to: NSPoint(x: point.x, y: point.y - radius),
               controlPoint1: point, controlPoint2: point)
    path.curve(to: NSPoint(x: point.x - radius, y: point.y),
               controlPoint1: point, controlPoint2: point)
    path.curve(to: NSPoint(x: point.x, y: point.y + radius),
               controlPoint1: point, controlPoint2: point)
    path.close()
    ice.withAlphaComponent(0.85).setFill()
    path.fill()
}
for _ in 0..<12 {
    let x = 130 + rand() * 764
    let y = 250 + rand() * 640
    star(at: NSPoint(x: x, y: y), radius: 7 + rand() * 9)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render the icon")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments.count > 1
                    ? CommandLine.arguments[1]
                    : FileManager.default.currentDirectoryPath + "/icon_1024.png")
try png.write(to: outputURL)
print("Wrote \(outputURL.path)")
