import AppKit

// Trims the white surround off a generated mark and re-masks it to the macOS
// icon shape: artwork inside a squircle, everything outside transparent.
// Without this the Dock draws the source PNG's white corners as a frame.

let arguments = CommandLine.arguments
guard arguments.count >= 3,
      let source = NSImage(contentsOfFile: arguments[1]) else {
    fatalError("usage: mask_icon.swift <input.png> <output.png> [trimFraction]")
}
let output = arguments[2]
let trim = arguments.count > 3 ? Double(arguments[3]) ?? 0.055 : 0.055

let canvas = 1024.0
let sourceSize = source.size
let inset = min(sourceSize.width, sourceSize.height) * trim
let cropped = NSRect(x: inset, y: inset,
                     width: sourceSize.width - inset * 2,
                     height: sourceSize.height - inset * 2)

// macOS leaves a margin around the squircle; matching it keeps the icon the
// same visual weight as everything else in the Dock.
let margin = canvas * 0.028
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
