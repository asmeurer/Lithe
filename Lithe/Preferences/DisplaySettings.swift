import Foundation

/// What to put in the menu bar for a given power state.
///
/// The raw values match the order of the original SlimBatteryMonitor popup so
/// that old preferences can be imported directly.
enum DisplayMode: Int, Codable, CaseIterable, Sendable, Identifiable {
    case hidden = 0
    case icon = 1
    case iconAndPercent = 2
    case iconAndTime = 3
    case percent = 4
    case time = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .hidden: return "Hide"
        case .icon: return "Icon"
        case .iconAndPercent: return "Icon and percent charge"
        case .iconAndTime: return "Icon and time remaining"
        case .percent: return "Percent charge only"
        case .time: return "Time remaining only"
        }
    }

    var showsIcon: Bool {
        switch self {
        case .icon, .iconAndPercent, .iconAndTime: return true
        case .hidden, .percent, .time: return false
        }
    }

    var showsPercent: Bool { self == .iconAndPercent || self == .percent }
    var showsTime: Bool { self == .iconAndTime || self == .time }
}

/// The outline of the battery icon. Raw values match SlimBatteryMonitor's
/// shape popup for preference import.
enum IconShape: Int, Codable, CaseIterable, Sendable, Identifiable {
    case rectangular = 0
    case roundedWithTerminal = 1
    case thin = 2
    case rounded = 3
    case horizontal = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .rectangular: return "Rectangular"
        case .roundedWithTerminal: return "Rounded with terminal"
        case .thin: return "Thin"
        case .rounded: return "Rounded"
        case .horizontal: return "Horizontal"
        }
    }
}

/// A color that is either chosen automatically (so it adapts to a light or
/// dark menu bar) or fixed by the user.
enum ColorSetting: Codable, Equatable, Sendable {
    case automatic
    case custom(RGBA)

    var isAutomatic: Bool {
        if case .automatic = self { return true }
        return false
    }

    var customColor: RGBA? {
        if case .custom(let c) = self { return c }
        return nil
    }
}

/// A device-independent sRGB color with components in `0...1`.
struct RGBA: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA` (the leading `#` is optional).
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        } else {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        }
    }

    var hex: String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X", byte(red), byte(green), byte(blue), byte(alpha))
    }

    static let orange = RGBA(red: 1.0, green: 0.55, blue: 0.0)
    static let green = RGBA(red: 0.2, green: 0.78, blue: 0.35)
    static let red = RGBA(red: 1.0, green: 0.23, blue: 0.19)
}

/// Every user-configurable setting, as one value. The preferences window edits
/// a copy of this and the menu bar controller re-renders whenever it changes.
struct DisplaySettings: Codable, Equatable, Sendable {
    // What to show
    var onBatteryMode: DisplayMode = .iconAndPercent
    var chargingMode: DisplayMode = .icon
    var chargedMode: DisplayMode = .icon
    /// Show a gray outline for a battery that is reported as not present,
    /// instead of hiding the icon entirely.
    var showRemovedBattery: Bool = true
    /// Treat an attached UPS as a battery and display it.
    var showUPS: Bool = false
    /// Reverse the left-to-right order when more than one source is shown.
    var reverseOrder: Bool = false

    // Shape and colors
    var shape: IconShape = .roundedWithTerminal
    var onBatteryColor: ColorSetting = .automatic
    var chargingColor: ColorSetting = .custom(.orange)
    var chargedColor: ColorSetting = .custom(.green)
    var outlineColor: ColorSetting = .automatic
    /// Turn the icon a warning color when the charge falls below `lowColorPercent`.
    var lowColorEnabled: Bool = true
    var lowColorPercent: Int = 20
    var lowColor: ColorSetting = .custom(.red)

    // Warnings
    /// Show a warning panel (and play a sound) when discharging below
    /// `warningPanelPercent`.
    var warningPanelEnabled: Bool = true
    var warningPanelPercent: Int = 10
    var warningSoundEnabled: Bool = true

    init() {}

    /// Decodes leniently: a missing key, an unknown enum value, or a field of
    /// the wrong type falls back to the default for that one setting instead
    /// of discarding all saved settings. This keeps preferences across
    /// upgrades and downgrades that add or rename fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DisplaySettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil ?? fallback
        }
        onBatteryMode = value(.onBatteryMode, d.onBatteryMode)
        chargingMode = value(.chargingMode, d.chargingMode)
        chargedMode = value(.chargedMode, d.chargedMode)
        showRemovedBattery = value(.showRemovedBattery, d.showRemovedBattery)
        showUPS = value(.showUPS, d.showUPS)
        reverseOrder = value(.reverseOrder, d.reverseOrder)
        shape = value(.shape, d.shape)
        onBatteryColor = value(.onBatteryColor, d.onBatteryColor)
        chargingColor = value(.chargingColor, d.chargingColor)
        chargedColor = value(.chargedColor, d.chargedColor)
        outlineColor = value(.outlineColor, d.outlineColor)
        lowColorEnabled = value(.lowColorEnabled, d.lowColorEnabled)
        lowColorPercent = value(.lowColorPercent, d.lowColorPercent)
        lowColor = value(.lowColor, d.lowColor)
        warningPanelEnabled = value(.warningPanelEnabled, d.warningPanelEnabled)
        warningPanelPercent = value(.warningPanelPercent, d.warningPanelPercent)
        warningSoundEnabled = value(.warningSoundEnabled, d.warningSoundEnabled)
    }

    func mode(for state: PowerState) -> DisplayMode {
        switch state {
        case .onBattery: return onBatteryMode
        case .charging: return chargingMode
        case .charged: return chargedMode
        }
    }

    func fillColor(for state: PowerState) -> ColorSetting {
        switch state {
        case .onBattery: return onBatteryColor
        case .charging: return chargingColor
        case .charged: return chargedColor
        }
    }

    /// True when the settings hide the menu bar item in every state, which
    /// makes the app hard to find again.
    var hidesEverything: Bool {
        onBatteryMode == .hidden && chargingMode == .hidden && chargedMode == .hidden
    }
}
