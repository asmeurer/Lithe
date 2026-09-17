import Foundation

/// A color to draw with, after the user's setting has been applied to the
/// current battery state.
enum IconColor: Equatable, Sendable {
    /// The menu bar's text color (adapts to light and dark menu bars).
    case automatic
    /// A dimmed color used for a battery that is not present.
    case dimmed
    case custom(RGBA)

    init(_ setting: ColorSetting) {
        switch setting {
        case .automatic: self = .automatic
        case .custom(let c): self = .custom(c)
        }
    }
}

/// Everything the renderer needs to draw one battery icon.
struct IconSpec: Equatable, Sendable {
    var shape: IconShape
    /// Fill level in `0...1`; `nil` draws an empty outline.
    var level: Double?
    var isPresent: Bool
    var fill: IconColor
    var outline: IconColor
    /// Text drawn above the meter, used by the horizontal shape.
    var textAbove: String?
}

/// One power source's contribution to the menu bar item.
struct ItemPresentation: Equatable, Sendable {
    var icon: IconSpec?
    /// Text shown next to the icon (or on its own).
    var text: String?
    var textColor: IconColor

    var isEmpty: Bool { icon == nil && text == nil }
}

/// The complete description of what the menu bar item should look like and
/// say. Computed purely from a snapshot and the settings so it can be tested.
struct StatusPresentation: Equatable, Sendable {
    var items: [ItemPresentation]
    /// One human-readable line per displayed source, for the menu and tooltip.
    var summaryLines: [String]

    var isEmpty: Bool { items.allSatisfy(\.isEmpty) }
    var tooltip: String { summaryLines.joined(separator: "\n") }

    static func make(snapshot: PowerSnapshot, settings: DisplaySettings) -> StatusPresentation {
        var sources = snapshot.sources.filter { source in
            switch source.kind {
            case .internalBattery, .unknown: return true
            case .ups: return settings.showUPS
            }
        }
        if settings.reverseOrder { sources.reverse() }

        var items: [ItemPresentation] = []
        var lines: [String] = []

        if sources.isEmpty {
            lines.append("No battery present")
            if settings.showRemovedBattery {
                items.append(ItemPresentation(icon: removedIcon(settings), text: nil, textColor: .automatic))
            }
            return StatusPresentation(items: items, summaryLines: lines)
        }

        for source in sources {
            lines.append(summary(for: source, lowPowerMode: snapshot.lowPowerMode))
            guard source.isPresent else {
                if settings.showRemovedBattery {
                    items.append(ItemPresentation(icon: removedIcon(settings), text: nil, textColor: .automatic))
                }
                continue
            }
            items.append(item(for: source, settings: settings))
        }
        return StatusPresentation(items: items, summaryLines: lines)
    }

    private static func removedIcon(_ settings: DisplaySettings) -> IconSpec {
        IconSpec(shape: settings.shape, level: nil, isPresent: false, fill: .dimmed, outline: .dimmed, textAbove: nil)
    }

    private static func item(for source: PowerSource, settings: DisplaySettings) -> ItemPresentation {
        let mode = settings.mode(for: source.state)
        guard mode != .hidden else {
            return ItemPresentation(icon: nil, text: nil, textColor: .automatic)
        }

        let isLow = settings.lowColorEnabled && (source.percent ?? 100) < settings.lowColorPercent
        let fill: IconColor = isLow ? IconColor(settings.lowColor) : IconColor(settings.fillColor(for: source.state))
        let outline: IconColor = isLow ? IconColor(settings.lowColor) : IconColor(settings.outlineColor)

        var text: String?
        if mode.showsPercent {
            text = TimeFormatting.percent(source.percent)
        } else if mode.showsTime, source.state != .charged {
            text = TimeFormatting.clock(minutes: source.relevantMinutes)
        }

        var icon: IconSpec?
        if mode.showsIcon {
            icon = IconSpec(shape: settings.shape, level: source.charge, isPresent: true, fill: fill, outline: outline, textAbove: nil)
            if settings.shape == .horizontal, let t = text {
                // The horizontal shape prints its text above the meter.
                icon?.textAbove = t
                text = nil
            }
        }
        // With no icon in a time/percent-only mode there is nothing to show
        // while the value is unknown except the placeholder, which is fine.
        return ItemPresentation(icon: icon, text: text, textColor: outline)
    }

    /// A one-line description of a source, e.g. "On battery: 2 hours 30
    /// minutes remaining (80%)".
    static func summary(for source: PowerSource, lowPowerMode: Bool = false) -> String {
        let prefix = source.kind == .ups ? "\(source.name): " : ""
        guard source.isPresent else { return prefix + "Battery not present" }
        let pct = TimeFormatting.percent(source.percent)
        var line: String
        switch source.state {
        case .onBattery:
            if let m = source.minutesToEmpty {
                line = "On battery: \(TimeFormatting.spoken(minutes: m)) remaining (\(pct))"
            } else {
                line = "On battery: calculating time remaining (\(pct))"
            }
        case .charging:
            if let m = source.minutesToFull {
                line = "Charging: \(TimeFormatting.spoken(minutes: m)) until full (\(pct))"
            } else {
                line = "Charging (\(pct))"
            }
        case .charged:
            if source.percent == 100 || (source.isCharged && source.percent == nil) {
                line = "Fully charged"
            } else if source.isCharged {
                // macOS reports "charged" from about 95% up.
                line = "Charged (\(pct))"
            } else if source.chargeOnHold {
                line = "Charging on hold (\(pct))"
            } else {
                line = "On external power, not charging (\(pct))"
            }
        }
        if lowPowerMode && source.kind != .ups {
            line += " · Low Power Mode"
        }
        return prefix + line
    }
}
