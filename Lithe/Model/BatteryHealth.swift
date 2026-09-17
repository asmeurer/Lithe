import Foundation
import IOKit

/// Extra battery details that are not part of the power source dictionary and
/// have to be read from the `AppleSmartBattery` entry in the I/O Registry.
struct BatteryHealth: Equatable, Sendable {
    var cycleCount: Int?
    /// Design capacity in mAh.
    var designCapacity: Int?
    /// Current full-charge capacity in mAh.
    var fullChargeCapacity: Int?
    /// Battery voltage in millivolts.
    var voltage: Int?
    /// Signed current in milliamps: negative while discharging.
    var amperage: Int?
    /// Temperature in degrees Celsius, if the machine reports it.
    var temperatureCelsius: Double?

    /// Full-charge capacity as a percentage of the design capacity, which is
    /// what System Settings calls "Maximum Capacity".
    var maximumCapacityPercent: Int? {
        guard let designCapacity, designCapacity > 0, let fullChargeCapacity else { return nil }
        return Int((Double(fullChargeCapacity) / Double(designCapacity) * 100).rounded(.down))
    }

    /// Power flowing into (positive) or out of (negative) the battery, in watts.
    var watts: Double? {
        guard let voltage, let amperage else { return nil }
        return Double(voltage) * Double(amperage) / 1_000_000
    }

    /// Decodes the registry properties. All keys are optional because the set
    /// varies between Intel and Apple silicon machines and macOS versions.
    static func parse(_ props: [String: Any]) -> BatteryHealth {
        var h = BatteryHealth()
        let data = props["BatteryData"] as? [String: Any] ?? [:]
        h.cycleCount = int(props["CycleCount"])
        h.designCapacity = int(data["DesignCapacity"]) ?? int(props["DesignCapacity"])
        h.fullChargeCapacity = int(data["FullChargeCapacity"]) ?? int(props["AppleRawMaxCapacity"])
        h.voltage = int(props["Voltage"])
        h.amperage = int(props["Amperage"])
        if let t = int(props["Temperature"]) {
            // Reported in hundredths of a degree Celsius.
            h.temperatureCelsius = Double(t) / 100
        }
        return h
    }

    /// Reads the live values. Returns `nil` on a machine without a smart
    /// battery (for example a desktop Mac).
    static func read() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return parse(props)
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let n as NSNumber: return n.intValue
        case let i as Int: return i
        default: return nil
        }
    }
}
