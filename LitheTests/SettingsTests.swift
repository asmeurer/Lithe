import Foundation
import Testing
@testable import Lithe

struct DisplaySettingsCodingTests {
    @Test func roundTripsThroughJSON() throws {
        var s = DisplaySettings()
        s.onBatteryMode = .time
        s.shape = .thin
        s.chargingColor = .automatic
        s.outlineColor = .custom(RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        s.lowColorPercent = 33
        s.warningPanelEnabled = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(DisplaySettings.self, from: data)
        #expect(back == s)
    }

    @Test func rgbaHexRoundTrip() {
        let c = RGBA(red: 1, green: 0.5, blue: 0, alpha: 1)
        #expect(c.hex == "#FF8000FF")
        let parsed = try! #require(RGBA(hex: "#FF8000FF"))
        #expect(parsed.hex == c.hex)
        #expect(abs(parsed.green - c.green) < 1.0 / 255)
        let short = try! #require(RGBA(hex: "336699"))
        #expect(short.alpha == 1)
        #expect(abs(short.red - 0.2) < 0.001)
        #expect(RGBA(hex: "nope") == nil)
        #expect(RGBA(hex: "#12345") == nil)
    }

    @Test func modeCatalogMatchesLegacyOrder() {
        #expect(DisplayMode.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5])
        #expect(DisplayMode(rawValue: 0) == .hidden)
        #expect(DisplayMode(rawValue: 3) == .iconAndTime)
        #expect(DisplayMode(rawValue: 5) == .time)
        #expect(IconShape(rawValue: 1) == .roundedWithTerminal)
        #expect(IconShape(rawValue: 4) == .horizontal)
    }
}

struct LegacyImportTests {
    /// A real `defaults export` of SlimBatteryMonitor 1.5.
    static var legacy: [String: Any] { [
        "CMHBatteryShape": 3,
        "CMHChargingOption": 2,
        "CMHDrainingOption": 3,
        "CMHLastRunVersion": "1.5",
        "CMHPoweredOption": 1,
        "CMHRunCount": 942,
        "CMHShouldReverseOrder": 0,
        "CMHShouldShowRemoved": 1,
        "CMHShouldShowUPS": 0,
        "CMHWarningEnabled": 1,
        "CMHWarningPanelEnabled": 1,
        "CMHWarningPanelPercent": 10,
        "CMHWarningPercent": 25,
        "NSStatusItem Preferred Position Item-0": 384,
    ] }

    @Test func detectsSlimBatteryMonitorDefaults() {
        #expect(LegacyImport.looksLikeSlimBatteryMonitor(Self.legacy))
        #expect(!LegacyImport.looksLikeSlimBatteryMonitor(["NSWindow Frame x": "1 2 3 4"]))
        #expect(!LegacyImport.looksLikeSlimBatteryMonitor([:]))
    }

    @Test func importsDisplayChoices() {
        let s = LegacyImport.settings(from: Self.legacy, base: DisplaySettings())
        #expect(s.onBatteryMode == .iconAndTime)
        #expect(s.chargingMode == .iconAndPercent)
        #expect(s.chargedMode == .icon)
        #expect(s.shape == .rounded)
        #expect(s.showRemovedBattery)
        #expect(!s.showUPS)
        #expect(!s.reverseOrder)
        #expect(s.lowColorEnabled)
        #expect(s.lowColorPercent == 25)
        #expect(s.warningPanelEnabled)
        #expect(s.warningPanelPercent == 10)
        // Colors are deliberately not imported.
        #expect(s.onBatteryColor == DisplaySettings().onBatteryColor)
        #expect(s.chargingColor == DisplaySettings().chargingColor)
    }

    @Test func ignoresGarbage() {
        let base = DisplaySettings()
        let s = LegacyImport.settings(from: [
            "CMHDrainingOption": 42,
            "CMHBatteryShape": -1,
            "CMHWarningPercent": 250,
            "CMHShouldShowUPS": "yes",
        ], base: base)
        #expect(s == base)
    }
}

@MainActor
struct PreferencesStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "com.github.asmeurer.Lithe.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func persistsAndReloads() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.settings == DisplaySettings())
        prefs.settings.shape = .horizontal
        prefs.settings.warningPanelPercent = 15
        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.settings.shape == .horizontal)
        #expect(reloaded.settings.warningPanelPercent == 15)
        reloaded.resetToDefaults()
        #expect(Preferences(defaults: defaults).settings == DisplaySettings())
    }

    @Test func ignoresCorruptSavedSettings() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: Preferences.settingsKey)
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.settings == DisplaySettings())
    }
}
