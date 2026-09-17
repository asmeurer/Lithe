#!/usr/bin/env swift
// Generates the app icon: a slim battery on a rounded background, written as
// the PNG sizes an .appiconset needs. Run `make icon` after changing it.
import AppKit

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Lithe/Assets.xcassets/AppIcon.appiconset"

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size / 1024

    // Background: macOS-style rounded square with a soft vertical gradient.
    let inset = 100 * s
    let bgRect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185 * s, yRadius: 185 * s)
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.27, alpha: 1),
                              ending: NSColor(srgbRed: 0.07, green: 0.09, blue: 0.13, alpha: 1))!
    gradient.draw(in: bg, angle: -90)

    // Battery body.
    let bodyWidth = 300 * s
    let bodyHeight = 560 * s
    let body = NSRect(x: (size - bodyWidth) / 2, y: (size - bodyHeight) / 2 - 30 * s, width: bodyWidth, height: bodyHeight)
    let terminal = NSRect(x: body.midX - 70 * s, y: body.maxY - 4 * s, width: 140 * s, height: 60 * s)

    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: terminal, xRadius: 22 * s, yRadius: 22 * s).fill()

    let outline = NSBezierPath(roundedRect: body, xRadius: 64 * s, yRadius: 64 * s)
    outline.lineWidth = 40 * s
    NSColor.white.withAlphaComponent(0.95).setStroke()
    outline.stroke()

    // Fill level.
    let inner = body.insetBy(dx: 64 * s, dy: 64 * s)
    let level: CGFloat = 0.72
    let fillRect = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * level)
    let fill = NSGradient(starting: NSColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 1),
                          ending: NSColor(srgbRed: 0.20, green: 0.72, blue: 0.36, alpha: 1))!
    fill.draw(in: NSBezierPath(roundedRect: fillRect, xRadius: 30 * s, yRadius: 30 * s), angle: 90)

    image.unlockFocus()
    return image
}

func write(_ image: NSImage, pixels: Int, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: url)
}

let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
let directory = URL(fileURLWithPath: outputDirectory)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

var images: [[String: String]] = []
for (points, scale) in sizes {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)@\(scale)x.png"
    try write(draw(size: CGFloat(pixels)), pixels: pixels, to: directory.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: directory.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(directory.path)")
