import AppKit

// Puts a generated mark on the macOS icon grid: trims the white surround the
// generator leaves, fills the squircle with the mark's own background colour,
// and sets the artwork inside it at a size that leaves the breathing room every
// other icon in the Dock has.
//
//   swift mask_icon.swift <input.png> <output.png> [trim] [contentScale]

let arguments = CommandLine.arguments
guard arguments.count >= 3, let source = NSImage(contentsOfFile: arguments[1]) else {
    fatalError("usage: mask_icon.swift <input.png> <output.png> [trim] [contentScale]")
}
let output = arguments[2]
let trim = arguments.count > 3 ? Double(arguments[3]) ?? 0.06 : 0.06
let contentScale = arguments.count > 4 ? Double(arguments[4]) ?? 0.84 : 0.84

let canvas = 1024.0
let sourceSize = source.size
let inset = min(sourceSize.width, sourceSize.height) * trim
let cropped = NSRect(x: inset, y: inset,
                     width: sourceSize.width - inset * 2,
                     height: sourceSize.height - inset * 2)

// The macOS icon grid: the artwork is a squircle inset from the canvas, with
// transparency around it. Scaling the mark's own square — background included —
// is what gives the Dock its breathing room, and it leaves no seam to hide.
let margin = canvas * (1 - contentScale) / 2
let plate = NSRect(x: margin, y: margin, width: canvas - margin * 2, height: canvas - margin * 2)

let result = NSImage(size: NSSize(width: canvas, height: canvas))
result.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let shape = NSBezierPath(roundedRect: plate,
                         xRadius: plate.width * 0.225,
                         yRadius: plate.width * 0.225)
shape.addClip()
source.draw(in: plate, from: cropped, operation: .copy, fraction: 1)

result.unlockFocus()

guard let tiff = result.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not write the masked icon")
}
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
