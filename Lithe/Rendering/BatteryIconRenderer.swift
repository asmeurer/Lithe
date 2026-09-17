import AppKit

/// Draws battery icons and composes them (with any text) into the image used
/// by the status item.
///
/// Images are created with a drawing handler, which macOS re-runs for each
/// appearance and backing scale, so dynamic colors such as `labelColor`
/// adapt to a light or dark menu bar without any manual tracking.
enum BatteryIconRenderer {
    /// Height of the vertical icons, in points.
    static let iconHeight: CGFloat = 16
    /// Horizontal gap between an icon and its text when composed together.
    static let textGap: CGFloat = 3
    /// Gap between multiple sources in one item.
    static let itemGap: CGFloat = 6

    static func nsColor(_ color: IconColor) -> NSColor {
        switch color {
        case .automatic: return .labelColor
        case .dimmed: return .secondaryLabelColor
        case .custom(let c): return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        }
    }

    static func menuBarFont() -> NSFont {
        NSFont.menuBarFont(ofSize: 0)
    }

    /// The size of the icon for a shape (excluding any text above).
    static func iconSize(for spec: IconSpec) -> NSSize {
        switch spec.shape {
        case .rectangular, .roundedWithTerminal: return NSSize(width: 10, height: iconHeight)
        case .rounded: return NSSize(width: 10, height: iconHeight)
        case .thin: return NSSize(width: 5, height: iconHeight)
        case .horizontal:
            if spec.textAbove != nil {
                return NSSize(width: 26, height: 17)
            }
            return NSSize(width: 24, height: 10)
        }
    }

    /// Renders a single icon as a resolution-independent image.
    static func image(for spec: IconSpec) -> NSImage {
        let size = iconSize(for: spec)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(spec, in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Draws the icon into `rect` in the current graphics context.
    static func draw(_ spec: IconSpec, in rect: NSRect) {
        let outline = nsColor(spec.outline)
        let fill = nsColor(spec.fill)
        let level = spec.level.map { min(1, max(0, $0)) }

        switch spec.shape {
        case .rectangular, .roundedWithTerminal, .rounded:
            let hasNub = spec.shape != .rounded
            let nubHeight: CGFloat = hasNub ? 1.5 : 0
            let nubWidth: CGFloat = 4
            let radius: CGFloat = spec.shape == .rectangular ? 0.5 : (spec.shape == .rounded ? 3 : 2)
            let body = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - nubHeight)
            if hasNub {
                let nub = NSRect(x: body.midX - nubWidth / 2, y: body.maxY - 0.5, width: nubWidth, height: nubHeight + 0.5)
                outline.setFill()
                NSBezierPath(roundedRect: nub, xRadius: 0.5, yRadius: 0.5).fill()
            }
            strokeOutline(body, radius: radius, color: outline)
            if let level {
                let inner = body.insetBy(dx: 2, dy: 2)
                let fillRect = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: (inner.height * level).rounded(.up))
                fill.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: max(0, radius - 1.5), yRadius: max(0, radius - 1.5)).fill()
            }

        case .thin:
            strokeOutline(rect, radius: 1.5, color: outline)
            if let level {
                let inner = rect.insetBy(dx: 1.5, dy: 1.5)
                let fillRect = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: (inner.height * level).rounded(.up))
                fill.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 0.5, yRadius: 0.5).fill()
            }

        case .horizontal:
            var body = rect
            if let text = spec.textAbove {
                let font = NSFont.systemFont(ofSize: 8, weight: .medium)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: outline]
                let string = NSAttributedString(string: text, attributes: attributes)
                let textSize = string.size()
                let textHeight: CGFloat = 9
                string.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.maxY - textHeight))
                body = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - textHeight - 1)
            }
            let nubWidth: CGFloat = 1.5
            let nubHeight: CGFloat = min(4, body.height / 2)
            let meter = NSRect(x: body.minX, y: body.minY, width: body.width - nubWidth, height: body.height)
            let nub = NSRect(x: meter.maxX - 0.5, y: body.midY - nubHeight / 2, width: nubWidth + 0.5, height: nubHeight)
            outline.setFill()
            NSBezierPath(roundedRect: nub, xRadius: 0.5, yRadius: 0.5).fill()
            strokeOutline(meter, radius: 2, color: outline)
            if let level {
                let inner = meter.insetBy(dx: 2, dy: 2)
                let fillRect = NSRect(x: inner.minX, y: inner.minY, width: (inner.width * level).rounded(.up), height: inner.height)
                fill.setFill()
                NSBezierPath(roundedRect: fillRect, xRadius: 0.5, yRadius: 0.5).fill()
            }
        }
    }

    private static func strokeOutline(_ rect: NSRect, radius: CGFloat, color: NSColor) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        path.lineWidth = 1
        color.setStroke()
        path.stroke()
    }

    /// Composes several sources (each an icon and/or text) into one image.
    /// Used when more than one power source is displayed, since a status item
    /// has only a single title.
    static func composedImage(items: [ItemPresentation], font: NSFont? = nil) -> NSImage? {
        let font = font ?? menuBarFont()
        struct Part {
            var icon: IconSpec?
            var text: NSAttributedString?
            var width: CGFloat
        }
        var parts: [Part] = []
        for item in items where !item.isEmpty {
            var width: CGFloat = 0
            var text: NSAttributedString?
            if let icon = item.icon { width += iconSize(for: icon).width }
            if let t = item.text {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor(item.textColor)]
                let s = NSAttributedString(string: t, attributes: attributes)
                text = s
                width += (item.icon == nil ? 0 : textGap) + s.size().width.rounded(.up)
            }
            parts.append(Part(icon: item.icon, text: text, width: width))
        }
        guard !parts.isEmpty else { return nil }
        let height: CGFloat = 18
        let totalWidth = parts.map(\.width).reduce(0, +) + CGFloat(parts.count - 1) * itemGap
        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
            var x = rect.minX
            for part in parts {
                if let icon = part.icon {
                    let size = iconSize(for: icon)
                    draw(icon, in: NSRect(x: x, y: rect.midY - size.height / 2, width: size.width, height: size.height))
                    x += size.width + (part.text == nil ? 0 : textGap)
                }
                if let text = part.text {
                    let size = text.size()
                    text.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))
                    x += size.width.rounded(.up)
                }
                x += itemGap
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
