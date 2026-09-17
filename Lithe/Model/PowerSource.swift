import Foundation

/// The charging state of a battery or UPS, as far as the menu bar display is
/// concerned. These are the three states the user configures independently.
enum PowerState: String, Codable, CaseIterable, Sendable {
    /// Discharging: the machine is running from the battery.
    case onBattery
    /// External power is connected and the battery is being charged.
    case charging
    /// External power is connected and the battery is not charging, either
    /// because it is full or because charging is being held (for example by
    /// Optimized Battery Charging or a charge limit).
    case charged
}

/// The kind of power source reported by IOKit.
enum PowerSourceKind: String, Codable, Sendable {
    case internalBattery
    case ups
    case unknown
}

/// A snapshot of one power source (an internal battery or a UPS), decoded from
/// the dictionary returned by `IOPSGetPowerSourceDescription`.
///
/// This is a plain value type so that all downstream logic (what to display,
/// what to draw, what to say in the menu) can be unit-tested against fixtures.
struct PowerSource: Equatable, Sendable {
    var name: String
    var kind: PowerSourceKind
    /// Whether the physical battery is present. A removed battery is reported
    /// by some machines as a source that is not present.
    var isPresent: Bool
    var state: PowerState
    /// Charge as a fraction in `0...1`, or `nil` if unknown.
    var charge: Double?
    /// Minutes until the battery is empty (when on battery), or `nil` if unknown
    /// or not applicable.
    var minutesToEmpty: Int?
    /// Minutes until the battery is fully charged (when charging), or `nil` if
    /// unknown or not applicable.
    var minutesToFull: Int?
    /// Whether the system reports the battery as fully charged.
    var isCharged: Bool
    /// Battery condition as reported by IOKit, e.g. "Good", "Fair", "Poor", or
    /// `nil` when not reported.
    var healthCondition: String?
    /// Whether charging is being held below full by the system (Optimized
    /// Battery Charging or a charge limit) while external power is connected.
    var chargeOnHold: Bool

    init(
        name: String = "Battery",
        kind: PowerSourceKind = .internalBattery,
        isPresent: Bool = true,
        state: PowerState,
        charge: Double?,
        minutesToEmpty: Int? = nil,
        minutesToFull: Int? = nil,
        isCharged: Bool = false,
        healthCondition: String? = nil,
        chargeOnHold: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.isPresent = isPresent
        self.state = state
        self.charge = charge
        self.minutesToEmpty = minutesToEmpty
        self.minutesToFull = minutesToFull
        self.isCharged = isCharged
        self.healthCondition = healthCondition
        self.chargeOnHold = chargeOnHold
    }

    /// Charge as a whole percentage in `0...100`, or `nil` if unknown.
    var percent: Int? {
        guard let charge else { return nil }
        return Int((charge * 100).rounded())
    }

    /// The time estimate that is relevant to the current state: time to empty
    /// while on battery, time to full while charging, and nothing otherwise.
    var relevantMinutes: Int? {
        switch state {
        case .onBattery: return minutesToEmpty
        case .charging: return minutesToFull
        case .charged: return nil
        }
    }
}

/// Everything the app knows about power at one moment.
struct PowerSnapshot: Equatable, Sendable {
    /// All power sources in the order IOKit reports them.
    var sources: [PowerSource]
    /// Whether the machine as a whole is currently drawing from external power.
    var externalPowerConnected: Bool
    /// Whether macOS Low Power Mode is enabled.
    var lowPowerMode: Bool
    var timestamp: Date

    init(sources: [PowerSource], externalPowerConnected: Bool, lowPowerMode: Bool = false, timestamp: Date = Date()) {
        self.sources = sources
        self.externalPowerConnected = externalPowerConnected
        self.lowPowerMode = lowPowerMode
        self.timestamp = timestamp
    }

    static let empty = PowerSnapshot(sources: [], externalPowerConnected: true, timestamp: Date(timeIntervalSince1970: 0))
}
