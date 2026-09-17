import Foundation

/// Reads the preferences of SlimBatteryMonitor (the Intel-only app that Lithe
/// replaces) so that a user switching over keeps their display settings.
///
/// Colors are not imported: they were stored as archived `NSColor` objects in
/// the ancient typedstream format, and the old defaults (black on black)
/// would not adapt to a dark menu bar anyway.
enum LegacyImport {
    static let domain = "org.orange-carb.SlimBatteryMonitor"

    static func looksLikeSlimBatteryMonitor(_ dict: [String: Any]) -> Bool {
        dict.keys.contains { $0.hasPrefix("CMH") }
    }

    static func settings(from dict: [String: Any], base: DisplaySettings) -> DisplaySettings {
        var s = base
        if let m = mode(dict["CMHDrainingOption"]) { s.onBatteryMode = m }
        if let m = mode(dict["CMHChargingOption"]) { s.chargingMode = m }
        if let m = mode(dict["CMHPoweredOption"]) { s.chargedMode = m }
        if let raw = int(dict["CMHBatteryShape"]), let shape = IconShape(rawValue: raw) { s.shape = shape }
        if let b = bool(dict["CMHShouldShowRemoved"]) { s.showRemovedBattery = b }
        if let b = bool(dict["CMHShouldShowUPS"]) { s.showUPS = b }
        if let b = bool(dict["CMHShouldReverseOrder"]) { s.reverseOrder = b }
        if let b = bool(dict["CMHWarningEnabled"]) { s.lowColorEnabled = b }
        if let p = int(dict["CMHWarningPercent"]), (1...99).contains(p) { s.lowColorPercent = p }
        if let b = bool(dict["CMHWarningPanelEnabled"]) { s.warningPanelEnabled = b }
        if let p = int(dict["CMHWarningPanelPercent"]), (1...99).contains(p) { s.warningPanelPercent = p }
        return s
    }

    private static func mode(_ value: Any?) -> DisplayMode? {
        guard let raw = int(value) else { return nil }
        return DisplayMode(rawValue: raw)
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber: return n.intValue
        case let i as Int: return i
        case let s as String: return Int(s)
        default: return nil
        }
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let n as NSNumber: return n.boolValue
        case let b as Bool: return b
        default: return nil
        }
    }
}
