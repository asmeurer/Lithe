import Foundation
import IOKit.ps

/// Decodes the `[String: Any]` dictionaries that IOKit's power source API
/// produces into `PowerSource` values.
///
/// Key names come from `IOKit/ps/IOPSKeys.h`. The parser is deliberately
/// forgiving: any missing or malformed value degrades to "unknown" rather than
/// failing, because the exact set of keys varies between machines, macOS
/// versions, and UPS drivers.
enum PowerSourceParser {
    /// Sentinel used by IOKit for "still calculating" time estimates.
    static let timeUnknown = -1

    static func parse(_ dict: [String: Any]) -> PowerSource {
        let name = dict[kIOPSNameKey] as? String ?? "Battery"
        let kind: PowerSourceKind
        switch dict[kIOPSTypeKey] as? String {
        case kIOPSInternalBatteryType: kind = .internalBattery
        case kIOPSUPSType: kind = .ups
        default: kind = .unknown
        }
        let isPresent = dict[kIOPSIsPresentKey] as? Bool ?? true
        let isCharging = dict[kIOPSIsChargingKey] as? Bool ?? false
        let isCharged = dict[kIOPSIsChargedKey] as? Bool ?? false
        let powerSourceState = dict[kIOPSPowerSourceStateKey] as? String

        let state: PowerState
        if powerSourceState == kIOPSBatteryPowerValue {
            state = .onBattery
        } else if isCharging {
            state = .charging
        } else {
            // AC Power (or Off Line for a UPS) and not charging.
            state = .charged
        }

        var charge: Double?
        if let current = number(dict[kIOPSCurrentCapacityKey]),
           let max = number(dict[kIOPSMaxCapacityKey]), max > 0 {
            charge = min(1, Swift.max(0, current / max))
        }

        let minutesToEmpty = minutes(dict[kIOPSTimeToEmptyKey])
        let minutesToFull = minutes(dict[kIOPSTimeToFullChargeKey])

        let condition = dict[kIOPSBatteryHealthConditionKey] as? String ?? dict[kIOPSBatteryHealthKey] as? String
        let optimized = dict["Optimized Battery Charging Engaged"] as? Bool ?? false

        return PowerSource(
            name: name,
            kind: kind,
            isPresent: isPresent,
            state: state,
            charge: charge,
            minutesToEmpty: state == .onBattery ? minutesToEmpty : nil,
            minutesToFull: state == .charging ? minutesToFull : nil,
            isCharged: isCharged,
            healthCondition: condition,
            optimizedChargingEngaged: optimized
        )
    }

    /// Converts an IOKit minutes value into an optional. IOKit uses -1 for
    /// "unknown / still calculating", and 0 is treated as unknown too since it
    /// only ever appears when the estimate is not applicable.
    static func minutes(_ value: Any?) -> Int? {
        guard let n = number(value) else { return nil }
        let m = Int(n)
        return m > 0 ? m : nil
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let i as Int: return Double(i)
        default: return nil
        }
    }
}
