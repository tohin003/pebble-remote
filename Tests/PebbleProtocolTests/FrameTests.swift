import Foundation
import Testing

@testable import PebbleProtocol

// Every example below is pasted verbatim from the bridge contract (sections 3.2 to 3.6).
// Only the placeholders that are not JSON (`<unix ms>`, `<n>`, `{...}`, `<Pebble's result>`) are filled in by `fill`.

private let contractFills: [(String, String)] = [
    ("<unix ms on the Mac>", "1761759000123"),
    ("<unix ms>", "1761759000456"),
    ("<last seq>", "1200"),
    ("<n>", "1187"),
    ("<Pebble's result>", #"{"chats":[],"version":"1.9.28"}"#),
    (#""params":{...}"#, #""params":{"id":"c1","text":"Run the tests"}"#),
    (#""data":{...}"#, #""data":{"chat_id":"c1","id":"m7","text":"Hel"}"#),
]

private func fill(_ text: String) -> String {
    contractFills.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
}

/// Decodes the text, re-encodes the frame, and checks that the JSON is the same value as the input.
@discardableResult
private func roundTrip(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Frame {
    let frame = try FrameCodec.decode(text)
    let again = try FrameCodec.decode(try FrameCodec.encode(frame))
    #expect(again == frame, sourceLocation: sourceLocation)
    let input = try FrameCodec.jsonValue(text)
    let output = try FrameCodec.jsonValue(try FrameCodec.encodeText(frame))
    #expect(output == input, sourceLocation: sourceLocation)
    return frame
}

// MARK: - Handshake

@Test func challengeFromTheContract() throws {
    let text = fill(#"{"t":"challenge","v":1,"bid":"<bridge id>","nonce":"<b64url 32 bytes>","time":<unix ms>}"#)
    guard case .challenge(let challenge) = try roundTrip(text) else { Issue.record("not a challenge"); return }
    #expect(challenge.version == 1)
    #expect(challenge.bridgeID == "<bridge id>")
    #expect(challenge.nonce == "<b64url 32 bytes>")
    #expect(challenge.time == 1_761_759_000_456)
}

@Test func helloFromTheContractWithAndWithoutResume() throws {
    let contract =
        #"{"t":"hello","v":1,"device_id":"<id>","sig":"<b64url DER over T_hello>","resume":{"epoch":"<e>","seq":<n>}|null,"app":"1.0 (1)"}"#
    let resuming = fill(contract.replacingOccurrences(of: "|null", with: ""))
    let fresh = contract.replacingOccurrences(of: #"{"epoch":"<e>","seq":<n>}|null"#, with: "null")

    guard case .hello(let hello) = try roundTrip(resuming) else { Issue.record("not a hello"); return }
    #expect(hello.deviceID == "<id>")
    #expect(hello.signature == "<b64url DER over T_hello>")
    #expect(hello.resume == HelloFrame.Resume(epoch: "<e>", seq: 1187))
    #expect(hello.app == "1.0 (1)")

    guard case .hello(let first) = try roundTrip(fresh) else { Issue.record("not a hello"); return }
    #expect(first.resume == nil)
    // A hello with nothing to resume still says so: "resume":null, as the contract writes it.
    #expect(try FrameCodec.encodeText(.hello(first)).contains(#""resume":null"#))
}

@Test func welcomeFromTheContract() throws {
    let text = fill(
        """
        {"t":"welcome","v":1,"epoch":"<e>","seq":<last seq>,"resumed":true,
         "bridge":{"version":"<x>","name":"<Mac name>"},"pebble":{"running":true,"version":"1.9.28"},
         "methods":["state","get_chat", "..."],"elevated":["approve","..."],
         "limits":{"max_request":131072,"max_frame":8388608}}
        """)
    guard case .welcome(let welcome) = try roundTrip(text) else { Issue.record("not a welcome"); return }
    #expect(welcome.epoch == "<e>")
    #expect(welcome.seq == 1200)
    #expect(welcome.resumed)
    #expect(welcome.bridge == WelcomeFrame.Bridge(version: "<x>", name: "<Mac name>"))
    #expect(welcome.pebble == WelcomeFrame.Pebble(running: true, version: "1.9.28"))
    #expect(welcome.methods == ["state", "get_chat", "..."])
    #expect(welcome.elevated == ["approve", "..."])
    #expect(welcome.limits == WelcomeFrame.Limits.contract)
}

@Test func welcomeToleratesMissingAndExtraFields() throws {
    let frame = try FrameCodec.decode(
        #"{"t":"welcome","epoch":"e2","pebble":{"running":false,"version":null},"future":{"x":1},"methods":["state"]}"#)
    guard case .welcome(let welcome) = frame else { Issue.record("not a welcome"); return }
    #expect(welcome.version == 1)
    #expect(welcome.seq == 0)
    #expect(welcome.resumed == false)
    #expect(welcome.pebble == WelcomeFrame.Pebble(running: false, version: nil))
    #expect(welcome.bridge == nil)
    #expect(welcome.elevated.isEmpty)
    #expect(welcome.limits == nil)
}

@Test func byeFromTheContractAndEachCode() throws {
    let text =
        #"{"t":"bye","code":"unknown_device|revoked|bad_signature|bad_version|replaced|busy","error":"<words for the person>"}"#
    guard case .bye(let bye) = try roundTrip(text) else { Issue.record("not a bye"); return }
    #expect(bye.error == "<words for the person>")

    let codes: [(String, ByeCode)] = [
        ("unknown_device", .unknownDevice), ("revoked", .revoked), ("bad_signature", .badSignature),
        ("bad_version", .badVersion), ("replaced", .replaced), ("busy", .busy),
    ]
    for (wire, code) in codes {
        let frame = try roundTrip(#"{"t":"bye","code":"\#(wire)","error":"Pebble Remote was removed on the Mac."}"#)
        #expect(frame == .bye(ByeFrame(code: code, error: "Pebble Remote was removed on the Mac.")))
    }
}

// MARK: - Pairing

@Test func pairFromTheContract() throws {
    let text = """
        {"t":"pair","v":1,"code":"<code>",
         "device":{"name":"iPhone 17","model":"iPhone18,3","os":"iOS 26.1","app":"1.0 (1)"},
         "device_key":"<b64url X9.63 uncompressed, 65 bytes>","approve_key":"<b64url X9.63>",
         "sig":"<b64url DER ECDSA by device key over T_pair>","approve_sig":"<b64url DER ECDSA by approve key over T_pair>"}
        """
    guard case .pair(let pair) = try roundTrip(text) else { Issue.record("not a pair"); return }
    #expect(pair.code == "<code>")
    #expect(pair.device == PairFrame.Device(name: "iPhone 17", model: "iPhone18,3", os: "iOS 26.1", app: "1.0 (1)"))
    #expect(pair.deviceKey == "<b64url X9.63 uncompressed, 65 bytes>")
    #expect(pair.approveKey == "<b64url X9.63>")
    #expect(pair.signature == "<b64url DER ECDSA by device key over T_pair>")
    #expect(pair.approveSignature == "<b64url DER ECDSA by approve key over T_pair>")
}

@Test func pairedFromTheContract() throws {
    #expect(try roundTrip(#"{"t":"paired","device_id":"<id>"}"#) == .paired(PairedFrame(deviceID: "<id>")))
}

// MARK: - Requests and responses

@Test func requestFromTheContract() throws {
    let text = fill(
        #"{"t":"req","id":"<unique per connection, at most 64 chars>","method":"<name>","params":{...},"idem":"<uuid>"}"#)
    guard case .request(let request) = try roundTrip(text) else { Issue.record("not a request"); return }
    #expect(request.id == "<unique per connection, at most 64 chars>")
    #expect(request.method == "<name>")
    #expect(request.params == ["id": "c1", "text": "Run the tests"])
    #expect(request.idem == "<uuid>")
    #expect(!request.isElevated)
}

@Test func elevatedRequestFromTheContract() throws {
    let text = fill(
        """
        {"t":"req","id":"r42","method":"approve","params_json":"{\\"id\\":\\"c1\\",\\"action_id\\":\\"a9\\"}","idem":"<uuid>",
         "proof":{"ts":<unix ms>,"sig":"<b64url DER ECDSA by approve key over T_proof>"}}
        """)
    guard case .request(let request) = try roundTrip(text) else { Issue.record("not a request"); return }
    #expect(request.isElevated)
    #expect(request.params == nil)
    // The exact characters the proof signed, escapes undone once.
    #expect(request.paramsJSON == #"{"id":"c1","action_id":"a9"}"#)
    #expect(request.proof == RequestFrame.Proof(ts: 1_761_759_000_456, sig: "<b64url DER ECDSA by approve key over T_proof>"))
    #expect(request.idem == "<uuid>")
}

@Test func elevatedParamsTextSurvivesTheWireByteForByte() throws {
    let params: JSONValue = ["id": "c1", "action_id": "a9", "note": "Ünïcode ✓ \"quoted\" /path/to\\file"]
    let paramsJSON = try FrameCodec.jsonText(params)
    #expect(paramsJSON.hasPrefix(#"{"action_id":"a9","id":"c1","note":"#))  // compact, keys sorted
    let sent = RequestFrame(id: "r1", method: "approve", paramsJSON: paramsJSON, proof: .init(ts: 1, sig: "s"), idem: "u")
    let received = try FrameCodec.decode(try FrameCodec.encode(.request(sent)))
    guard case .request(let request) = received else { Issue.record("not a request"); return }
    #expect(Array(try #require(request.paramsJSON).utf8) == Array(paramsJSON.utf8))
    #expect(try FrameCodec.jsonValue(paramsJSON) == params)
}

@Test func requestWithoutParamsOrIdem() throws {
    let request = RequestFrame(id: "r7", method: "state")
    let text = try FrameCodec.encodeText(.request(request))
    #expect(text == #"{"id":"r7","method":"state","params":{},"t":"req"}"#)
    #expect(try FrameCodec.decode(#"{"t":"req","id":"r7","method":"state"}"#) == .request(request))
}

@Test func responsesFromTheContract() throws {
    let success = fill(#"{"t":"res","id":"<same>","ok":true,"result":<Pebble's result>}"#)
    guard case .response(let ok) = try roundTrip(success) else { Issue.record("not a response"); return }
    #expect(ok.id == "<same>")
    #expect(ok.ok)
    #expect(ok.result?["version"] == "1.9.28")

    let refusal = #"{"t":"res","id":"<same>","ok":false,"error":"<message for the person>","code":"<content-free code>"}"#
    guard case .response(let refused) = try roundTrip(refusal) else { Issue.record("not a response"); return }
    #expect(refused.outcome == .failure(error: "<message for the person>", code: "<content-free code>"))
    #expect(refused.result == nil)
}

@Test func responsesToleratePartialFields() throws {
    #expect(try FrameCodec.decode(#"{"t":"res","id":"r1","ok":true}"#) == .response(.init(id: "r1", outcome: .success(.null))))
    #expect(
        try FrameCodec.decode(#"{"t":"res","id":"r2","error":"Pebble is not running.","code":"pebble_offline"}"#)
            == .response(.init(id: "r2", outcome: .failure(error: "Pebble is not running.", code: "pebble_offline"))))
    #expect(try FrameCodec.decode(#"{"t":"res","id":"r3","ok":false}"#) == .response(.init(id: "r3", outcome: .failure(error: "", code: nil))))
    #expect(BridgeErrorCode.proofRequired.rawValue == "proof_required")
}

// MARK: - Events

@Test func eventFromTheContract() throws {
    let text = fill(#"{"t":"evt","seq":<n>,"event":"<name>","data":{...},"ts":<unix ms on the Mac>}"#)
    guard case .event(let event) = try roundTrip(text) else { Issue.record("not an event"); return }
    #expect(event.seq == 1187)
    #expect(event.name == "<name>")
    #expect(event.chatID == "c1")
    #expect(event.data["text"] == "Hel")
    #expect(event.time == Date(timeIntervalSince1970: 1_761_759_000.123))
}

@Test func eventsToleratePartialAndFractionalFields() throws {
    let frame = try FrameCodec.decode(#"{"t":"evt","seq":3,"event":"idle","ts":1761759000123.7,"extra":true}"#)
    guard case .event(let event) = frame else { Issue.record("not an event"); return }
    #expect(event.data == .object([:]))
    #expect(event.time.map { ($0.timeIntervalSince1970 * 1000).rounded() } == 1_761_759_000_124)
    let bridgeEvent = try FrameCodec.decode(
        #"{"t":"evt","seq":4,"event":"remote.mac","data":{"battery_percent":81,"charging":true,"on_power":true,"keep_awake":true}}"#)
    guard case .event(let mac) = bridgeEvent else { Issue.record("not an event"); return }
    #expect(mac.time == nil)
    #expect(mac.data["battery_percent"]?.int == 81)
}

// MARK: - Unknown and broken frames

@Test func unknownFrameTypesAreKeptNotErrors() throws {
    let text = #"{"t":"telemetry","v":2,"what":{"a":[1,2.5,null]}}"#
    let frame = try roundTrip(text)
    #expect(frame.type == "telemetry")
    guard case .unknown(let type, let raw) = frame else { Issue.record("not unknown"); return }
    #expect(type == "telemetry")
    #expect(raw["what"]?["a"] == [1, 2.5, .null])
}

@Test func brokenFramesThrowContentFreeErrors() {
    #expect(throws: FrameDecodingError.self) { try FrameCodec.decode("not json") }
    #expect(throws: FrameDecodingError.self) { try FrameCodec.decode(#"{"no_type":1}"#) }
    #expect(throws: FrameDecodingError.self) { try FrameCodec.decode(#"[1,2]"#) }
    #expect(throws: FrameDecodingError.self) { try FrameCodec.decode(#"{"t":"res","ok":true}"#) }
    do {
        _ = try FrameCodec.decode(#"{"t":"evt","event":"token","data":{"text":"secret words"}}"#)
        Issue.record("decoded an event without seq")
    } catch let error as FrameDecodingError {
        #expect(error.reason == "missing seq")
        #expect(!error.description.contains("secret"))
    } catch {
        Issue.record("unexpected error \(error)")
    }
}

@Test func frameTypesMatchTheWire() {
    #expect(Frame.challenge(.init(bridgeID: "b", nonce: "n")).type == "challenge")
    #expect(Frame.request(.init(id: "1", method: "state")).type == "req")
    #expect(Frame.response(.init(id: "1", outcome: .success(.null))).type == "res")
    #expect(Frame.event(.init(seq: 1, name: "idle", data: [:])).type == "evt")
    #expect(RemoteContract.idempotentMethods.contains("run_steer"))
    #expect(!RemoteContract.idempotentMethods.contains("state"))
}
