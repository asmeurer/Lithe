import Foundation

/// Access to the system's smart-charging controls: whether Optimized Battery
/// Charging or a charge limit is holding the charge, and the "Charge to Full
/// Now" override that Apple's own battery menu offers.
///
/// There is no public API for this. Control Center uses the private PowerUI
/// framework's `PowerUISmartChargeClient`, and so does this wrapper, loaded
/// at runtime and guarded at every step: if the framework, the class, or a
/// method is missing on some macOS version, the feature simply disappears.
@MainActor
final class SmartCharge {
    static let shared = SmartCharge()

    /// What the system reports about charge holding.
    struct State: Equatable, Sendable {
        /// Optimized Battery Charging is currently holding the charge.
        var optimizedChargingEngaged: Bool
        /// The charge limit setting (for example 80%) is turned on.
        var chargeLimitEnabled: Bool
        /// The limit in percent when `chargeLimitEnabled`, otherwise 100.
        var chargeLimit: Int
        /// Whether the system allows a "charge to full" override right now.
        var overrideAllowed: Bool

        /// True when either mechanism is holding the charge below full.
        var isHolding: Bool { optimizedChargingEngaged || (chargeLimitEnabled && chargeLimit < 100) }
    }

    enum Failure: LocalizedError {
        case unavailable
        case rejected(NSError?)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Smart charging controls are not available on this Mac."
            case .rejected(let error):
                return error?.localizedDescription ?? "The system declined the request."
            }
        }
    }

    private let client: (any SmartChargeClientProtocol)?

    /// Loads the private client, or `nil` if it cannot be used.
    static func loadClient() -> (any SmartChargeClientProtocol)? {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else { return nil }
        let required: [Selector] = [
            #selector(SmartChargeClientProtocol.isOBCEngaged(_:chargeLimit:chargingOverrideAllowed:withError:)),
            #selector(SmartChargeClientProtocol.isMCLCurrentlyEnabled(_:)),
            #selector(SmartChargeClientProtocol.getMCLLimit(_:)),
            #selector(SmartChargeClientProtocol.temporarilyEnableCharging(_:)),
            #selector(SmartChargeClientProtocol.temporarilyDisableMCL(_:)),
        ]
        let initializer = NSSelectorFromString("initWithClientName:")
        guard cls.instancesRespond(to: initializer),
              required.allSatisfy({ cls.instancesRespond(to: $0) }) else { return nil }
        // alloc/init through the runtime: `init` consumes alloc's reference
        // and returns an owned one.
        guard let allocated = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let instance = allocated.perform(initializer, with: "Lithe")?.takeRetainedValue() else { return nil }
        return unsafeBitCast(instance, to: (any SmartChargeClientProtocol).self)
    }

    init(client: (any SmartChargeClientProtocol)? = SmartCharge.loadClient()) {
        self.client = client
    }

    var isAvailable: Bool { client != nil }

    /// Queries the system. Returns `nil` when the controls are unavailable or
    /// the query fails.
    func state() -> State? {
        guard let client else { return nil }
        var engaged = ObjCBool(false)
        var limit: UInt = 100
        var override = ObjCBool(false)
        var error: NSError?
        guard client.isOBCEngaged(&engaged, chargeLimit: &limit, chargingOverrideAllowed: &override, withError: &error) else {
            NSLog("Lithe: smart charge query failed: \(error?.localizedDescription ?? "unknown error")")
            return nil
        }
        error = nil
        let mclEnabled = client.isMCLCurrentlyEnabled(&error) != 0
        error = nil
        let mclLimit = Int(client.getMCLLimit(&error))
        return State(
            optimizedChargingEngaged: engaged.boolValue,
            chargeLimitEnabled: mclEnabled,
            chargeLimit: mclEnabled ? mclLimit : 100,
            overrideAllowed: override.boolValue
        )
    }

    /// Asks the system to charge to full now, the same way the battery menu
    /// does: lift the charge limit if one is set, otherwise override
    /// Optimized Battery Charging.
    func chargeToFullNow() throws {
        guard let client else { throw Failure.unavailable }
        var error: NSError?
        let limited = client.isMCLCurrentlyEnabled(&error) != 0
        error = nil
        let ok = limited ? client.temporarilyDisableMCL(&error) : client.temporarilyEnableCharging(&error)
        guard ok else {
            NSLog("Lithe: charge to full request failed: \(error?.localizedDescription ?? "unknown error")")
            throw Failure.rejected(error)
        }
    }
}

/// The subset of `PowerUISmartChargeClient` that Control Center's battery
/// menu uses, declared so it can be called through the Objective-C runtime.
@objc protocol SmartChargeClientProtocol {
    init(clientName: String)
    @objc(isOBCEngaged:chargeLimit:chargingOverrideAllowed:withError:)
    func isOBCEngaged(_ engaged: UnsafeMutablePointer<ObjCBool>, chargeLimit: UnsafeMutablePointer<UInt>,
                      chargingOverrideAllowed: UnsafeMutablePointer<ObjCBool>, withError: NSErrorPointer) -> Bool
    @objc(isMCLCurrentlyEnabled:)
    func isMCLCurrentlyEnabled(_ error: NSErrorPointer) -> UInt
    @objc(getMCLLimitWithError:)
    func getMCLLimit(_ error: NSErrorPointer) -> UInt8
    @objc(temporarilyEnableCharging:)
    func temporarilyEnableCharging(_ error: NSErrorPointer) -> Bool
    @objc(temporarilyDisableMCL:)
    func temporarilyDisableMCL(_ error: NSErrorPointer) -> Bool
}
