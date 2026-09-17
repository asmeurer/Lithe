import Foundation
import Testing
@testable import Lithe

struct PowerSourceParserTests {
    /// The dictionary IOKit produced on an Apple silicon MacBook Pro on AC
    /// power at 80% with charging on hold.
    static var onACNotCharging: [String: Any] { [
        "Battery Provides Time Remaining": true,
        "Current": 0,
        "Current Capacity": 80,
        "DesignCycleCount": 300,
        "Is Charged": false,
        "Is Charging": false,
        "Is Present": true,
        "LPM Active": false,
        "Max Capacity": 100,
        "Name": "InternalBattery-0",
        "Power Source ID": 40894563,
        "Power Source State": "AC Power",
        "Time to Empty": 0,
        "Time to Full Charge": 0,
        "Transport Type": "Internal",
        "Type": "InternalBattery",
    ] }

    @Test func parsesACNotCharging() {
        let s = PowerSourceParser.parse(Self.onACNotCharging)
        #expect(s.name == "InternalBattery-0")
        #expect(s.kind == .internalBattery)
        #expect(s.isPresent)
        #expect(s.state == .charged)
        #expect(s.charge == 0.8)
        #expect(s.percent == 80)
        #expect(s.minutesToEmpty == nil)
        #expect(s.minutesToFull == nil)
        #expect(!s.isCharged)
    }

    @Test func parsesDischarging() {
        var d = Self.onACNotCharging
        d["Power Source State"] = "Battery Power"
        d["Current Capacity"] = 43
        d["Time to Empty"] = 150
        let s = PowerSourceParser.parse(d)
        #expect(s.state == .onBattery)
        #expect(s.percent == 43)
        #expect(s.minutesToEmpty == 150)
        #expect(s.relevantMinutes == 150)
        #expect(s.minutesToFull == nil)
    }

    @Test func dischargingWhileCalculatingHasNoEstimate() {
        var d = Self.onACNotCharging
        d["Power Source State"] = "Battery Power"
        d["Time to Empty"] = -1
        let s = PowerSourceParser.parse(d)
        #expect(s.state == .onBattery)
        #expect(s.minutesToEmpty == nil)
    }

    @Test func parsesCharging() {
        var d = Self.onACNotCharging
        d["Is Charging"] = true
        d["Current Capacity"] = 55
        d["Time to Full Charge"] = 70
        let s = PowerSourceParser.parse(d)
        #expect(s.state == .charging)
        #expect(s.minutesToFull == 70)
        #expect(s.relevantMinutes == 70)
        #expect(s.minutesToEmpty == nil)
    }

    @Test func chargeHeldComesFromTheRegistryHint() {
        // The dictionary alone cannot tell "on hold" from "not charging".
        let plain = PowerSourceParser.parse(Self.onACNotCharging)
        #expect(!plain.chargeOnHold)
        let held = PowerSourceParser.parse(Self.onACNotCharging, chargeHeld: true)
        #expect(held.chargeOnHold)
        #expect(held.state == .charged)

        // Not "on hold" when actually charging, charged, or full.
        var charging = Self.onACNotCharging
        charging["Is Charging"] = true
        #expect(!PowerSourceParser.parse(charging, chargeHeld: true).chargeOnHold)
        var full = Self.onACNotCharging
        full["Current Capacity"] = 100
        #expect(!PowerSourceParser.parse(full, chargeHeld: true).chargeOnHold)
        var charged = Self.onACNotCharging
        charged["Is Charged"] = true
        #expect(!PowerSourceParser.parse(charged, chargeHeld: true).chargeOnHold)

        // The legacy key still counts if a system publishes it.
        var published = Self.onACNotCharging
        published["Optimized Battery Charging Engaged"] = true
        #expect(PowerSourceParser.parse(published).chargeOnHold)
    }

    @Test func parsesFullyCharged() {
        var d = Self.onACNotCharging
        d["Is Charged"] = true
        d["Current Capacity"] = 100
        let s = PowerSourceParser.parse(d)
        #expect(s.state == .charged)
        #expect(s.isCharged)
        #expect(s.percent == 100)
        #expect(s.relevantMinutes == nil)
    }

    @Test func parsesRemovedBattery() {
        var d = Self.onACNotCharging
        d["Is Present"] = false
        d["Current Capacity"] = 0
        d["Max Capacity"] = 0
        let s = PowerSourceParser.parse(d)
        #expect(!s.isPresent)
        #expect(s.charge == nil)
        #expect(s.percent == nil)
    }

    @Test func parsesUPS() {
        let d: [String: Any] = [
            "Name": "Back-UPS 600",
            "Type": "UPS",
            "Transport Type": "USB",
            "Is Present": true,
            "Is Charging": false,
            "Power Source State": "Battery Power",
            "Current Capacity": 90,
            "Max Capacity": 100,
            "Time to Empty": 25,
        ]
        let s = PowerSourceParser.parse(d)
        #expect(s.kind == .ups)
        #expect(s.name == "Back-UPS 600")
        #expect(s.state == .onBattery)
        #expect(s.percent == 90)
        #expect(s.minutesToEmpty == 25)
    }

    @Test func toleratesMissingKeys() {
        let s = PowerSourceParser.parse([:])
        #expect(s.kind == .unknown)
        #expect(s.isPresent)
        #expect(s.state == .charged)
        #expect(s.charge == nil)
        #expect(s.minutesToEmpty == nil)
    }

    @Test func clampsCapacity() {
        var d = Self.onACNotCharging
        d["Current Capacity"] = 120
        #expect(PowerSourceParser.parse(d).charge == 1)
    }

    @Test func readsHealthCondition() {
        var d = Self.onACNotCharging
        d["BatteryHealthCondition"] = "Check Battery"
        #expect(PowerSourceParser.parse(d).healthCondition == "Check Battery")
        d.removeValue(forKey: "BatteryHealthCondition")
        d["BatteryHealth"] = "Good"
        #expect(PowerSourceParser.parse(d).healthCondition == "Good")
    }
}

struct BatteryHealthTests {
    @Test func parsesAppleSiliconRegistry() throws {
        let props: [String: Any] = [
            "CycleCount": 32,
            "Voltage": 12232,
            "Amperage": -1500,
            "BatteryData": [
                "DesignCapacity": 8579,
                "FullChargeCapacity": 8117,
                "NominalChargeCapacity": 8361,
            ],
            "ChargerData": [
                "IsCharging": 0,
                "NotChargingReason": 16777216,
            ],
        ]
        let h = BatteryHealth.parse(props)
        #expect(h.cycleCount == 32)
        #expect(h.notChargingReason == 16777216)
        #expect(h.isChargeHeld)
        #expect(h.designCapacity == 8579)
        #expect(h.fullChargeCapacity == 8117)
        #expect(h.maximumCapacityPercent == 94)
        #expect(h.temperatureCelsius == nil)
        let watts = try #require(h.watts)
        #expect(abs(watts - (-18.348)) < 0.001)
    }

    @Test func parsesIntelStyleKeys() {
        let props: [String: Any] = [
            "CycleCount": 500,
            "DesignCapacity": 5000,
            "AppleRawMaxCapacity": 4000,
            "Temperature": 3011,
        ]
        let h = BatteryHealth.parse(props)
        #expect(h.maximumCapacityPercent == 80)
        #expect(h.temperatureCelsius == 30.11)
        #expect(h.watts == nil)
        #expect(!h.isChargeHeld)
    }
}

struct TimeFormattingTests {
    @Test func clock() {
        #expect(TimeFormatting.clock(minutes: 150) == "2:30")
        #expect(TimeFormatting.clock(minutes: 5) == "0:05")
        #expect(TimeFormatting.clock(minutes: 0) == "0:00")
        #expect(TimeFormatting.clock(minutes: 600) == "10:00")
        #expect(TimeFormatting.clock(minutes: nil) == "–:––")
    }

    @Test func spoken() {
        #expect(TimeFormatting.spoken(minutes: 150) == "2 hours 30 minutes")
        #expect(TimeFormatting.spoken(minutes: 60) == "1 hour")
        #expect(TimeFormatting.spoken(minutes: 1) == "1 minute")
        #expect(TimeFormatting.spoken(minutes: 0) == "0 minutes")
        #expect(TimeFormatting.spoken(minutes: 61) == "1 hour 1 minute")
    }

    @Test func percent() {
        #expect(TimeFormatting.percent(80) == "80%")
        #expect(TimeFormatting.percent(nil) == "–%")
    }
}
