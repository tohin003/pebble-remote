import Foundation
import PebbleRemoteKit
import SwiftUI
import Testing

@testable import PebbleRemoteUI

/// Lane X, contract S-05 in the app's shell: the Mac's unlock ends when the app goes to the background (before the
/// connection closes) and when the app lock engages.
@MainActor
struct ShellLockTests {
    private static let mac = PairedMac(
        bridgeID: "b1", name: "Studio Mac", deviceID: "d1", pin: "p1",
        endpoints: [Endpoint(host: "192.168.1.20", port: 47800)], pairedAt: Date(timeIntervalSince1970: 1_800_000_000))

    @Test func goingToTheBackgroundEndsTheMacsUnlockThenClosesTheConnection() async {
        let probe = ShellProbeClient()
        let model = PebbleRemoteModel(store: RemoteStore(client: probe, pairedMac: Self.mac))
        model.scenePhaseChanged(.background)
        // Once, and before the close: the store's stop and the app lock engaging share the one call.
        #expect(await waitUntil { probe.events == ["lock", "disconnect"] })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(probe.events == ["lock", "disconnect"])
    }
}
