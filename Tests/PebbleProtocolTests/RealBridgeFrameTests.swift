import Foundation
import Testing

@testable import PebbleProtocol

// Frames exactly as Pebble 1.9.29's own bridge writes them (read-only Pebble checkout: backend/pebble/remote_bridge.py
// and remote_keys.py; `dumps` is compact JSON that keeps UTF-8, and an `evt` frame is formatted by hand in `publish`).
// FrameTests checks the contract's examples; these check what the real bridge sends that the examples leave out:
// `welcome.unlock_seconds`, every `bye` code with its words, refusals with and without a code, an answer a retry gets
// with its result dropped, and the bridge's own events (an array as `data`, a null battery, a trimmed event).

private func realFrame(_ text: String) throws -> Frame { try FrameCodec.decode(text) }

@Test func realChallengeAndPairedDecode() throws {
    let challenge = try realFrame(
        #"{"t":"challenge","v":1,"bid":"b-0123456789abcdef","nonce":"qL3m0vW2b9xY1z8kP4nR6tU7cA5dE0fG3hJ2iK1lM9o","time":1761900000123}"#
    )
    guard case .challenge(let frame) = challenge else { Issue.record("not a challenge"); return }
    #expect(frame.version == 1 && frame.bridgeID == "b-0123456789abcdef" && frame.time == 1_761_900_000_123)
    #expect(frame.nonce.count == 43)  // 32 bytes, base64url without padding

    guard case .paired(let paired) = try realFrame(#"{"t":"paired","device_id":"d-AbCdEfGhIjKlMnOp"}"#) else {
        Issue.record("not paired")
        return
    }
    #expect(paired.deviceID == "d-AbCdEfGhIjKlMnOp")
}

@Test func realWelcomeCarriesTheUnlockAndTheLimits() throws {
    // remote_bridge.authenticate, in its key order; methods and elevated shortened here (BridgeAlignmentTests in the
    // Kit's tests holds the whole lists).
    let text =
        #"{"t":"welcome","v":1,"epoch":"e-Zk9qX3RyYWlu","seq":42,"resumed":true,"bridge":{"version":"1.9.29","name":"Sam’s MacBook Pro"},"pebble":{"running":true,"version":"1.9.29"},"methods":["state","get_chat","remote.lock","remote.folders"],"elevated":["approve","remote.unlock","setting:permissions","setting:stealth"],"unlock_seconds":900,"limits":{"max_request":131072,"max_frame":8388608}}"#
    guard case .welcome(let welcome) = try realFrame(text) else { Issue.record("not a welcome"); return }
    #expect(welcome.epoch == "e-Zk9qX3RyYWlu" && welcome.seq == 42 && welcome.resumed)
    #expect(welcome.bridge == WelcomeFrame.Bridge(version: "1.9.29", name: "Sam’s MacBook Pro"))
    #expect(welcome.pebble == WelcomeFrame.Pebble(running: true, version: "1.9.29"))
    #expect(welcome.unlockSeconds == 900)
    #expect(welcome.limits == WelcomeFrame.Limits.contract)
    #expect(welcome.methods.contains("remote.lock") && welcome.elevated.contains("setting:stealth"))
}

/// remote_bridge.BYE, word for word, and the X-1 refusal (PAIR_REFUSED) that also goes as `bad_code`.
private let realByes: [(code: String, words: String)] = [
    ("unknown_device", "This iPhone isn't paired with this Mac. Pair it again from Pebble's settings on the Mac."),
    ("revoked", "This iPhone was removed from Pebble on your Mac. Pair it again to keep using it."),
    ("bad_signature", "This iPhone's key didn't match. Pair it again from Pebble's settings on the Mac."),
    ("bad_version", "This Pebble Remote doesn't match Pebble on your Mac. Update both to the latest version."),
    ("replaced", "Pebble Remote connected again from this iPhone."),
    ("busy", "Your Mac is busy. Try again in a moment."),
    ("bad_code", "This pairing link has expired or was already used. Show a new one on your Mac."),
    ("bad_code", "Pairing wasn't confirmed on your Mac. Show a new pairing link there and try again."),
    (
        "too_large",
        "That message was too large to read, so Pebble closed the connection. Pebble Remote reconnects by itself."
    ),
]

@Test func everyRealByeDecodesWithItsWords() throws {
    for (code, words) in realByes {
        let text = #"{"t":"bye","code":""# + code + #"","error":""# + words + #""}"#
        guard case .bye(let bye) = try realFrame(text) else {
            Issue.record("not a bye: \(code)")
            continue
        }
        #expect(bye.code.rawValue == code && bye.error == words)
    }
    #expect(ByeCode(rawValue: "bad_code") == .badCode && ByeCode(rawValue: "replaced") == .replaced)
}

@Test func realRefusalsKeepTheirCodeAndWords() throws {
    let refusals: [(text: String, code: String?, words: String)] = [
        (
            #"{"t":"res","id":"r7","ok":false,"error":"Unlock Pebble Remote with Face ID before Pebble acts on what you ask.","code":"unlock_required"}"#,
            "unlock_required", "Unlock Pebble Remote with Face ID before Pebble acts on what you ask."
        ),
        (
            #"{"t":"res","id":"r8","ok":false,"error":"Confirm with Face ID to do this.","code":"proof_required"}"#,
            "proof_required", "Confirm with Face ID to do this."
        ),
        (
            #"{"t":"res","id":"r9","ok":false,"error":"That's a lot of requests at once. Try again in a moment.","code":"rate_limited"}"#,
            BridgeErrorCode.rateLimited.rawValue, "That's a lot of requests at once. Try again in a moment."
        ),
        // A phone removed while its call waited for a thread (F4), and a defect: words, and no code.
        (
            #"{"t":"res","id":"r10","ok":false,"error":"This iPhone was removed from Pebble on your Mac. Pair it again to keep using it."}"#,
            nil, "This iPhone was removed from Pebble on your Mac. Pair it again to keep using it."
        ),
        (
            #"{"t":"res","id":"r11","ok":false,"error":"Pebble couldn't do that because of an internal error. It is recorded in Pebble's log."}"#,
            nil, "Pebble couldn't do that because of an internal error. It is recorded in Pebble's log."
        ),
    ]
    for (text, code, words) in refusals {
        guard case .response(let response) = try realFrame(text) else {
            Issue.record("not a response")
            continue
        }
        #expect(response.outcome == .failure(error: words, code: code))
    }
    // F7: a retry whose first answer was too large to keep learns only that the call happened.
    guard case .response(let kept) = try realFrame(#"{"t":"res","id":"r12","ok":true,"result":null}"#) else {
        Issue.record("not a response")
        return
    }
    #expect(kept.outcome == .success(.null))
}

@Test func realBridgeEventsDecode() throws {
    // remote_bridge.devices_event: `data` is the remote.devices array, each phone's own copy marking it current.
    let devices = try realFrame(
        #"{"t":"evt","seq":43,"event":"remote.devices","ts":1761900000456,"data":[{"device_id":"d-AbCdEfGhIjKlMnOp","name":"iPhone 17","paired_at":1761800000000,"last_seen":1761900000000,"current":true}]}"#
    )
    guard case .event(let list) = devices else { Issue.record("not an event"); return }
    #expect(list.name == "remote.devices" && list.seq == 43)
    #expect(list.data.array?.first?["current"]?.bool == true)

    // remote.mac from `pmset`: a Mac without a battery reads as on power, with a null percentage.
    guard case .event(let mac) = try realFrame(
        #"{"t":"evt","seq":44,"event":"remote.mac","data":{"battery_percent":null,"charging":false,"on_power":true,"keep_awake":true},"ts":1761900000789}"#
    ) else { Issue.record("not an event"); return }
    #expect(mac.data["battery_percent"] == .null && mac.data["keep_awake"]?.bool == true)

    // `publish`: an event over 1 MB goes as its ids and `trimmed`.
    guard case .event(let trimmed) = try realFrame(
        #"{"t":"evt","seq":45,"event":"actions","data":{"chat_id":"c1","trimmed":true},"ts":1761900001000}"#
    ) else { Issue.record("not an event"); return }
    #expect(trimmed.data["trimmed"]?.bool == true && trimmed.data["actions"] == nil)
    #expect(trimmed.time == Date(timeIntervalSince1970: 1_761_900_001))

    // Merged tokens (30 ms) keep the first event's fields and the joined text; data straight from Pebble may be null.
    guard case .event(let token) = try realFrame(
        #"{"t":"evt","seq":46,"event":"token","data":{"chat_id":"c1","id":"m7","text":"Hello, wor"},"ts":1761900001100}"#
    ) else { Issue.record("not an event"); return }
    #expect(token.data["text"]?.string == "Hello, wor")
    guard case .event(let empty) = try realFrame(#"{"t":"evt","seq":47,"event":"ready","data":null,"ts":1761900001200}"#)
    else { Issue.record("not an event"); return }
    #expect(empty.data == .object([:]))
}
