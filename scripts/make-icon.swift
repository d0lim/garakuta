#!/usr/bin/env swift
// Builds Resources/AppIcon.icns from Resources/Logo.png.
//
// The logo is a rounded cream tile with generous transparent padding. macOS app icons live on a fixed grid:
// a 1024 pt canvas whose icon shape is an 824 pt rounded square centred in it. This script trims the padding,
// re-masks the artwork to that shape and writes every size the icon set needs.
//
//   swift scripts/make-icon.swift [source.png] [output.icns]
import AppKit

let args = CommandLine.arguments
let sourcePath = args.count > 1 ? args[1] : "Resources/Logo.png"
let outputPath = args.count > 2 ? args[2] : "Resources/AppIcon.icns"

guard let source = NSImage(contentsOfFile: sourcePath),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot read \(sourcePath)")
}
let rep = NSBitmapImageRep(cgImage: cg)
let width = rep.pixelsWide, height = rep.pixelsHigh

// Opaque bounding box.
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width where rep.colorAt(x: x, y: y)!.alphaComponent > 0.02 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
let artwork = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
// Tile colour, sampled just inside the top edge (the tile is a flat fill).
let fill = rep.colorAt(x: width / 2, y: minY + 20)!.usingColorSpace(.sRGB)!

func render(size: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.interpolationQuality = .high
    let s = CGFloat(size)
    let tile = CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let radius = tile.width * 0.2237
    let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    shape.addClip()
    fill.setFill()
    shape.fill()
    // Aspect-fill the trimmed artwork over the tile. Its own, tighter corners fall outside the clip.
    let aw = CGFloat(artwork.width), ah = CGFloat(artwork.height)
    let scale = max(tile.width / aw, tile.height / ah)
    let drawn = CGRect(x: tile.midX - aw * scale / 2, y: tile.midY - ah * scale / 2, width: aw * scale, height: ah * scale)
    ctx.cgContext.draw(artwork, in: drawn)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("Garakuta-\(ProcessInfo.processInfo.processIdentifier).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for (suffix, scale) in [("", 1), ("@2x", 2)] {
        let png = render(size: base * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputPath]
try iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote \(outputPath) from \(artwork.width)x\(artwork.height) artwork")
