// Compose the 1024x1024 transparent app-icon master from the source sticker PNG.
//
// Usage: swift compose-icon-master.swift <source.png> <out.png>
//
// The source is scaled proportionally so its longest side is at most 1000 px
// (leaving >=12 px transparent margin on every side of the 1024x1024 canvas),
// then centered. No stretching, no background plate, no mask, no cropping:
// the irregular silhouette and its alpha channel are preserved as-is.

import AppKit

let canvasSize = 1024
let maxContentSide = 1000

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("usage: swift compose-icon-master.swift <source.png> <out.png>\n".data(using: .utf8)!)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = NSImage(contentsOf: sourceURL),
      let tiff = source.tiffRepresentation,
      let sourceRep = NSBitmapImageRep(data: tiff) else {
    FileHandle.standardError.write("error: cannot read PNG at \(sourceURL.path)\n".data(using: .utf8)!)
    exit(1)
}

let sourceWidth = sourceRep.pixelsWide
let sourceHeight = sourceRep.pixelsHigh
let scale = min(Double(maxContentSide) / Double(max(sourceWidth, sourceHeight)), 1.0)
let contentWidth = max(1, Int((Double(sourceWidth) * scale).rounded(.down)))
let contentHeight = max(1, Int((Double(sourceHeight) * scale).rounded(.down)))
let originX = (canvasSize - contentWidth) / 2
let originY = (canvasSize - contentHeight) / 2

guard let canvasRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write("error: cannot allocate 1024x1024 canvas\n".data(using: .utf8)!)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: canvasRep)
NSGraphicsContext.current = context
context?.imageInterpolation = .high
source.draw(
    in: NSRect(x: originX, y: originY, width: contentWidth, height: contentHeight),
    from: .zero,
    operation: .copy,
    fraction: 1.0
)
NSGraphicsContext.restoreGraphicsState()

guard let png = canvasRep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("error: cannot encode PNG\n".data(using: .utf8)!)
    exit(1)
}
do {
    try png.write(to: outputURL)
} catch {
    FileHandle.standardError.write("error: cannot write \(outputURL.path): \(error)\n".data(using: .utf8)!)
    exit(1)
}

FileHandle.standardError.write("master: source \(sourceWidth)x\(sourceHeight) -> content \(contentWidth)x\(contentHeight) at (\(originX), \(originY)) on 1024x1024 canvas\n".data(using: .utf8)!)
