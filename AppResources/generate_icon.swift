import AppKit
import CoreImage

// MINDSPACE app icon — a brain reduced to what survives at 16pt, in white, cut
// out of an aurora. The folds are erased rather than drawn, so the light behind
// the mark shows through them. Deterministic source: re-render, don't replace.

let size = 1024.0
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: rect.size)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: a)
}

let nightTop = rgb(7, 16, 21)
let nightLow = rgb(12, 30, 34)
let green = rgb(64, 208, 142)
let teal = rgb(64, 168, 190)

image.lockFocus()

let plate = NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24), xRadius: 224, yRadius: 224)
plate.addClip()

// The sky.
NSGradient(colors: [nightLow, nightTop], atLocations: [0, 1], colorSpace: .deviceRGB)?
    .draw(in: rect, angle: 90)

// Two soft bands of light behind the mark — enough to read as an aurora, not
// so much that it competes with the silhouette.
let sky = NSImage(size: rect.size)
sky.lockFocus()
for (centre, width, colour) in [(380.0, 260.0, green), (660.0, 200.0, teal)] {
    let band = NSBezierPath()
    band.move(to: NSPoint(x: centre - width / 2, y: 120))
    band.curve(to: NSPoint(x: centre + 60 - width / 2, y: 940),
               controlPoint1: NSPoint(x: centre - width / 2 - 60, y: 460),
               controlPoint2: NSPoint(x: centre + 110 - width / 2, y: 640))
    band.line(to: NSPoint(x: centre + 60 + width / 2, y: 940))
    band.curve(to: NSPoint(x: centre + width / 2, y: 120),
               controlPoint1: NSPoint(x: centre + 110 + width / 2, y: 640),
               controlPoint2: NSPoint(x: centre - width / 2 + 60, y: 460))
    band.close()
    NSGraphicsContext.saveGraphicsState()
    band.addClip()
    NSGradient(colors: [colour.withAlphaComponent(0), colour.withAlphaComponent(0.95), colour.withAlphaComponent(0)],
               atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)?
        .draw(in: NSRect(x: 0, y: 120, width: size, height: 820), angle: 90)
    NSGraphicsContext.restoreGraphicsState()
}
sky.unlockFocus()

if let blur = CIFilter(name: "CIGaussianBlur"),
   let tiff = sky.tiffRepresentation,
   let ci = CIImage(data: tiff) {
    blur.setValue(ci, forKey: kCIInputImageKey)
    blur.setValue(90.0, forKey: kCIInputRadiusKey)
    if let output = blur.outputImage, let cg = CIContext().createCGImage(output, from: ci.extent) {
        NSGraphicsContext.current?.cgContext.draw(cg, in: rect)
    }
}

// The mark: a rounded mass with a scalloped top. The bumps along the crown are
// what actually say "brain" at small sizes — interior detail reads as noise, a
// lumpy silhouette reads instantly.
let brain = NSBezierPath()
let bumpRadius: CGFloat = 68
let crownY: CGFloat = 660
let bumpCentres: [CGFloat] = [318, 446, 578, 706]

brain.move(to: NSPoint(x: 250, y: 430))
brain.curve(to: NSPoint(x: 250, y: crownY),
            controlPoint1: NSPoint(x: 214, y: 520), controlPoint2: NSPoint(x: 220, y: 606))
for centre in bumpCentres {
    brain.appendArc(withCenter: NSPoint(x: centre, y: crownY),
                    radius: bumpRadius, startAngle: 180, endAngle: 0, clockwise: true)
}
brain.curve(to: NSPoint(x: 774, y: 430),
            controlPoint1: NSPoint(x: 804, y: 606), controlPoint2: NSPoint(x: 810, y: 520))
brain.curve(to: NSPoint(x: 512, y: 268),
            controlPoint1: NSPoint(x: 742, y: 330), controlPoint2: NSPoint(x: 636, y: 268))
brain.curve(to: NSPoint(x: 250, y: 430),
            controlPoint1: NSPoint(x: 388, y: 268), controlPoint2: NSPoint(x: 282, y: 330))
brain.close()

func fold(_ points: [NSPoint], width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: points[0])
    path.curve(to: points[2], controlPoint1: points[1], controlPoint2: points[1])
    path.lineWidth = width
    path.lineCapStyle = .round
    path.stroke()
}

// White silhouette with the folds erased, so the aurora shows through them.
let mark = NSImage(size: rect.size)
mark.lockFocus()
NSColor.white.setFill()
brain.fill()
NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
NSColor.black.setStroke()
// One divide, nothing else. Two hemispheres is the whole idea.
fold([NSPoint(x: 512, y: 736), NSPoint(x: 512, y: 500), NSPoint(x: 512, y: 262)], width: 44)
mark.unlockFocus()
mark.draw(in: rect)

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
