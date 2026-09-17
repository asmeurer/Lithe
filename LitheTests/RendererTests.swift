import AppKit
import Testing
@testable import Lithe

/// Rendering tests draw every shape into a bitmap to make sure nothing traps
/// and that the fill actually varies with the charge level.
@MainActor
struct RendererTests {
    private func bitmap(_ image: NSImage, scale: CGFloat = 2) -> NSBitmapImageRep {
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func opaquePixels(_ rep: NSBitmapImageRep, minimumAlpha: CGFloat = 0.5) -> Int {
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > minimumAlpha {
                count += 1
            }
        }
        return count
    }

    @Test func everyShapeRendersAtEveryLevel() {
        for shape in IconShape.allCases {
            var previous = -1
            for level in stride(from: 0.0, through: 1.0, by: 0.25) {
                let spec = IconSpec(shape: shape, level: level, isPresent: true,
                                    fill: .custom(.green), outline: .custom(RGBA(red: 0, green: 0, blue: 0)),
                                    textAbove: shape == .horizontal ? "50%" : nil)
                let image = BatteryIconRenderer.image(for: spec)
                #expect(image.size == BatteryIconRenderer.iconSize(for: spec))
                let pixels = opaquePixels(bitmap(image))
                #expect(pixels > 0, "\(shape) drew nothing at \(level)")
                #expect(pixels >= previous, "\(shape) fill shrank from \(previous) to \(pixels) at \(level)")
                previous = pixels
            }
        }
    }

    @Test func fullIsVisiblyFullerThanEmpty() {
        for shape in IconShape.allCases {
            let empty = IconSpec(shape: shape, level: 0, isPresent: true, fill: .custom(.green), outline: .automatic, textAbove: nil)
            let full = IconSpec(shape: shape, level: 1, isPresent: true, fill: .custom(.green), outline: .automatic, textAbove: nil)
            let e = opaquePixels(bitmap(BatteryIconRenderer.image(for: empty)))
            let f = opaquePixels(bitmap(BatteryIconRenderer.image(for: full)))
            #expect(f > e + 10, "\(shape): empty=\(e) full=\(f)")
        }
    }

    @Test func removedBatteryDrawsOnlyAnOutline() {
        let spec = IconSpec(shape: .roundedWithTerminal, level: nil, isPresent: false, fill: .dimmed, outline: .dimmed, textAbove: nil)
        let image = BatteryIconRenderer.image(for: spec)
        let rep = bitmap(image)
        // Center pixel of the body must be transparent (no fill).
        let center = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)
        #expect((center?.alphaComponent ?? 1) < 0.1)
        // The dimmed outline is translucent, so use a low threshold.
        #expect(opaquePixels(rep, minimumAlpha: 0.15) > 0)
    }

    @Test func composedImageCoversAllItems() throws {
        let icon = IconSpec(shape: .rectangular, level: 0.5, isPresent: true, fill: .automatic, outline: .automatic, textAbove: nil)
        let items = [
            ItemPresentation(icon: icon, text: "50%", textColor: .automatic),
            ItemPresentation(icon: icon, text: nil, textColor: .automatic),
            ItemPresentation(icon: nil, text: "1:23", textColor: .custom(.red)),
        ]
        let image = try #require(BatteryIconRenderer.composedImage(items: items))
        #expect(image.size.width > 3 * BatteryIconRenderer.iconSize(for: icon).width)
        #expect(opaquePixels(bitmap(image)) > 0)
        #expect(BatteryIconRenderer.composedImage(items: [ItemPresentation(icon: nil, text: nil, textColor: .automatic)]) == nil)
    }

    @Test func colorsResolve() {
        #expect(BatteryIconRenderer.nsColor(.automatic) == .labelColor)
        #expect(BatteryIconRenderer.nsColor(.dimmed) == .secondaryLabelColor)
        let c = BatteryIconRenderer.nsColor(.custom(RGBA(red: 1, green: 0, blue: 0)))
        #expect(c.usingColorSpace(.sRGB)?.redComponent == 1)
    }
}
