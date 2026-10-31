import Foundation
import SwiftUI
import Testing

@testable import PebbleRemoteKit
@testable import PebbleRemoteUI

/// Lane U's DEBUG launch hook for the UI audit (`-PebbleUIAudit 1`): it starts only with its argument, and the model it
/// makes runs the demo and nothing else, so the audit can never reach a Mac or wait on Face ID. (Release builds don't
/// contain the hook at all; these tests run in a DEBUG build.)
@MainActor
struct UIAuditLaunchTests {
    @Test(arguments: [
        [], ["-demo"], ["-PebbleUIAudit"], ["-PebbleUIAudit", "0"], ["-PebbleUIAudit", "yes"],
        ["-PebbleUIAuditPace", "1"], ["-PebbleUIAudit1"],
    ])
    func theAuditStartsOnlyWithItsArgument(_ arguments: [String]) {
        #expect(UIAuditLaunch(arguments: ["/private/var/PebbleRemote"] + arguments) == nil)
    }

    @Test func paceAndAppearanceAreOptional() throws {
        let plain = try #require(UIAuditLaunch(arguments: ["/private/var/PebbleRemote", "-PebbleUIAudit", "1"]))
        #expect(plain.pace == 1)
        #expect(plain.appearance == nil)
        #expect(plain.colorScheme == nil)

        let set = try #require(
            UIAuditLaunch(arguments: [
                "-PebbleUIAuditAppearance", "dark", "-PebbleUIAudit", "1", "-PebbleUIAuditPace", "2.5",
            ]))
        #expect(set.pace == 2.5)
        #expect(set.colorScheme == .dark)
        #expect(UIAuditLaunch(arguments: ["-PebbleUIAudit", "1", "-PebbleUIAuditAppearance", "light"])?.colorScheme == .light)
        #expect(UIAuditLaunch(arguments: ["-PebbleUIAudit", "1", "-PebbleUIAuditAppearance", "sepia"])?.appearance == nil)
        #expect(UIAuditLaunch(arguments: ["-PebbleUIAudit", "1", "-PebbleUIAuditPace", "0"])?.pace == 0)
    }

    @Test(arguments: ["-1", "nan", "inf", "fast", ""])
    func anUnusablePaceIsLifelike(_ pace: String) {
        #expect(UIAuditLaunch(arguments: ["-PebbleUIAudit", "1", "-PebbleUIAuditPace", pace])?.pace == 1)
    }

    /// The audit taps "Leave the Demo" too: the app then makes its other store, which must be a demo as well, never the
    /// live client with the paired Mac from the Keychain. The app lock never applies, so no Face ID.
    @Test func theAuditModelOnlyEverRunsTheDemo() throws {
        let launch = try #require(UIAuditLaunch(arguments: ["-PebbleUIAudit", "1", "-PebbleUIAuditPace", "0"]))
        let model = PebbleRemoteModel.uiAudit(launch)
        #expect(model.store.isDemo)
        #expect(model.store.client is DemoClient)
        #expect(model.store.pairedMac?.bridgeID == "demo")
        #expect(!model.lockApplies)

        model.leaveDemo()
        #expect(model.store.isDemo)
        #expect(model.store.client is DemoClient)
        #expect(model.store.pairedMac?.bridgeID == "demo")
        #expect(!model.lockApplies)
        #expect(!model.lock.isLocked)
    }
}
