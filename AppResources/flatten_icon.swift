import AppKit
import CoreImage

// Bolds a finely-hatched mark so it survives Dock sizes: blur the hatching
// until the strokes merge into solid mass, then push contrast so what's left is
// two tones rather than a grey mush. Keeps the shape that was drawn; loses the
// detail that was never going to render at 32 points anyway.
//
//   swift flatten_icon.swift <input.png> <output.png> [blur] [contrast]

let arguments = CommandLine.arguments
guard arguments.count >= 3,
      let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
      let input = CIImage(data: data) else {
    fatalError("usage: flatten_icon.swift <input.png> <output.png> [blur] [contrast]")
}
let blurRadius = arguments.count > 3 ? Double(arguments[3]) ?? 12 : 12
let contrast = arguments.count > 4 ? Double(arguments[4]) ?? 3.2 : 3.2

let context = CIContext()
var working = input

// Dilate first: thin bright strokes on a dark ground need to grow into each
// other. Blurring instead just averages them toward the background, which is
// how the first attempt came out nearly black.
if let dilate = CIFilter(name: "CIMorphologyMaximum") {
    dilate.setValue(working, forKey: kCIInputImageKey)
    dilate.setValue(blurRadius, forKey: "inputRadius")
    if let output = dilate.outputImage { working = output.cropped(to: input.extent) }
}

if let smooth = CIFilter(name: "CIGaussianBlur") {
    smooth.setValue(working, forKey: kCIInputImageKey)
    smooth.setValue(blurRadius * 0.35, forKey: kCIInputRadiusKey)
    if let output = smooth.outputImage { working = output.cropped(to: input.extent) }
}

if let mono = CIFilter(name: "CIPhotoEffectMono") {
    mono.setValue(working, forKey: kCIInputImageKey)
    if let output = mono.outputImage { working = output.cropped(to: input.extent) }
}

if let controls = CIFilter(name: "CIColorControls") {
    controls.setValue(working, forKey: kCIInputImageKey)
    controls.setValue(contrast, forKey: kCIInputContrastKey)
    controls.setValue(0.02, forKey: kCIInputBrightnessKey)
    if let output = controls.outputImage { working = output.cropped(to: input.extent) }
}

// One ink on one ground. Mapping luminance to exactly two colours is what stops
// the mark drifting between mint and white across its own surface.
if let falseColour = CIFilter(name: "CIFalseColor") {
    falseColour.setValue(working, forKey: kCIInputImageKey)
    falseColour.setValue(CIColor(red: 0.078, green: 0.086, blue: 0.196), forKey: "inputColor0")
    falseColour.setValue(CIColor(red: 0.639, green: 0.937, blue: 0.792), forKey: "inputColor1")
    if let output = falseColour.outputImage { working = output.cropped(to: input.extent) }
}

guard let cg = context.createCGImage(working, from: input.extent) else {
    fatalError("Could not flatten the mark")
}
let rep = NSBitmapImageRep(cgImage: cg)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the flattened mark")
}
try png.write(to: URL(fileURLWithPath: arguments[2]))
print("Wrote \(arguments[2])")
