import AppKit

// MINDSPACE app icon — the brain as line-work: one weight of stroke, one ink,
// on a navy plate. Drawn rather than filtered, because an outline thin enough
// to look delicate at 1024 is mush at 48, and the only fix is to choose the
// stroke weight for the small size and let the big one look bold.

let canvas = 1024.0
let rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let image = NSImage(size: rect.size)

func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
    NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: 1)
}

let navy = rgb(24, 26, 58)
let navyDeep = rgb(16, 18, 42)
let mint = rgb(163, 239, 200)

image.lockFocus()
NSGraphicsContext.current?.shouldAntialias = true

// Plate on the macOS grid, artwork sitting well inside it.
let margin = canvas * 0.08
let plate = NSRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)
let plateShape = NSBezierPath(roundedRect: plate,
                              xRadius: plate.width * 0.225,
                              yRadius: plate.width * 0.225)
plateShape.addClip()
NSGradient(colors: [navy, navyDeep], atLocations: [0, 1], colorSpace: .deviceRGB)?
    .draw(in: plate, angle: 90)

let stroke: CGFloat = 46
mint.setStroke()

// The silhouette: a scalloped crown over a fuller left side, with a short stem.
let outline = NSBezierPath()
outline.lineWidth = stroke
outline.lineCapStyle = .round
outline.lineJoinStyle = .round

let crownY: CGFloat = 596
outline.move(to: NSPoint(x: 306, y: 430))
outline.curve(to: NSPoint(x: 306, y: crownY),
              controlPoint1: NSPoint(x: 268, y: 494), controlPoint2: NSPoint(x: 272, y: 556))
for (x, radius) in [(374.0, 68.0), (502.0, 78.0), (632.0, 66.0)] {
    outline.appendArc(withCenter: NSPoint(x: x, y: crownY), radius: radius,
                      startAngle: 180, endAngle: 0, clockwise: true)
}
outline.curve(to: NSPoint(x: 718, y: 430),
              controlPoint1: NSPoint(x: 752, y: 556), controlPoint2: NSPoint(x: 756, y: 494))
outline.curve(to: NSPoint(x: 552, y: 322),
              controlPoint1: NSPoint(x: 692, y: 366), controlPoint2: NSPoint(x: 630, y: 322))
outline.curve(to: NSPoint(x: 512, y: 268),
              controlPoint1: NSPoint(x: 524, y: 322), controlPoint2: NSPoint(x: 524, y: 288))
outline.stroke()

// Base and stem, closing the shape without a hard corner.
let base = NSBezierPath()
base.lineWidth = stroke
base.lineCapStyle = .round
base.move(to: NSPoint(x: 306, y: 430))
base.curve(to: NSPoint(x: 512, y: 268),
           controlPoint1: NSPoint(x: 330, y: 330), controlPoint2: NSPoint(x: 410, y: 268))
base.stroke()

// Two folds. Both stop short of the outline so the mark stays open — folds that
// touch the edge close the shape into a face.
let foldA = NSBezierPath()
foldA.lineWidth = stroke
foldA.lineCapStyle = .round
foldA.move(to: NSPoint(x: 392, y: 486))
foldA.curve(to: NSPoint(x: 638, y: 470),
            controlPoint1: NSPoint(x: 470, y: 566), controlPoint2: NSPoint(x: 556, y: 396))
foldA.stroke()

let foldB = NSBezierPath()
foldB.lineWidth = stroke
foldB.lineCapStyle = .round
foldB.move(to: NSPoint(x: 512, y: 596))
foldB.curve(to: NSPoint(x: 512, y: 372),
            controlPoint1: NSPoint(x: 566, y: 520), controlPoint2: NSPoint(x: 452, y: 452))
foldB.stroke()

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
