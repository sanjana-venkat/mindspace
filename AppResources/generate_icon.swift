import AppKit

// MINDSPACE app icon — the brain as a handful of flowing lines rather than an
// outline: stacked waves that follow the shape of the mass, with a stem hooking
// off the lower right. One ink, one stroke weight, drawn straight into the
// final composition so nothing gets scaled twice.

let canvas = 1024.0
let rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let image = NSImage(size: rect.size)

func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
    NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: 1)
}

let navy = rgb(24, 26, 58)
let navyDeep = rgb(15, 17, 40)
let mint = rgb(168, 240, 205)

image.lockFocus()
NSGraphicsContext.current?.shouldAntialias = true

let margin = canvas * 0.08
let plate = NSRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)
let plateShape = NSBezierPath(roundedRect: plate,
                              xRadius: plate.width * 0.225,
                              yRadius: plate.width * 0.225)
plateShape.addClip()
NSGradient(colors: [navy, navyDeep], atLocations: [0, 1], colorSpace: .deviceRGB)?
    .draw(in: plate, angle: 90)

let stroke: CGFloat = 30
mint.setStroke()

func line(_ points: [NSPoint], _ controls: [(NSPoint, NSPoint)]) {
    let path = NSBezierPath()
    path.lineWidth = stroke
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: points[0])
    for (index, control) in controls.enumerated() {
        path.curve(to: points[index + 1], controlPoint1: control.0, controlPoint2: control.1)
    }
    path.stroke()
}

// The crown: one long line up and over the top, closing down the right side.
line([NSPoint(x: 306, y: 396), NSPoint(x: 552, y: 716), NSPoint(x: 722, y: 424)],
     [(NSPoint(x: 288, y: 604), NSPoint(x: 404, y: 716)),
      (NSPoint(x: 700, y: 716), NSPoint(x: 740, y: 560))])

// Three waves through the mass, each following the crown's curve and fading
// shorter as they descend.
line([NSPoint(x: 336, y: 556), NSPoint(x: 520, y: 594), NSPoint(x: 690, y: 556)],
     [(NSPoint(x: 396, y: 636), NSPoint(x: 452, y: 528)),
      (NSPoint(x: 592, y: 660), NSPoint(x: 636, y: 522))])

line([NSPoint(x: 330, y: 452), NSPoint(x: 512, y: 494), NSPoint(x: 694, y: 452)],
     [(NSPoint(x: 392, y: 534), NSPoint(x: 446, y: 424)),
      (NSPoint(x: 586, y: 562), NSPoint(x: 640, y: 418))])

line([NSPoint(x: 352, y: 356), NSPoint(x: 522, y: 396), NSPoint(x: 668, y: 364)],
     [(NSPoint(x: 408, y: 434), NSPoint(x: 460, y: 328)),
      (NSPoint(x: 592, y: 462), NSPoint(x: 624, y: 330))])

// The underside, gathering to the right and hooking down into the stem.
line([NSPoint(x: 372, y: 286), NSPoint(x: 560, y: 288), NSPoint(x: 648, y: 202)],
     [(NSPoint(x: 428, y: 246), NSPoint(x: 500, y: 248)),
      (NSPoint(x: 608, y: 318), NSPoint(x: 672, y: 268))])

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
