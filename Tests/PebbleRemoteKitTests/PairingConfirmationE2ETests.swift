import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane X end to end: X-1 (the person confirms each pairing on the Mac) and S-05 (the unlock ends when the phone stops
// using it) against lane C2's mock bridge over real TLS 1.3. The mock prints `PAIRING_CODE=123456` when a pairing waits
// for its person, which the phone's own code is compared with. Skipped unless PEBBLE_MOCK_E2E=1:
//
//     PEBBLE_MOCK_E2E=1 scripts/swift.sh test --filter E2E

/// Values that closures running anywhere add to, and a test reads.
final class Recorded<Element: Sendable>: Sendable {
    private let state = Mutex<[Element]>([])
    func add(_ element: Element) { state.withLock { $0.append(element) } }
    var all: [Element] { state.withLock { $0 } }
}

@Suite("Lane X: X-1 and S-05 end to end with the mock bridge", .serialized)
struct PairingConfirmationE2ETests {
    private static func client(
        keys: RecordingKeyProvider = RecordingKeyProvider(), unlockReason: String? = nil,
        connector: any FrameSocketConnector = NetworkSocketConnector(), pairingConfirmationTimeout: Duration = .seconds(30)
    ) -> LiveClient {
        LiveClient(
            keys: keys, pairingReason: { "Pair with \($0)" }, unlockReason: unlockReason, connector: connector,
            pathWatcher: StillPathWatcher(), discovery: NoBridgeDiscovery(),
            device: DeviceDescription(model: "iPhone18,3", os: "iOS 26.1", app: "1.0 (1)"),
            configuration: LiveClient.Configuration(
                backoff: Backoff(initial: .milliseconds(100), maximum: .seconds(1)),
                pairingConfirmationTimeout: pairingConfirmationTimeout))
    }

    @Test(.enabled(if: MockBridgeE2ETests.enabled), .timeLimit(.minutes(1)))
    func thePhoneShowsTheCodeTheMacShowsAndPairsOnlyOnceTheMacConfirms() async throws {
        // The mock confirms after 1 s, as a person would after comparing the two screens.
        let mock = try await MockBridgeProcess.launch(extraArguments: ["--pair-confirm-delay", "1"])
        defer { mock.stop() }
        let link = try #require(PairingLink(string: mock.pairingLink))
        let shown = Recorded<(code: PairingCode, at: ContinuousClock.Instant)>()
        let client = Self.client()

        let mac = try await client.pair(link, deviceName: "Test iPhone") { code in
            shown.add((code, ContinuousClock.now))
        }
        let finished = ContinuousClock.now

        // One code, shown while the Mac waited for its person (the mock waits 1 s after it verifies the pairing, which
        // is after the phone has shown its code), and the same six digits the Mac shows.
        #expect(shown.all.count == 1)
        let code = try #require(shown.all.first)
        #expect(finished - code.at >= .milliseconds(600), "`paired` came only after the Mac's person confirmed")
        #expect(try await mock.pairingCodes(waitingFor: 1) == [code.code.digits], "the Mac shows the same six digits")
        #expect(!mac.deviceID.isEmpty && mac.bridgeID == link.bridgeID)
    }

    @Test(.enabled(if: MockBridgeE2ETests.enabled), .timeLimit(.minutes(1)))
    func aCancelOnTheMacIsABadCodeAfterTheCodeWasShownAndTheLinkIsSpent() async throws {
        let mock = try await MockBridgeProcess.launch(extraArguments: ["--pair-confirm", "refuse"])
        defer { mock.stop() }
        let link = try #require(PairingLink(string: mock.pairingLink))
        let keys = RecordingKeyProvider()
        let shown = Recorded<PairingCode>()
        let client = Self.client(keys: keys)
        do {
            _ = try await client.pair(link, deviceName: "Test iPhone") { code in shown.add(code) }
            Issue.record("a pairing the Mac refused was accepted")
        } catch RemoteCallError.transport(let code) {
            #expect(code == "bad_code")
        }
        // The code was shown first, and it was the Mac's.
        #expect(shown.all.map(\.digits) == (try await mock.pairingCodes(waitingFor: 1)))
        #expect(try await keys.keys(for: link.bridgeID) == nil)
        // The pairing code is spent: the same link is refused again at once, with nothing shown to confirm.
        do {
            _ = try await Self.client().pair(link, deviceName: "Another iPhone")
            Issue.record("a spent link was accepted")
        } catch RemoteCallError.transport(let code) {
            #expect(code == "bad_code")
        }
    }

    @Test(.enabled(if: MockBridgeE2ETests.enabled), .timeLimit(.minutes(1)))
    func twoMinutesWithoutAnAnswerAreTheMacsByeBadCodeToo() async throws {
        // The Mac waits for a person who never answers (`ask` reads stdin, which is empty) and gives up after 1 s here;
        // the phone, which waits longer than the Mac does, hears its `bye`.
        let mock = try await MockBridgeProcess.launch(
            extraArguments: ["--pair-confirm", "ask", "--pair-confirm-timeout", "1"])
        defer { mock.stop() }
        let link = try #require(PairingLink(string: mock.pairingLink))
        let started = ContinuousClock.now
        do {
            _ = try await Self.client().pair(link, deviceName: "Test iPhone")
            Issue.record("a pairing nobody confirmed was accepted")
        } catch RemoteCallError.transport(let code) {
            #expect(code == "bad_code")
        }
        #expect(ContinuousClock.now - started >= .milliseconds(900), "the phone waited for the Mac's answer")
    }

    @Test(.enabled(if: MockBridgeE2ETests.enabled), .timeLimit(.minutes(1)))
    func leavingTheWaitIsNotAPairing() async throws {
        let mock = try await MockBridgeProcess.launch(extraArguments: ["--pair-confirm", "ask"])
        defer { mock.stop() }
        let link = try #require(PairingLink(string: mock.pairingLink))
        let keys = RecordingKeyProvider()
        let shown = Recorded<PairingCode>()
        let client = Self.client(keys: keys)
        let pairing = Task {
            try await client.pair(link, deviceName: "Test iPhone") { code in shown.add(code) }
        }
        try await eventually("the code", timeout: .seconds(15)) { shown.all.count == 1 }
        pairing.cancel()
        await #expect(throws: RemoteCallError.cancelledByPerson) { try await pairing.value }
        #expect(try await keys.keys(for: link.bridgeID) == nil)
    }

    @Test(.enabled(if: MockBridgeE2ETests.enabled), .timeLimit(.minutes(1)))
    func theUnlockEndsWithLockAndWithTheLastConnection() async throws {
        let mock = try await MockBridgeProcess.launch(extraArguments: ["--pair-confirm-delay", "0.2"])
        defer { mock.stop() }
        let link = try #require(PairingLink(string: mock.pairingLink))
        let keys = RecordingKeyProvider()
        let connector = RecordingConnector()
        // No unlock sentence: a refusal of `unlock_required` reaches the caller instead of asking for Face ID.
        let client = Self.client(keys: keys, connector: connector)
        let log = UpdateLog(client)
        let mac = try await client.pair(link, deviceName: "Test iPhone")
        await client.connect(to: mac)
        try await eventually("connected", timeout: .seconds(15)) { log.connectedCount >= 1 }
        let info = try #require(log.welcomes.first)
        #expect(info.methods.contains("remote.lock"))

        // Unlocked by Face ID, an act goes through.
        try await client.unlock(reason: "Unlock Pebble")
        #expect(await client.unlockedUntil != nil)
        let state = try await client.call("state", [:])
        let chats = try #require(state["chats"]?.array)
        let chatID = try #require(chats.first?["id"]?.string)
        let title = try #require(chats.first?["title"]?.string)
        _ = try await client.call("chat_rename", ["id": .string(chatID), "title": .string(title)])

        // `remote.lock`: the screens stop claiming it, and the Mac ends it too.
        await client.lock()
        #expect(await client.unlockedUntil == nil)
        #expect(log.unlocks.last == .some(nil))
        #expect(try await Self.refusal(client, chatID, title) == "unlock_required")

        // Unlocked again; then the connection drops. The Mac ends the unlock when the device's last connection closes,
        // and the phone stops claiming it at the same moment.
        try await client.unlock(reason: "Unlock Pebble")
        #expect(await client.unlockedUntil != nil)
        await connector.dropNewest()
        try await eventually("the phone stopped claiming it", timeout: .seconds(15)) { await client.unlockedUntil == nil }
        try await eventually("reconnected", timeout: .seconds(15)) { log.connectedCount >= 2 }
        #expect(try await Self.refusal(client, chatID, title) == "unlock_required")

        await client.disconnect()
        #expect(await client.unlockedUntil == nil)
    }

    /// The code the Mac answers a call that acts with, or nil when it went through.
    private static func refusal(_ client: LiveClient, _ chatID: String, _ title: String) async throws -> String? {
        do {
            _ = try await client.call("chat_rename", ["id": .string(chatID), "title": .string(title)])
            return nil
        } catch RemoteCallError.refused(let refusal) {
            return refusal.code
        }
    }
}
