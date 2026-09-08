import AppKit
import CoreImage

// MINDSPACE app icon — a night sky with an aurora hanging in it, the same
// curtains the reading panel draws. Deterministic source so the mark can be
// re-rendered rather than stored as an opaque bitmap.

let size = 1024.0
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: rect.size)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: a)
}

let nightTop = rgb(8, 16, 22)
let nightLow = rgb(14, 34, 38)
let green = rgb(76, 214, 150)
let teal = rgb(78, 176, 196)
let violet = rgb(140, 118, 226)
let rose = rgb(214, 130, 168)

image.lockFocus()

let plate = NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24), xRadius: 224, yRadius: 224)
plate.addClip()

// The sky.
NSGradient(colors: [nightLow, nightTop, nightLow],
           atLocations: [0, 0.45, 1],
           colorSpace: .deviceRGB)?
    .draw(in: rect, angle: 90)

// Three curtains: a wandering centre line, a breathing width, and a vertical
// ramp from green at the base to violet at the tips.
func curtain(centerX: Double, width: Double, phase: Double, tip: NSColor) {
    let path = NSBezierPath()
    let samples = 40
    var left: [NSPoint] = []
    var right: [NSPoint] = []
    for i in 0...samples {
        let t = Double(i) / Double(samples)
        let y = 120 + t * 800
        let wander = sin(t * 2.1 + phase) * 52 + sin(t * 4.3 + phase * 1.4) * 18
        let breath = width * (0.66 + 0.4 * sin(t * 2.4 + phase))
        left.append(NSPoint(x: centerX + wander - breath / 2, y: y))
        right.append(NSPoint(x: centerX + wander + breath / 2, y: y))
    }
    path.move(to: left[0])
    for point in left.dropFirst() { path.line(to: point) }
    for point in right.reversed() { path.line(to: point) }
    path.close()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [green.withAlphaComponent(0.0),
                        green.withAlphaComponent(1.0),
                        teal.withAlphaComponent(0.9),
                        tip.withAlphaComponent(0.85),
                        tip.withAlphaComponent(0.0)],
               atLocations: [0, 0.22, 0.55, 0.85, 1],
               colorSpace: .deviceRGB)?
        .draw(in: NSRect(x: 0, y: 100, width: size, height: 840), angle: 90)
    NSGraphicsContext.restoreGraphicsState()
}

// Drawn into an offscreen image so the whole aurora can be blurred as one.
let sky = NSImage(size: rect.size)
sky.lockFocus()
curtain(centerX: 300, width: 250, phase: 0.4, tip: violet)
curtain(centerX: 512, width: 150, phase: 2.4, tip: rose)
curtain(centerX: 726, width: 230, phase: 4.1, tip: violet)
sky.unlockFocus()

if let blur = CIFilter(name: "CIGaussianBlur"),
   let tiff = sky.tiffRepresentation,
   let ci = CIImage(data: tiff) {
    blur.setValue(ci, forKey: kCIInputImageKey)
    blur.setValue(30.0, forKey: kCIInputRadiusKey)
    if let output = blur.outputImage {
        let context = CIContext()
        if let cg = context.createCGImage(output, from: ci.extent) {
            NSGraphicsContext.current?.cgContext.draw(cg, in: rect)
        }
    }
} else {
    sky.draw(in: rect)
}

// A low horizon glow, so the curtains look like they stand on something.
NSGradient(colors: [green.withAlphaComponent(0.22), NSColor.clear],
           atLocations: [0, 1], colorSpace: .deviceRGB)?
    .draw(in: NSRect(x: 0, y: 0, width: size, height: 300), angle: 90)

// Stars.
var seed: UInt64 = 0x2545F4914F6CDD1D
func rand() -> Double {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return Double(seed % 100_000) / 100_000.0
}
for _ in 0..<90 {
    let x = rand() * size
    let y = 520 + rand() * 460
    let r = 1.4 + rand() * 2.6
    NSColor.white.withAlphaComponent(0.18 + rand() * 0.5).setFill()
    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: r, height: r)).fill()
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
