import Foundation
import Testing
@testable import Lithe

struct StatusPresentationTests {
    func snapshot(_ sources: [PowerSource], lowPower: Bool = false) -> PowerSnapshot {
        PowerSnapshot(sources: sources, externalPowerConnected: sources.first?.state != .onBattery, lowPowerMode: lowPower)
    }

    /// The configuration SlimBatteryMonitor users commonly had: time while
    /// draining, percent while charging, icon only when charged.
    var classicSettings: DisplaySettings {
        var s = DisplaySettings()
        s.onBatteryMode = .iconAndTime
        s.chargingMode = .iconAndPercent
        s.chargedMode = .icon
        s.shape = .rounded
        s.lowColorEnabled = true
        s.lowColorPercent = 25
        s.warningPanelEnabled = true
        s.warningPanelPercent = 10
        return s
    }

    @Test func onBatteryShowsIconAndTime() {
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.8, minutesToEmpty: 150)]),
            settings: classicSettings)
        #expect(p.items.count == 1)
        let item = p.items[0]
        #expect(item.icon?.shape == .rounded)
        #expect(item.icon?.level == 0.8)
        #expect(item.icon?.fill == .automatic)
        #expect(item.icon?.outline == .automatic)
        #expect(item.text == "2:30")
        #expect(item.textColor == .automatic)
        #expect(p.summaryLines == ["On battery: 2 hours 30 minutes remaining (80%)"])
        #expect(p.tooltip == "On battery: 2 hours 30 minutes remaining (80%)")
    }

    @Test func onBatteryCalculatingShowsPlaceholder() {
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.8)]),
            settings: classicSettings)
        #expect(p.items[0].text == "–:––")
        #expect(p.summaryLines == ["On battery: calculating time remaining (80%)"])
    }

    @Test func chargingShowsIconAndPercentInChargingColor() {
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .charging, charge: 0.55, minutesToFull: 70)]),
            settings: classicSettings)
        let item = p.items[0]
        #expect(item.icon?.fill == .custom(.orange))
        #expect(item.text == "55%")
        #expect(p.summaryLines == ["Charging: 1 hour 10 minutes until full (55%)"])
    }

    @Test func chargedShowsIconOnly() {
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .charged, charge: 1.0, isCharged: true)]),
            settings: classicSettings)
        let item = p.items[0]
        #expect(item.icon?.fill == .custom(.green))
        #expect(item.text == nil)
        #expect(p.summaryLines == ["Fully charged"])
    }

    @Test func chargedNeverShowsATimeEstimate() {
        var s = classicSettings
        s.chargedMode = .iconAndTime
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .charged, charge: 0.8)]),
            settings: s)
        #expect(p.items[0].icon != nil)
        #expect(p.items[0].text == nil)
        #expect(p.summaryLines == ["On external power, not charging (80%)"])
        s.chargedMode = .time
        let p2 = StatusPresentation.make(snapshot: snapshot([PowerSource(state: .charged, charge: 0.8)]), settings: s)
        #expect(p2.isEmpty)
    }

    @Test func optimizedChargingSummary() {
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .charged, charge: 0.8, optimizedChargingEngaged: true)]),
            settings: classicSettings)
        #expect(p.summaryLines == ["Charging on hold (80%)"])
    }

    @Test func lowChargeUsesWarningColorForFillOutlineAndText() {
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.2, minutesToEmpty: 30)]),
            settings: classicSettings)
        let item = p.items[0]
        #expect(item.icon?.fill == .custom(.red))
        #expect(item.icon?.outline == .custom(.red))
        #expect(item.textColor == .custom(.red))
    }

    @Test func lowChargeThresholdIsExclusive() {
        let at = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.25, minutesToEmpty: 30)]),
            settings: classicSettings)
        #expect(at.items[0].icon?.fill == .automatic)
        var s = classicSettings
        s.lowColorEnabled = false
        let off = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.05, minutesToEmpty: 3)]),
            settings: s)
        #expect(off.items[0].icon?.fill == .automatic)
    }

    @Test func hiddenModeProducesEmptyItem() {
        var s = classicSettings
        s.onBatteryMode = .hidden
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.8, minutesToEmpty: 150)]),
            settings: s)
        #expect(p.items.count == 1)
        #expect(p.items[0].isEmpty)
        #expect(p.isEmpty)
        // The summary is still available for the menu.
        #expect(p.summaryLines.count == 1)
    }

    @Test func textOnlyModes() {
        var s = classicSettings
        s.onBatteryMode = .percent
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.8, minutesToEmpty: 150)]),
            settings: s)
        #expect(p.items[0].icon == nil)
        #expect(p.items[0].text == "80%")
        s.onBatteryMode = .time
        let t = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.8, minutesToEmpty: 150)]),
            settings: s)
        #expect(t.items[0].icon == nil)
        #expect(t.items[0].text == "2:30")
    }

    @Test func horizontalShapeMovesTextAboveMeter() {
        var s = classicSettings
        s.shape = .horizontal
        s.onBatteryMode = .iconAndPercent
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.8, minutesToEmpty: 150)]),
            settings: s)
        #expect(p.items[0].text == nil)
        #expect(p.items[0].icon?.textAbove == "80%")
    }

    @Test func removedBatteryShowsDimmedOutlineWhenEnabled() {
        var s = classicSettings
        s.showRemovedBattery = true
        let removed = PowerSource(isPresent: false, state: .charged, charge: nil)
        let p = StatusPresentation.make(snapshot: snapshot([removed]), settings: s)
        #expect(p.items.count == 1)
        #expect(p.items[0].icon?.isPresent == false)
        #expect(p.items[0].icon?.level == nil)
        #expect(p.items[0].icon?.outline == .dimmed)
        #expect(p.summaryLines == ["Battery not present"])

        s.showRemovedBattery = false
        let hidden = StatusPresentation.make(snapshot: snapshot([removed]), settings: s)
        #expect(hidden.isEmpty)
    }

    @Test func noPowerSourcesAtAll() {
        var s = classicSettings
        let p = StatusPresentation.make(snapshot: snapshot([]), settings: s)
        #expect(p.summaryLines == ["No battery present"])
        #expect(p.items.count == 1)
        #expect(p.items[0].icon?.isPresent == false)
        s.showRemovedBattery = false
        #expect(StatusPresentation.make(snapshot: snapshot([]), settings: s).isEmpty)
    }

    @Test func upsIsHiddenUnlessEnabled() {
        let ups = PowerSource(name: "Back-UPS", kind: .ups, state: .onBattery, charge: 0.9, minutesToEmpty: 25)
        let battery = PowerSource(state: .charged, charge: 1.0, isCharged: true)
        var s = classicSettings
        s.showUPS = false
        let p = StatusPresentation.make(snapshot: snapshot([battery, ups]), settings: s)
        #expect(p.items.count == 1)
        #expect(p.summaryLines == ["Fully charged"])

        s.showUPS = true
        let both = StatusPresentation.make(snapshot: snapshot([battery, ups]), settings: s)
        #expect(both.items.count == 2)
        #expect(both.items[1].text == "0:25")
        #expect(both.summaryLines == ["Fully charged", "Back-UPS: On battery: 25 minutes remaining (90%)"])

        s.reverseOrder = true
        let reversed = StatusPresentation.make(snapshot: snapshot([battery, ups]), settings: s)
        #expect(reversed.items[0].text == "0:25")
        #expect(reversed.summaryLines.first?.hasPrefix("Back-UPS") == true)
    }

    @Test func lowPowerModeIsMentioned() {
        let p = StatusPresentation.make(
            snapshot: snapshot([PowerSource(state: .onBattery, charge: 0.5, minutesToEmpty: 100)], lowPower: true),
            settings: classicSettings)
        #expect(p.summaryLines == ["On battery: 1 hour 40 minutes remaining (50%) · Low Power Mode"])
    }

    @Test func defaultSettingsHideNothing() {
        #expect(!DisplaySettings().hidesEverything)
        var s = DisplaySettings()
        s.onBatteryMode = .hidden
        s.chargingMode = .hidden
        s.chargedMode = .hidden
        #expect(s.hidesEverything)
    }
}
