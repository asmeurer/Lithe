import Foundation
import Testing
@testable import Lithe

@MainActor
struct SmartChargeTests {
    /// A stand-in client so the wrapper's logic can be tested without the
    /// private framework.
    final class FakeClient: NSObject, SmartChargeClientProtocol {
        var engaged = false
        var limit: UInt = 100
        var override = false
        var mclEnabled: UInt = 0
        var mclLimit: UInt8 = 100
        var queryFails = false
        var actionFails = false
        var calls: [String] = []

        required init(clientName: String) {}
        override init() { super.init() }

        func isOBCEngaged(_ engaged: UnsafeMutablePointer<ObjCBool>, chargeLimit: UnsafeMutablePointer<UInt>,
                          chargingOverrideAllowed: UnsafeMutablePointer<ObjCBool>, withError: NSErrorPointer) -> Bool {
            if queryFails {
                withError?.pointee = NSError(domain: "Test", code: 1)
                return false
            }
            engaged.pointee = ObjCBool(self.engaged)
            chargeLimit.pointee = limit
            chargingOverrideAllowed.pointee = ObjCBool(override)
            return true
        }
        func isMCLCurrentlyEnabled(_ error: NSErrorPointer) -> UInt { mclEnabled }
        func getMCLLimit(_ error: NSErrorPointer) -> UInt8 { mclLimit }
        func temporarilyEnableCharging(_ error: NSErrorPointer) -> Bool {
            calls.append("enableCharging")
            if actionFails { error?.pointee = NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "nope"]) }
            return !actionFails
        }
        func temporarilyDisableMCL(_ error: NSErrorPointer) -> Bool {
            calls.append("disableMCL")
            return !actionFails
        }
    }

    @Test func reportsOptimizedChargingHold() {
        let fake = FakeClient()
        fake.engaged = true
        fake.limit = 80
        fake.override = true
        let state = SmartCharge(client: fake).state()
        #expect(state == SmartCharge.State(optimizedChargingEngaged: true, chargeLimitEnabled: false, chargeLimit: 100, overrideAllowed: true))
        #expect(state?.isHolding == true)
    }

    @Test func reportsChargeLimit() {
        let fake = FakeClient()
        fake.mclEnabled = 1
        fake.mclLimit = 80
        let state = SmartCharge(client: fake).state()
        #expect(state?.chargeLimitEnabled == true)
        #expect(state?.chargeLimit == 80)
        #expect(state?.isHolding == true)
    }

    @Test func idleStateIsNotHolding() {
        let state = SmartCharge(client: FakeClient()).state()
        #expect(state?.isHolding == false)
        #expect(state?.overrideAllowed == false)
    }

    @Test func queryFailureYieldsNil() {
        let fake = FakeClient()
        fake.queryFails = true
        #expect(SmartCharge(client: fake).state() == nil)
        #expect(SmartCharge(client: nil).state() == nil)
        #expect(!SmartCharge(client: nil).isAvailable)
    }

    @Test func chargeToFullLiftsTheLimitOrOverridesOptimizedCharging() throws {
        let optimized = FakeClient()
        optimized.engaged = true
        try SmartCharge(client: optimized).chargeToFullNow()
        #expect(optimized.calls == ["enableCharging"])

        let limited = FakeClient()
        limited.mclEnabled = 1
        limited.mclLimit = 80
        try SmartCharge(client: limited).chargeToFullNow()
        #expect(limited.calls == ["disableMCL"])
    }

    @Test func chargeToFullReportsFailures() {
        let failing = FakeClient()
        failing.actionFails = true
        #expect(throws: SmartCharge.Failure.self) { try SmartCharge(client: failing).chargeToFullNow() }
        #expect(throws: SmartCharge.Failure.self) { try SmartCharge(client: nil).chargeToFullNow() }
    }

    /// On a real Mac the private client should load; this only checks that
    /// the class and the selectors Lithe relies on still exist.
    @Test func privateClientLoadsOnThisSystem() {
        #expect(SmartCharge.loadClient() != nil)
    }
}
