import AppKit

// MINDSPACE app icon — one flat shape, drawn to survive the Dock. The tell for
// "brain" at 32 points is a scalloped crown and two fat grooves, not fold
// detail: anything finer turns to mush beside a flat mark like Figma's or
// QuickTime's. Deterministic source — re-render it, don't replace it.

let canvas = 1024.0
let rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let image = NSImage(size: rect.size)

func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
    NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: 1)
}

let navy = rgb(24, 26, 58)
let navyDeep = rgb(16, 18, 42)
let mint = rgb(150, 232, 190)

image.lockFocus()

// The plate, inset so the icon sits on the macOS grid rather than filling it.
let margin = canvas * 0.08
let plate = NSRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)
let plateShape = NSBezierPath(roundedRect: plate,
                              xRadius: plate.width * 0.225,
                              yRadius: plate.width * 0.225)
plateShape.addClip()
NSGradient(colors: [navy, navyDeep], atLocations: [0, 1], colorSpace: .deviceRGB)?
    .draw(in: plate, angle: 90)

// The silhouette does all the work. Bumps right around the upper perimeter say
// "brain" on their own; interior grooves at this size only ever read as a face.
let brain = NSBezierPath()
let centre = NSPoint(x: 512, y: 520)

// Lobes placed around the mass, largest at the crown, tucking in at the base.
let lobes: [(angle: Double, distance: CGFloat, radius: CGFloat)] = [
    (100, 156, 132),   // crown left
    (58, 168, 120),    // crown right
    (146, 150, 118),   // upper left
    (16, 158, 112),    // upper right
    (188, 132, 104),   // left
    (348, 140, 100),   // right
    (232, 118, 96),    // lower left
    (302, 122, 92),    // lower right
    (268, 96, 104)     // base
]

for lobe in lobes {
    let radians = lobe.angle * .pi / 180
    let point = NSPoint(x: centre.x + cos(radians) * lobe.distance,
                        y: centre.y + sin(radians) * lobe.distance)
    let circle = NSBezierPath(ovalIn: NSRect(x: point.x - lobe.radius, y: point.y - lobe.radius,
                                             width: lobe.radius * 2, height: lobe.radius * 2))
    brain.append(circle)
}
brain.append(NSBezierPath(ovalIn: NSRect(x: centre.x - 150, y: centre.y - 140,
                                         width: 300, height: 280)))
brain.windingRule = .nonZero

mint.setFill()
brain.fill()

// One notch out of the base, so the mass has a front and a back rather than
// reading as a cloud.
NSGraphicsContext.saveGraphicsState()
navyDeep.setFill()
let notch = NSBezierPath(ovalIn: NSRect(x: 452, y: 236, width: 132, height: 108))
notch.fill()
NSGraphicsContext.restoreGraphicsState()

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
