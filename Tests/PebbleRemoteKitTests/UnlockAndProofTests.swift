import CryptoKit
import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane B, contract v0.3: the unlock (C1), proofs bound to their connection and call (3.11 item 3), a proof's call
// resent after a drop, `bye too_large` (item 6) and `setting:<key>` proofs (item 5).
@Suite("Lane B: unlock and v0.3 proofs")
struct UnlockAndProofTests {
    static func near(_ date: Date?, _ seconds: TimeInterval) -> Bool {
        guard let date else { return false }
        return abs(date.timeIntervalSinceNow - seconds) < 10
    }

    @Test func unlockRequiredUnlocksAndRetriesWithTheSameKey() async throws {
        let h = try await LiveHarness.make(unlockReason: "Unlock Pebble")
        h.bridge.requireUnlock(window: 600, announce: 600)
        try await h.connect()
        #expect(await h.client.unlockedUntil == nil)
        let result = try await h.client.call("send", ["chat_id": "c1", "text": "hi"])
        #expect(result == [:])
        let sends = h.bridge.requests("send")
        #expect(sends.count == 2 && sends[0].idem == sends[1].idem && sends[0].id != sends[1].id)
        #expect(h.bridge.executions(of: "send") == 1 && h.bridge.unlockRefusals == 1)
        #expect(h.bridge.requests("remote.unlock").count == 1)
        #expect(h.keys.reasons == ["Unlock Pebble"])
        #expect(Self.near(await h.client.unlockedUntil, 600))  // from welcome.unlock_seconds
        #expect(h.log.unlocks.count == 1 && Self.near(h.log.unlocks.last ?? nil, 600))
        #expect(h.log.welcomes.first?.unlockSeconds == 600)
        // Reads never need it, and a second act goes straight through while unlocked.
        _ = try await h.client.call("state", [:])
        _ = try await h.client.call("send", ["chat_id": "c1", "text": "again"])
        #expect(h.bridge.unlockRefusals == 1 && h.bridge.problems.isEmpty)
    }

    @Test func withoutAnUnlockSentenceTheRefusalReachesTheCaller() async throws {
        let h = try await LiveHarness.make()
        h.bridge.requireUnlock()
        try await h.connect()
        do {
            _ = try await h.client.call("send", ["chat_id": "c1", "text": "hi"])
            Issue.record("expected unlock_required")
        } catch RemoteCallError.refused(let refusal) {
            #expect(refusal.code == "unlock_required")
        }
        #expect(h.log.unlocks == [nil] || h.log.unlocks.isEmpty)  // locked, as the refusal said
        try await h.client.unlock(reason: "Unlock")
        let until = await h.client.unlockedUntil
        #expect(Self.near(until, 15 * 60))  // no unlock_seconds in welcome: 15 minutes
        #expect(h.log.unlocks.last == until)
        _ = try await h.client.call("send", ["chat_id": "c1", "text": "hi"])
        #expect(h.bridge.executions(of: "send") == 1)
    }

    @Test func concurrentUnlocksShareOneFaceID() async throws {
        let h = try await LiveHarness.make()
        h.bridge.requireUnlock()
        try await h.connect()
        async let first: Void = h.client.unlock(reason: "Unlock")
        async let second: Void = h.client.unlock(reason: "Unlock")
        _ = try await (first, second)
        #expect(h.bridge.requests("remote.unlock").count == 1 && h.keys.reasons.count == 1)
    }

    @Test func theUnlockLapsesOnTime() async throws {
        let h = try await LiveHarness.make()
        h.bridge.requireUnlock(window: 1, announce: 1)
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        #expect(Self.near(await h.client.unlockedUntil, 1))
        try await eventually("lapsed", timeout: .seconds(4)) { h.log.unlocks.last == .some(nil) }
        #expect(await h.client.unlockedUntil == nil)
        #expect(h.log.unlocks.count == 2)
    }

    @Test func everyElevatedCallRenewsTheUnlock() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        _ = try await h.client.callElevated("approve", ["id": "c1", "action_id": "a1"], reason: "Approve")
        #expect(Self.near(await h.client.unlockedUntil, 15 * 60))
    }

    @Test func aRestartedBridgeForgetsTheUnlock() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        #expect(await h.client.unlockedUntil != nil)
        h.bridge.restart(epoch: "e2")
        try await h.connected(times: 2)
        #expect(await h.client.unlockedUntil == nil)
        #expect(h.log.unlocks.last == .some(nil))
    }

    @Test func anElevatedCallLostInADropIsSignedAgainForTheNewConnection() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { request in
            request.method == "approve" ? .loseAnswer(.success(["approved": true])) : .answer(.success([:]))
        }
        try await h.connect()
        let result = try await h.client.callElevated("approve", ["id": "c1", "action_id": "a9"], reason: "Approve")
        #expect(result == ["approved": true])
        let approvals = h.bridge.requests("approve")
        #expect(approvals.count == 2)
        #expect(approvals[0].idem == approvals[1].idem && approvals[0].id == approvals[1].id)
        #expect(approvals[0].proof?.sig != approvals[1].proof?.sig)  // a new proof for the new connection's nonce
        #expect(h.bridge.proofsChecked == 2 && h.bridge.executions(of: "approve") == 1)
        #expect(h.bridge.problems.isEmpty)  // each proof checked against its own connection's nonce; no replay
        #expect(h.keys.reasons == ["Approve", "Approve"])  // within one Face ID window on the phone
    }

    @Test func anElevatedCallIsNotSentAgainToARestartedBridge() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { request in request.method == "approve" ? .silent : .answer(.success([:])) }
        try await h.connect()
        let pending = Task {
            try await h.client.callElevated("approve", ["id": "c1", "action_id": "a9"], reason: "Approve")
        }
        try await eventually("the approval") { h.bridge.requests("approve").count == 1 }
        h.bridge.restart(epoch: "e2")
        await #expect(throws: RemoteCallError.transport("bridge_restarted")) { try await pending.value }
        #expect(h.bridge.requests("approve").count == 1)
    }

    /// A clock the test moves forward, and an approve key whose first signature takes "25 s" of it (a slow Face ID).
    final class ShiftingClock: Sendable {
        private let offset = Mutex<TimeInterval>(0)
        func now() -> Date { Date().addingTimeInterval(offset.withLock { $0 }) }
        func advance(_ seconds: TimeInterval) { offset.withLock { $0 += seconds } }
    }

    final class SlowApproveKey: SigningKey {
        let inner = SoftwareSigningKey(role: .approve)
        let clock: ShiftingClock
        let signings = Mutex(0)
        init(clock: ShiftingClock) { self.clock = clock }
        var role: KeyRole { .approve }
        var publicKey: P256.Signing.PublicKey { inner.publicKey }
        func sign(_ message: Data, reason: String) async throws -> Data {
            if signings.withLock({ count in
                count += 1
                return count == 1
            }) {
                clock.advance(25)
            }
            return try await inner.sign(message, reason: reason)
        }
    }

    final class FixedKeyProvider: KeyProvider {
        let kept: DeviceKeys
        init(_ keys: DeviceKeys) { kept = keys }
        func makeKeys() async throws -> DeviceKeys { kept }
        func save(_ keys: DeviceKeys, for bridgeID: String) async throws {}
        func keys(for bridgeID: String) async throws -> DeviceKeys? { kept }
        func deleteKeys(for bridgeID: String) async throws {}
    }

    @Test func aSlowFaceIDSignsAFreshTime() async throws {
        let clock = ShiftingClock()
        let approve = SlowApproveKey(clock: clock)
        let keys = DeviceKeys(device: SoftwareSigningKey(role: .device), approve: approve)
        let bridge = FakeBridge()
        bridge.register(keys)
        let client = LiveClient(
            keys: FixedKeyProvider(keys), pairingReason: { $0 }, connector: FakeBridgeConnector(bridge: bridge),
            pathWatcher: ManualPathWatcher(), discovery: NoBridgeDiscovery(), configuration: LiveHarness.fast,
            clock: { clock.now() })
        let log = UpdateLog(client)
        await client.connect(to: PairedMac(
            bridgeID: bridge.bridgeID, name: "Mac", deviceID: "dev-1", pin: bridge.pin,
            endpoints: [LiveHarness.lan], pairedAt: Date()))
        try await eventually("connected") { log.connectedCount == 1 }
        _ = try await client.callElevated("approve", ["id": "c1", "action_id": "a1"], reason: "Approve")
        #expect(approve.signings.withLock { $0 } == 2)
        let ts = try #require(bridge.requests("approve").first?.proof?.ts)
        #expect(Double(ts) / 1000 - Date().timeIntervalSince1970 > 20)  // the time after Face ID, not before
        #expect(bridge.problems.isEmpty)
        await client.disconnect()
    }

    @Test func byeTooLargeReconnects() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        h.bridge.bye(ByeCode(rawValue: "too_large"), "That was too large.")
        try await h.connected(times: 2)
        #expect(!h.log.phases.contains { if case .failed = $0 { true } else { false } })
    }

    @Test func proofsFollowWelcomeElevatedIncludingSettingKeys() {
        let info = BridgeInfo(
            bridgeVersion: "0.3", macName: "Mac", pebbleRunning: true, pebbleVersion: nil,
            methods: ["state", "setting", "remote.unlock"], elevated: ["approve", "setting:permissions"],
            resumed: false)
        #expect(info.needsProof("approve"))
        #expect(!info.needsProof("send", ["chat_id": "c1"]))
        #expect(info.needsProof("setting", ["key": "permissions", "value": "full"]))
        #expect(!info.needsProof("setting", ["key": "theme", "value": "dark"]))
        #expect(!info.needsProof("setting"))
        #expect(info.offersUnlock)
        let older = BridgeInfo(
            bridgeVersion: "0.2", macName: "Mac", pebbleRunning: true, pebbleVersion: nil, methods: ["state"],
            elevated: ["approve", "setting"], resumed: false)
        #expect(older.needsProof("setting", ["key": "permissions"]))
        #expect(!older.needsProof("setting", ["key": "stealth"]))
        #expect(!older.offersUnlock)
    }
}
