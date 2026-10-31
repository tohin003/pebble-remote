import CryptoKit
import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane X, contract X-1 (claude-w's answer of 2026-10-30 10:49, item 3): after `pair` verifies, the phone and the Mac
// each show a six-digit code made from T_pair, and the bridge sends `paired` only once the person confirms on the Mac
// that the two match. A cancel, or two minutes without an answer, is `bye` `bad_code`, and the pairing code is spent.

/// A fixed T_pair and the code the contract's formula gives it. The first two come from lane C2's mock
/// (`bridge-mock/remote_wire.py`, `SAS_VECTORS`); the last two were made for this lane, with the hash written out
/// below, so that one has the digest's first byte above 0x80 (the integer needs all 32 bits, read unsigned) and one a
/// code the leading zero of which must stay.
///
/// Every row was checked against Python's hashlib, the formula's other implementation:
///
///     d = hashlib.sha256(b"pebble-remote/v1/sas\n" + t_pair).digest()
///     "%06d" % (int.from_bytes(d[:4], "big") % 1000000)
///
/// with `t_pair` = "pebble-remote/v1/pair\n" and then bid, nonce, pin, code, device_key and approve_key, each followed
/// by "\n".
struct PairingCodeVector: Sendable, CustomTestStringConvertible {
    var fields: [String]
    var digest: String
    var code: String
    var testDescription: String { "T_pair of \(fields[0]) gives \(code)" }

    static let all: [PairingCodeVector] = [
        PairingCodeVector(
            fields: ["b-1", "n-1", "p-1", "c-1", "dk-1", "ak-1"],
            digest: "57065e008e6e8ae233d92ebd1b61315ad0cb083f1a2d2ec6f428b7d804b937b5", code: "035072"),  // 0x57065e00 = 1460035072
        PairingCodeVector(
            fields: [
                "b-AAECAwQFBgcICQoL", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8",
                "uBxfZqYw5vyQji5sLR4Ex6QEFGKWKNk-v7nH6PPPyFM", "ZGVmZ2hpamtsbW5vcHFycw",
                "BAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8",
                "BEBBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn8",
            ],
            digest: "9d6a609c86ea7ca392c70ae278859a96aa42ee081bf53e9f23339ab73dde43c6", code: "994460"),  // 0x9d6a609c = 2640994460
        PairingCodeVector(
            fields: ["bridge-1", "nonce-1", "pin-1", "code-1", "devkey-1", "appkey-1"],
            digest: "789b40c7497f316517fc65e8a5178f8fa322a12548bf4aa562c107813fd4102f", code: "440583"),  // 2023440583
        PairingCodeVector(
            fields: ["bid", "n", "p", "c", "dk", "ak"],
            digest: "ea673f4e056c527639deea8f3757d0cdfab889090ff4654075a1ad0dd73687fe", code: "634958"),  // 3932634958
    ]

    /// T_pair for these fields, built by the phone's own builder.
    func transcript() throws -> Data {
        try SignedTranscript.pair(
            bridgeID: fields[0], nonce: fields[1], pin: fields[2], code: fields[3], deviceKey: fields[4],
            approveKey: fields[5])
    }
}

/// The codes a client shows while pairing, each with how many `pair` frames the bridge had received when it was shown.
final class ShownCodes: Sendable {
    private let bridge: FakeBridge
    private let items = Mutex<[(code: PairingCode, pairs: Int)]>([])

    init(_ bridge: FakeBridge) { self.bridge = bridge }

    /// The callback to give `pair`.
    var showing: @Sendable (PairingCode) -> Void {
        { [self] code in items.withLock { $0.append((code, bridge.pairs.count)) } }
    }

    var codes: [PairingCode] { items.withLock { $0.map(\.code) } }
    var pairsReceivedWhenShown: [Int] { items.withLock { $0.map(\.pairs) } }
}

/// Whether a pairing has returned or thrown.
final class Finished: Sendable {
    private let state = Mutex(false)
    func set() { state.withLock { $0 = true } }
    var isSet: Bool { state.withLock { $0 } }
}

/// A client that pairs with a bridge in memory, the Mac's person confirming by hand.
struct PairingHarness {
    let bridge: FakeBridge
    let keys: RecordingKeyProvider
    let client: LiveClient
    let link: PairingLink
    let shown: ShownCodes

    static func make(
        confirming: Bool = true, confirmationTimeout: Duration = .seconds(10), readTimeout: Duration = .seconds(2),
        pingInterval: Duration = .seconds(60), linkCode: String = "c0de-X1"
    ) -> PairingHarness {
        let bridge = FakeBridge()
        bridge.allowPairing(code: "c0de-X1")
        if confirming { bridge.requirePairingConfirmation() }
        let keys = RecordingKeyProvider()
        let client = LiveClient(
            keys: keys, pairingReason: { "Pair with \($0)" }, connector: FakeBridgeConnector(bridge: bridge),
            pathWatcher: ManualPathWatcher(), discovery: NoBridgeDiscovery(),
            device: DeviceDescription(model: "iPhone18,3", os: "iOS 26.1", app: "1.0 (1)"),
            configuration: LiveClient.Configuration(
                requestTimeout: .seconds(3), readTimeout: readTimeout, pingInterval: pingInterval,
                pingTimeout: .seconds(1), raceDelay: .milliseconds(150),
                backoff: Backoff(initial: .milliseconds(20), maximum: .milliseconds(100)),
                pairingConfirmationTimeout: confirmationTimeout, lockTimeout: .milliseconds(300)))
        let link = PairingLink(
            version: 1, bridgeID: bridge.bridgeID, macName: "Mac", pin: bridge.pin, code: linkCode,
            endpoints: [LiveHarness.lan])
        return PairingHarness(bridge: bridge, keys: keys, client: client, link: link, shown: ShownCodes(bridge))
    }

    /// Starts pairing; `finished` says whether it has returned or thrown.
    func start() -> (task: Task<PairedMac, any Error>, finished: Finished) {
        let finished = Finished()
        let (client, link, shown) = (self.client, self.link, self.shown)
        let task = Task { () throws -> PairedMac in
            defer { finished.set() }
            return try await client.pair(link, deviceName: "Sam's iPhone", showingCode: shown.showing)
        }
        return (task, finished)
    }
}

@Suite("Lane X: the formula for the code (X-1)")
struct PairingCodeFormulaTests {
    @Test(arguments: PairingCodeVector.all)
    func theCodeIsTheFirstFourBytesOfTheHashModAMillion(_ vector: PairingCodeVector) throws {
        let transcript = try vector.transcript()
        // The very bytes the pair signatures cover: the label line, then the six fields, each followed by "\n".
        #expect(String(decoding: transcript, as: UTF8.self) == "pebble-remote/v1/pair\n" + vector.fields.map { $0 + "\n" }.joined())
        // The hash is over "pebble-remote/v1/sas\n" followed by T_pair.
        let digest = SHA256.hash(data: Data("pebble-remote/v1/sas\n".utf8) + transcript)
        #expect(digest.map { String(format: "%02x", $0) }.joined() == vector.digest)
        #expect(PairingCode(pairTranscript: transcript).digits == vector.code)
        // The fake Mac's separate implementation agrees.
        #expect(FakeBridge.macCode(for: transcript) == vector.code)
    }

    @Test func theIntegerIsBigEndianAndUnsigned() throws {
        // 0x9d6a609c is above 2^31: read as a signed or little-endian number it would give another code.
        let vector = PairingCodeVector.all[1]
        #expect(2_640_994_460 % 1_000_000 == 994_460)
        #expect(PairingCode(pairTranscript: try vector.transcript()).digits == "994460")
        #expect(UInt32(0x9c60_6a9d) % 1_000_000 != 994_460)  // the same four bytes read little-endian
        #expect(Int32(bitPattern: 0x9d6a_609c) % 1_000_000 != 994_460)  // the same integer read as signed
    }

    @Test func aLeadingZeroIsKept() throws {
        let code = PairingCode(pairTranscript: try PairingCodeVector.all[0].transcript())
        #expect(code.digits == "035072" && code.grouped == "035 072" && code.description == "035072")
    }

    @Test func theCodeIsReadOneDigitAtATimeByVoiceOver() throws {
        let code = try #require(PairingCode(digits: "035072"))
        #expect(code.spoken == "0 3 5, 0 7 2")
    }

    @Test func aCodeFromTextIsSixAsciiDigits() {
        #expect(PairingCode(digits: "123456")?.grouped == "123 456")
        for text in ["", "12345", "1234567", "12345a", "12 456", "١٢٣٤٥٦", "１２３４５６", "-12345", "+12345"] {
            #expect(PairingCode(digits: text) == nil, "\(text) is not a code")
        }
    }

    @Test func aDifferentPairingGivesADifferentCode() throws {
        // The nonce, the keys and the link's code are all in T_pair, so another pairing (another phone, another try)
        // shows another code: a link that someone else used cannot make the Mac show this phone's code.
        let base = try PairingCodeVector.all[0].transcript()
        var changed = PairingCodeVector.all[0]
        changed.fields[1] = "n-2"
        #expect(PairingCode(pairTranscript: base) != PairingCode(pairTranscript: try changed.transcript()))
    }
}

@Suite("Lane X: confirming each pairing on the Mac (X-1)")
struct PairingConfirmationTests {
    // MARK: The flow

    @Test func theCodeIsShownOnceThePairIsSentAndThePhoneWaitsForTheMacToConfirm() async throws {
        let h = PairingHarness.make()
        let (pairing, finished) = h.start()
        try await eventually("the code") { h.shown.codes.count == 1 }
        // Shown after `pair` reached the Mac, and the same six digits the Mac shows: both made from the T_pair the
        // pair signatures cover (the fake Mac builds it from the frame it received and its own nonce).
        #expect(h.shown.pairsReceivedWhenShown == [1])
        #expect(h.shown.codes.first?.digits == h.bridge.pairingCodes.first)
        #expect(h.bridge.pairingCodes.count == 1)
        // The Mac waits for the person: no `paired`, nothing stored, and the phone is still waiting.
        try await Task.sleep(for: .milliseconds(250))
        #expect(h.bridge.isAwaitingConfirmation && !finished.isSet)
        #expect(try await h.keys.keys(for: h.bridge.bridgeID) == nil)
        // The person confirms on the Mac.
        #expect(h.bridge.confirmPairing())
        let mac = try await pairing.value
        #expect(mac.deviceID == "dev-1" && mac.name == "Studio Mac" && mac.pin == h.bridge.pin)
        let kept = try #require(try await h.keys.keys(for: h.bridge.bridgeID))
        let pair = try #require(h.bridge.pairs.first)
        #expect(kept.device.publicKeyText == pair.deviceKey && kept.approve.publicKeyText == pair.approveKey)
        #expect(h.shown.codes.count == 1)  // shown once, not again
        #expect(h.bridge.problems.isEmpty)
        let pairingSocketsClosed = h.bridge.sockets.allSatisfy { $0.isClosed }
        #expect(pairingSocketsClosed)
    }

    @Test func aMacThatNeverAsksStillPairsAsBefore() async throws {
        // A bridge from before X-1 answers `paired` at once; the phone shows the code for a moment and carries on.
        let h = PairingHarness.make(confirming: false)
        let (pairing, _) = h.start()
        let mac = try await pairing.value
        #expect(mac.deviceID == "dev-1")
        #expect(h.shown.codes.count == 1 && h.shown.codes.first?.digits == h.bridge.pairingCodes.first)
        #expect(h.bridge.problems.isEmpty)
    }

    @Test func thePhoneWaitsLongerThanItsOrdinaryReadTimeout() async throws {
        // The person needs far more than a read's 10 s. Here the read timeout is 300 ms and the Mac takes 800 ms.
        let h = PairingHarness.make(readTimeout: .milliseconds(300))
        let (pairing, _) = h.start()
        try await eventually("the code") { h.shown.codes.count == 1 }
        try await Task.sleep(for: .milliseconds(800))
        #expect(h.bridge.confirmPairing())
        _ = try await pairing.value
        #expect(h.bridge.problems.isEmpty)
    }

    @Test func theDefaultWaitCoversTheMacsTwoMinutesAndAFewSecondsMore() {
        let wait = LiveClient.Configuration().pairingConfirmationTimeout
        #expect(wait > .seconds(120) && wait <= .seconds(140))
    }

    // MARK: When the Mac does not confirm

    @Test func aCancelOnTheMacIsAByeBadCodeAfterTheCodeWasShownAndKeepsNothing() async throws {
        let h = PairingHarness.make()
        let (pairing, _) = h.start()
        try await eventually("the code") { h.shown.codes.count == 1 }
        h.bridge.refusePairing()
        await #expect(throws: RemoteCallError.transport("bad_code")) { try await pairing.value }
        #expect(try await h.keys.keys(for: h.bridge.bridgeID) == nil)
        #expect(h.shown.codes.count == 1)
        let closed = h.bridge.sockets.allSatisfy { $0.isClosed }
        #expect(closed)
        // The pairing code is spent: the same link gets nothing more.
        let again = h.start().task
        await #expect(throws: RemoteCallError.transport("bad_code")) { try await again.value }
    }

    @Test func aLinkTheMacRefusesAtOnceShowsTheCodeForAMomentThenBadCode() async throws {
        // The phone cannot tell a wrong, used or expired link from a person's Cancel: both are `bye` `bad_code`. The
        // code went out before the answer came, so the screens' words cover both (AppCopy.Pairing.notConfirmed).
        let h = PairingHarness.make(linkCode: "wrong")
        await #expect(throws: RemoteCallError.transport("bad_code")) { try await h.start().task.value }
        #expect(h.shown.codes.count == 1)
        #expect(try await h.keys.keys(for: h.bridge.bridgeID) == nil)
    }

    @Test func noAnswerInTheTimeThePersonHasIsNotConfirmed() async throws {
        let h = PairingHarness.make(confirmationTimeout: .milliseconds(300))
        let (pairing, _) = h.start()
        await #expect(throws: RemoteCallError.transport("not_confirmed")) { try await pairing.value }
        #expect(h.shown.codes.count == 1)
        #expect(try await h.keys.keys(for: h.bridge.bridgeID) == nil)
        let closed = h.bridge.sockets.allSatisfy { $0.isClosed }
        #expect(closed)
        // The Mac's person confirming now finds no phone waiting.
        #expect(!h.bridge.confirmPairing())
    }

    @Test func aConnectionThatEndsWithNoWordIsNotConfirmed() async throws {
        let h = PairingHarness.make()
        let (pairing, _) = h.start()
        try await eventually("the code") { h.shown.codes.count == 1 }
        h.bridge.sockets.first?.closeNow()  // the Mac closes (or the network drops) without a `bye`
        await #expect(throws: RemoteCallError.transport("not_confirmed")) { try await pairing.value }
        #expect(try await h.keys.keys(for: h.bridge.bridgeID) == nil)
    }

    @Test func thePersonLeavingTheWaitKeepsNothingAndTellsTheMacByClosing() async throws {
        let h = PairingHarness.make()
        let (pairing, _) = h.start()
        try await eventually("the code") { h.shown.codes.count == 1 }
        pairing.cancel()
        await #expect(throws: RemoteCallError.cancelledByPerson) { try await pairing.value }
        #expect(try await h.keys.keys(for: h.bridge.bridgeID) == nil)
        let closed = h.bridge.sockets.allSatisfy { $0.isClosed }
        #expect(closed)
        #expect(!h.bridge.confirmPairing())  // the Mac sees the phone gone, and stores nothing
    }

    // MARK: Staying connected while the person looks at the Mac

    @Test func thePhonePingsWhileItWaitsSoNeitherSideTakesTheQuietForADeadConnection() async throws {
        let h = PairingHarness.make(pingInterval: .milliseconds(40))
        let (pairing, _) = h.start()
        try await eventually("the code") { h.shown.codes.count == 1 }
        try await eventually("pings while the Mac waits") { (h.bridge.sockets.first?.pings ?? 0) >= 3 }
        #expect(h.bridge.confirmPairing())
        _ = try await pairing.value
    }

    // MARK: Words and codes for the screens

    @Test func theClientsOwnCodesForAPairingThatWasNotConfirmed() {
        #expect(LiveClient.callError(for: Handshake.Failure.notConfirmed) == .transport("not_confirmed"))
        #expect(LiveClient.callError(for: Handshake.Failure.bye(ByeFrame(code: .badCode))) == .transport("bad_code"))
        #expect(LiveClient.callError(for: CancellationError()) == .cancelledByPerson)
        // A pairing never reconnects, so a failed one is no connection problem.
        #expect(LiveClient.problem(for: Handshake.Failure.notConfirmed) == nil)
    }
}
