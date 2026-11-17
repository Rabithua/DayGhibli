// Render the menu bar icon PNG from the Totoro SVG.
//
// Usage: swift render-menubar-icon.swift <MenuBarIcon.svg> <MenuBarIcon.png>
//
// The SVG is rasterised with NSImage, tightly cropped to the visible content
// (any non-zero alpha), and written as a transparent-background PNG whose
// height is exactly 64 px with a proportional width. The eye whites in the
// artwork are holes in the silhouette (alpha = 0) while the body, irises and
// pupils stay opaque, so the PNG can be rendered as an NSImage template.

import AppKit

let outputHeight = 64
let rasterScale = 10.0

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("usage: swift render-menubar-icon.swift <MenuBarIcon.svg> <MenuBarIcon.png>\n".data(using: .utf8)!)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write("error: cannot read SVG at \(sourceURL.path)\n".data(using: .utf8)!)
    exit(1)
}
let baseSize = source.size

// Rasterise at 10x so the tight-crop bounds have sub-pixel-free precision.
let rasterWidth = Int((baseSize.width * rasterScale).rounded())
let rasterHeight = Int((baseSize.height * rasterScale).rounded())
guard let rasterRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: rasterWidth,
    pixelsHigh: rasterHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let rasterData = rasterRep.bitmapData else {
    FileHandle.standardError.write("error: cannot allocate raster buffer\n".data(using: .utf8)!)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
let rasterContext = NSGraphicsContext(bitmapImageRep: rasterRep)
NSGraphicsContext.current = rasterContext
rasterContext?.imageInterpolation = .high
// The bitmap context's coordinate space is its pixel grid, so draw the vector
// SVG scaled up to the full raster (10x) for crisp, precise crop bounds.
source.draw(in: NSRect(x: 0, y: 0, width: rasterRep.pixelsWide, height: rasterRep.pixelsHigh))
NSGraphicsContext.restoreGraphicsState()

// Find the tight bounding box of visible content (row 0 is the top scanline,
// the alpha byte is the fourth byte of each RGBA pixel).
let bytesPerRow = rasterRep.bytesPerRow
var minX = rasterWidth
var minY = rasterHeight
var maxX = -1
var maxY = -1
for row in 0..<rasterHeight {
    let rowStart = rasterData + row * bytesPerRow
    for column in 0..<rasterWidth {
        let alpha = rowStart[column * 4 + 3]
        if alpha > 0 {
            if column < minX { minX = column }
            if column > maxX { maxX = column }
            if row < minY { minY = row }
            if row > maxY { maxY = row }
        }
    }
}
guard maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write("error: rendered SVG has no visible content\n".data(using: .utf8)!)
    exit(1)
}

// Convert the pixel bounding box (top-origin rows) into a source rect in the
// NSImage point space (bottom-origin).
let cropRect = NSRect(
    x: CGFloat(minX) / rasterScale,
    y: (CGFloat(rasterHeight - 1 - maxY)) / rasterScale,
    width: CGFloat(maxX - minX + 1) / rasterScale,
    height: CGFloat(maxY - minY + 1) / rasterScale
)

let outputWidth = max(1, Int((CGFloat(outputHeight) * cropRect.width / cropRect.height).rounded()))
guard let outputRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: outputWidth,
    pixelsHigh: outputHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write("error: cannot allocate output buffer\n".data(using: .utf8)!)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
let outputContext = NSGraphicsContext(bitmapImageRep: outputRep)
NSGraphicsContext.current = outputContext
outputContext?.imageInterpolation = .high
source.draw(
    in: NSRect(x: 0, y: 0, width: CGFloat(outputWidth), height: CGFloat(outputHeight)),
    from: cropRect,
    operation: .copy,
    fraction: 1.0
)
NSGraphicsContext.restoreGraphicsState()

guard let png = outputRep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("error: cannot encode PNG\n".data(using: .utf8)!)
    exit(1)
}
do {
    try png.write(to: outputURL)
} catch {
    FileHandle.standardError.write("error: cannot write \(outputURL.path): \(error)\n".data(using: .utf8)!)
    exit(1)
}

FileHandle.standardError.write("menubar: svg \(baseSize.width)x\(baseSize.height) -> crop (\(cropRect.origin.x), \(cropRect.origin.y)) \(cropRect.width)x\(cropRect.height) -> \(outputWidth)x\(outputHeight)\n".data(using: .utf8)!)
