import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane X, contract S-05 (claude-w's answer of 2026-10-30 10:49, item 4): the unlock ends when the phone stops using it.
// `remote.lock` (a read, `{}` to `{}`) ends this device's unlock at once, and the bridge also ends it when the device's
// last connection closes. The phone calls `remote.lock` when the app goes to the background and when its own lock
// engages, briefly and ignoring failure; clears what its screens claim on lock and on disconnect; and skips the call on
// a bridge that does not offer it.

@Suite("Lane X: the unlock ends when the phone stops using it (S-05)")
struct UnlockEndsTests {
    /// A harness whose bridge asks for the unlock, and offers `remote.lock` unless `older`.
    static func make(older: Bool = false, unlockReason: String? = nil) async throws -> LiveHarness {
        var configuration = LiveHarness.fast
        configuration.lockTimeout = .milliseconds(300)
        let h = try await LiveHarness.make(configuration: configuration, unlockReason: unlockReason)
        h.bridge.requireUnlock(window: 600, announce: 600)
        if !older { h.bridge.offerLock() }
        return h
    }

    /// The client reported `.unlocked(until: nil)`: the log that stands for the store catches up on its own task.
    static func screensAreToldItIsLocked(_ h: LiveHarness) async throws {
        try await eventually("the screens were told it is locked") { h.log.unlocks.last == .some(nil) }
    }

    /// The next call that acts, as the bridge answers it.
    static func refusal(_ h: LiveHarness) async throws -> String? {
        do {
            _ = try await h.client.call("send", ["chat_id": "c1", "text": "hi"])
            return nil
        } catch RemoteCallError.refused(let refusal) {
            return refusal.code
        }
    }

    // MARK: remote.lock

    @Test func lockingEndsTheUnlockOnTheMacAndOnTheScreens() async throws {
        let h = try await Self.make()
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        #expect(await h.client.unlockedUntil != nil)
        #expect(try await Self.refusal(h) == nil)  // unlocked: the act goes through

        await h.client.lock()
        let locks = h.bridge.requests("remote.lock")
        #expect(locks.count == 1)
        // A read: `{}`, no `idem`, no proof, and it was sent on the open connection.
        #expect(locks.first?.params == [:] && locks.first?.idem == nil && locks.first?.proof == nil)
        #expect(await h.client.unlockedUntil == nil)
        try await Self.screensAreToldItIsLocked(h)
        #expect(h.bridge.problems.isEmpty)
        // The Mac ended it too: the next call that acts is refused until Face ID unlocks again.
        #expect(try await Self.refusal(h) == "unlock_required")
        #expect(h.bridge.executions(of: "send") == 1)  // only the first
    }

    @Test func lockingWorksWhileAlreadyLockedAndAsOftenAsAsked() async throws {
        let h = try await Self.make()
        try await h.connect()
        await h.client.lock()
        await h.client.lock()
        #expect(h.bridge.requests("remote.lock").count == 2 && h.bridge.problems.isEmpty)  // a read: allowed while locked
        #expect(await h.client.unlockedUntil == nil)
    }

    @Test func anOlderBridgeIsNotAskedButTheScreensStopClaimingTheUnlock() async throws {
        let h = try await Self.make(older: true)
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        #expect(await h.client.unlockedUntil != nil)
        await h.client.lock()
        #expect(h.bridge.requests("remote.lock").isEmpty)
        #expect(h.bridge.problems.isEmpty)  // the fake flags a `remote.lock` sent to a bridge that does not offer it
        #expect(await h.client.unlockedUntil == nil)
        try await Self.screensAreToldItIsLocked(h)
        // Its old behaviour stands: that bridge still has the unlock, so an act is not refused.
        #expect(try await Self.refusal(h) == nil)
    }

    @Test(arguments: [false, true])
    func lockingAndDisconnectingEndTheApprovalWindowToo(older: Bool) async throws {
        // S-14: the Face ID check that covers the next approvals for 30 s must not outlive the unlock, on any bridge.
        let h = try await Self.make(older: older)
        try await h.connect()
        #expect(h.keys.windowEnds == 0)
        await h.client.lock()
        #expect(h.keys.windowEnds == 1)
        await h.client.disconnect()
        #expect(h.keys.windowEnds == 2)
    }

    @Test func theApprovalGateCanBeEndedWithNothingToEnd() async {
        await ApprovalGate().endWindow()  // no Face ID was asked: nothing to drop, and nothing breaks
        await SecureEnclaveKeyProvider(store: InMemorySecretStore()).endApprovalWindow()
    }

    @Test func aLockThatGetsNoAnswerIsGivenUpQuicklyAndIgnored() async throws {
        let h = try await Self.make()
        h.bridge.respond { request in request.method == "remote.lock" ? .silent : .answer(.success([:])) }
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        let started = ContinuousClock.now
        await h.client.lock()  // returns, throws nothing
        #expect(ContinuousClock.now - started < .seconds(2), "the lock call is brief (300 ms here), not the 3 s of an ordinary call")
        #expect(await h.client.unlockedUntil == nil)
        #expect(h.bridge.requests("remote.lock").count == 1)
        // The connection was not harmed.
        _ = try await h.client.call("state", [:])
        #expect(h.bridge.problems.isEmpty)
    }

    @Test func aLockThatIsRefusedIsIgnoredToo() async throws {
        let h = try await Self.make()
        h.bridge.respond { request in
            request.method == "remote.lock" ? .answer(.failure(error: "Not now.", code: "rate_limited")) : .answer(.success([:]))
        }
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        await h.client.lock()
        #expect(await h.client.unlockedUntil == nil)
    }

    @Test func lockingWithoutAConnectionOnlyClearsWhatTheScreensShow() async throws {
        let h = try await Self.make()
        await h.client.lock()
        #expect(h.bridge.opens.isEmpty && h.bridge.requests.isEmpty)
        #expect(await h.client.unlockedUntil == nil)
    }

    @Test func lockingWhileTheConnectionIsLostDoesNotWait() async throws {
        let h = try await Self.make()
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        await h.client.disconnect()
        let started = ContinuousClock.now
        await h.client.lock()
        #expect(ContinuousClock.now - started < .seconds(1))  // not the lock timeout (300 ms here), let alone a call's 3 s
        #expect(h.bridge.requests("remote.lock").isEmpty)
    }

    // MARK: Clearing what the screens claim

    @Test(arguments: [false, true])
    func disconnectingClearsWhatTheScreensClaim(older: Bool) async throws {
        let h = try await Self.make(older: older)
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        #expect(await h.client.unlockedUntil != nil)
        await h.client.disconnect()
        #expect(await h.client.unlockedUntil == nil)
        try await Self.screensAreToldItIsLocked(h)
    }

    @Test func aLostConnectionEndsTheUnlockOfABridgeThatOffersLock() async throws {
        let h = try await Self.make()
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        h.bridge.drop()  // the last connection closes: the bridge ends the unlock
        try await eventually("the screens stop claiming it") { await h.client.unlockedUntil == nil }
        try await h.connected(times: 2)
        #expect(await h.client.unlockedUntil == nil)
        try await Self.screensAreToldItIsLocked(h)
        // And the bridge really did: the first act after the reconnect needs Face ID again.
        #expect(try await Self.refusal(h) == "unlock_required")
    }

    @Test func aLostConnectionLeavesAnOlderBridgesUnlockAlone() async throws {
        let h = try await Self.make(older: true)
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        let until = await h.client.unlockedUntil
        h.bridge.drop()
        try await h.connected(times: 2)
        #expect(await h.client.unlockedUntil == until)  // its old behaviour: the unlock outlives the connection
        #expect(try await Self.refusal(h) == nil)
    }

    @Test func aNewerConnectionOfThisPhoneTakingOverCarriesTheUnlockOn() async throws {
        // A network change races again; the bridge welcomes the new connection and closes the old with `replaced`. The
        // device never had no connection, so its unlock carries on.
        let h = try await LiveHarness.make(
            endpoints: [LiveHarness.lan, LiveHarness.tailnet], configuration: LiveHarness.fast)
        h.bridge.requireUnlock(window: 600, announce: 600)
        h.bridge.offerLock()
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        let until = await h.client.unlockedUntil
        #expect(until != nil)
        h.watcher.change()
        try await eventually("a second hello and the old socket closed") {
            h.bridge.hellos.count == 2 && h.bridge.sockets.first?.isClosed == true
        }
        try await eventually("connected") { await h.phase() == .connected }
        #expect(await h.client.unlockedUntil == until)
        #expect(try await Self.refusal(h) == nil)
        #expect(h.log.unlocks.last != .some(nil))
    }

    @Test func aRefusedUnlockRequiredStillClearsTheClaim() async throws {
        // Unchanged by S-05: a refusal of `unlock_required` means the bridge says locked, whatever the phone thought.
        let h = try await Self.make()
        try await h.connect()
        try await h.client.unlock(reason: "Unlock")
        h.bridge.lock()  // the window ran out on the bridge
        #expect(try await Self.refusal(h) == "unlock_required")
        #expect(await h.client.unlockedUntil == nil)
    }
}

/// A store on a live client against the bridge in memory, the store its only consumer of the client's updates.
@MainActor
struct StoreHarness {
    let bridge: FakeBridge
    let client: LiveClient
    let store: RemoteStore

    static func make(older: Bool = false) async throws -> StoreHarness {
        let bridge = FakeBridge()
        let keys = RecordingKeyProvider()
        let deviceKeys = try await keys.makeKeys()
        try await keys.save(deviceKeys, for: bridge.bridgeID)
        bridge.register(deviceKeys, id: "dev-1")
        bridge.requireUnlock(window: 600, announce: 600)
        if !older { bridge.offerLock() }
        var configuration = LiveHarness.fast
        configuration.lockTimeout = .milliseconds(300)
        let client = LiveClient(
            keys: keys, pairingReason: { $0 }, connector: FakeBridgeConnector(bridge: bridge),
            pathWatcher: ManualPathWatcher(), discovery: NoBridgeDiscovery(),
            device: DeviceDescription(model: "iPhone18,3", os: "iOS 26.1", app: "1.0 (1)"), configuration: configuration)
        let mac = PairedMac(
            bridgeID: bridge.bridgeID, name: "Studio Mac", deviceID: "dev-1", pin: bridge.pin,
            endpoints: [LiveHarness.lan], pairedAt: Date())
        return StoreHarness(bridge: bridge, client: client, store: RemoteStore(client: client, pairedMac: mac))
    }

    /// Starts the store and waits until it shows the connection and the bridge's welcome.
    func start() async -> Bool {
        store.start()
        return await eventually { store.connection.phase == .connected && store.bridge != nil }
    }
}

/// The store's side: stopping ends the Mac's unlock first, then closes the connection, and the screens follow.
@MainActor
@Suite("Lane X: the store ends the unlock before it stops (S-05)")
struct StoreLockTests {
    @Test func stoppingEndsTheUnlockOnTheMacBeforeTheConnectionCloses() async throws {
        let h = try await StoreHarness.make()
        #expect(await h.start())
        try await h.store.unlock()
        #expect(await eventually { h.store.isUnlocked })

        h.store.stop()
        #expect(await eventually { h.store.connection.phase == .idle })
        // The call reached the Mac on the open connection (a closed socket delivers nothing), and the close came after it.
        #expect(h.bridge.requests("remote.lock").count == 1)
        let closed = h.bridge.sockets.allSatisfy { $0.isClosed }
        #expect(closed)
        #expect(h.store.unlockedUntil == nil && !h.store.isUnlocked)
        #expect(h.bridge.problems.isEmpty)
    }

    @Test func lockingTwiceAtOnceAsksTheMacOnce() async throws {
        // Going to the background and the app lock engaging happen together.
        let h = try await StoreHarness.make()
        #expect(await h.start())
        try await h.store.unlock()
        #expect(await eventually { h.store.isUnlocked })
        async let first: Void = h.store.lock()
        async let second: Void = h.store.lock()
        _ = await (first, second)
        #expect(h.bridge.requests("remote.lock").count == 1)
        #expect(h.store.unlockedUntil == nil)
    }

    @Test func theStoreClearsItsClaimEvenWhenTheClientCannotAskTheMac() async throws {
        let h = try await StoreHarness.make(older: true)
        #expect(await h.start())
        try await h.store.unlock()
        #expect(await eventually { h.store.isUnlocked })
        await h.store.lock()
        #expect(h.store.unlockedUntil == nil)
        #expect(h.bridge.requests("remote.lock").isEmpty && h.bridge.problems.isEmpty)
    }

    @Test func theStoreFollowsTheClientWhenTheConnectionEndsTheUnlock() async throws {
        let h = try await StoreHarness.make()
        #expect(await h.start())
        try await h.store.unlock()
        #expect(await eventually { h.store.isUnlocked })
        h.bridge.drop()  // the bridge ends a device's unlock when its last connection closes
        #expect(await eventually { h.store.unlockedUntil == nil })
    }

    @Test func comingBackQuicklyIsNotUndoneByAStopThatIsStillEndingTheUnlock() async throws {
        // `stop()` waits for the Mac's answer to `remote.lock` (here 300 ms: it never comes); a `start()` made meanwhile
        // must run after the stop's disconnect, not before it, or the app would come back to the foreground with no
        // connection.
        let h = try await StoreHarness.make()
        h.bridge.respond { request in request.method == "remote.lock" ? .silent : .answer(.success([:])) }
        #expect(await h.start())
        h.store.stop()
        h.store.start()
        #expect(await eventually { h.bridge.hellos.count == 2 && h.store.connection.phase == .connected })
        try await Task.sleep(for: .milliseconds(400))
        #expect(h.store.connection.phase == .connected)
        #expect(h.bridge.hellos.count == 2)
    }
}
