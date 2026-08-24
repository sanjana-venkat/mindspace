import AppKit

// NOTED app icon — the paper, margin rule, pebble, and Kami crane distilled
// into one mark. Keep this source deterministic so design can evolve without
// replacing an opaque bitmap asset.

let size = 1024.0
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: rect.size)

let sand = NSColor(calibratedRed: 248/255, green: 244/255, blue: 236/255, alpha: 1)
let card = NSColor(calibratedRed: 254/255, green: 253/255, blue: 250/255, alpha: 1)
let ink = NSColor(calibratedRed: 31/255, green: 30/255, blue: 26/255, alpha: 1)
let rose = NSColor(calibratedRed: 199/255, green: 154/255, blue: 144/255, alpha: 1)
let tan = NSColor(calibratedRed: 240/255, green: 211/255, blue: 162/255, alpha: 1)

image.lockFocus()

// Warm sheet of paper.
let outer = NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24), xRadius: 224, yRadius: 224)
sand.setFill()
outer.fill()
outer.addClip()

// Kami's perch. The crane itself is the logo; the pebble only gives the white
// folded paper enough contrast at small macOS icon sizes.
let pebble = NSBezierPath()
pebble.move(to: NSPoint(x: 150, y: 486))
pebble.curve(to: NSPoint(x: 394, y: 826), controlPoint1: NSPoint(x: 134, y: 690), controlPoint2: NSPoint(x: 228, y: 810))
pebble.curve(to: NSPoint(x: 812, y: 770), controlPoint1: NSPoint(x: 586, y: 874), controlPoint2: NSPoint(x: 784, y: 858))
pebble.curve(to: NSPoint(x: 892, y: 366), controlPoint1: NSPoint(x: 934, y: 642), controlPoint2: NSPoint(x: 954, y: 472))
pebble.curve(to: NSPoint(x: 526, y: 176), controlPoint1: NSPoint(x: 810, y: 224), controlPoint2: NSPoint(x: 668, y: 154))
pebble.curve(to: NSPoint(x: 150, y: 486), controlPoint1: NSPoint(x: 302, y: 144), controlPoint2: NSPoint(x: 134, y: 308))
pebble.close()
tan.setFill()
pebble.fill()

// Kami, drawn as crisp folded paper. The bold outline survives 16px output.
func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
    let origin = NSPoint(x: 216, y: 244)
    let scaleX: CGFloat = 22.0
    let scaleY: CGFloat = 21.0
    return NSPoint(x: origin.x + x * scaleX, y: origin.y + y * scaleY)
}

let crane = NSBezierPath()
crane.move(to: p(4, 8))
crane.line(to: p(15, 22))
crane.line(to: p(20, 16))
crane.line(to: p(28, 26))
crane.line(to: p(30, 18))
crane.line(to: p(22, 10))
crane.line(to: p(14, 6))
crane.close()
crane.lineJoinStyle = .round
card.setFill()
crane.fill()
ink.setStroke()
crane.lineWidth = 15
crane.stroke()

let folds = NSBezierPath()
folds.move(to: p(15, 22))
folds.line(to: p(20, 16))
folds.line(to: p(14, 6))
folds.move(to: p(4, 8))
folds.line(to: p(20, 16))
folds.line(to: p(22, 10))
folds.lineWidth = 10
folds.lineJoinStyle = .round
ink.setStroke()
folds.stroke()

// Dusty-rose beak stitch and a tiny ink eye.
let beak = NSBezierPath()
beak.move(to: p(28, 26))
beak.line(to: p(26.5, 28.2))
beak.lineWidth = 13
beak.lineCapStyle = .round
rose.setStroke()
beak.stroke()

ink.setFill()
NSBezierPath(ovalIn: NSRect(x: p(27.5, 24.7).x - 8, y: p(27.5, 24.7).y - 8, width: 16, height: 16)).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render icon")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: outputURL)
print("Wrote icon to \(outputURL.path)")
