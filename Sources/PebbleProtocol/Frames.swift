import Foundation

// The bridge's wire frames. Contract: the bridge contract, sections 3.2 to 3.6.
//
// One JSON object per WebSocket text frame, told apart by "t". Field names on the wire are the contract's (snake_case);
// the Swift names say what each field is. Decoding is tolerant: unknown fields are ignored, optional fields may be
// missing, timestamps may arrive as whole or fractional milliseconds, and a frame whose "t" this version does not know
// decodes to `Frame.unknown` (a newer bridge may add frames). Encode and decode with `FrameCodec`.

/// One message on the bridge's WebSocket, in either direction.
public enum Frame: Sendable, Hashable {
    /// Bridge to phone, right after the socket opens (3.3, step 1).
    case challenge(ChallengeFrame)
    /// Phone to bridge: the signed answer to the challenge (3.3, step 2).
    case hello(HelloFrame)
    /// Bridge to phone: the connection is accepted (3.3, step 3).
    case welcome(WelcomeFrame)
    /// Bridge to phone: refused or replaced; the bridge closes the socket after it (3.3, step 4).
    case bye(ByeFrame)
    /// Phone to bridge: pairing with a one-time code, instead of `hello` (3.2).
    case pair(PairFrame)
    /// Bridge to phone: pairing accepted; a `welcome` follows (3.2).
    case paired(PairedFrame)
    /// Phone to bridge: a method call, normal or elevated (wire "req", 3.4 and 3.6).
    case request(RequestFrame)
    /// Bridge to phone: the answer to one request (wire "res", 3.4).
    case response(ResponseFrame)
    /// Bridge to phone: one of Pebble's events or the bridge's own (wire "evt", 3.5).
    case event(PebbleEvent)
    /// A frame type this version does not know, kept whole ("t" included in `raw`).
    case unknown(type: String, raw: JSONValue)

    /// The wire discriminator, "t".
    public var type: String {
        switch self {
        case .challenge: ChallengeFrame.wireType
        case .hello: HelloFrame.wireType
        case .welcome: WelcomeFrame.wireType
        case .bye: ByeFrame.wireType
        case .pair: PairFrame.wireType
        case .paired: PairedFrame.wireType
        case .request: RequestFrame.wireType
        case .response: ResponseFrame.wireType
        case .event: PebbleEvent.wireType
        case .unknown(let type, _): type
        }
    }
}

// MARK: - Handshake (3.3)

/// `{"t":"challenge","v":1,"bid":"<bridge id>","nonce":"<b64url 32 bytes>","time":<unix ms>}`
public struct ChallengeFrame: Sendable, Hashable, Codable {
    public static let wireType = "challenge"
    /// "v": the contract version (1).
    public var version: Int
    /// "bid"
    public var bridgeID: String
    /// base64url of 32 random bytes; signed into T_hello and T_pair.
    public var nonce: String
    /// The Mac's clock when it sent the challenge, unix milliseconds.
    public var time: Int64?

    public init(version: Int = RemoteContract.version, bridgeID: String, nonce: String, time: Int64? = nil) {
        self.version = version
        self.bridgeID = bridgeID
        self.nonce = nonce
        self.time = time
    }

    enum CodingKeys: String, CodingKey { case t, v, bid, nonce, time }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .v) ?? RemoteContract.version
        bridgeID = try c.decode(String.self, forKey: .bid)
        nonce = try c.decode(String.self, forKey: .nonce)
        time = try c.decodeMillisIfPresent(forKey: .time)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.wireType, forKey: .t)
        try c.encode(version, forKey: .v)
        try c.encode(bridgeID, forKey: .bid)
        try c.encode(nonce, forKey: .nonce)
        try c.encodeIfPresent(time, forKey: .time)
    }
}

/// `{"t":"hello","v":1,"device_id":"<id>","sig":"<b64url DER over T_hello>","resume":{"epoch":"<e>","seq":<n>}|null,
/// "app":"1.0 (1)"}`. `resume` is always written, as `null` when there is nothing to resume.
public struct HelloFrame: Sendable, Hashable, Codable {
    public static let wireType = "hello"

    /// Where the phone left off: the bridge replays every buffered event above `seq` in this `epoch`.
    public struct Resume: Sendable, Hashable, Codable {
        public var epoch: String
        public var seq: Int
        public init(epoch: String, seq: Int) {
            self.epoch = epoch
            self.seq = seq
        }
    }

    /// "v"
    public var version: Int
    /// "device_id"
    public var deviceID: String
    /// "sig": base64url DER ECDSA by the device key over T_hello.
    public var signature: String
    public var resume: Resume?
    /// The app's version, "1.0 (1)".
    public var app: String?

    public init(
        version: Int = RemoteContract.version, deviceID: String, signature: String, resume: Resume? = nil,
        app: String? = nil
    ) {
        self.version = version
        self.deviceID = deviceID
        self.signature = signature
        self.resume = resume
        self.app = app
    }

    enum CodingKeys: String, CodingKey { case t, v, device_id, sig, resume, app }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .v) ?? RemoteContract.version
        deviceID = try c.decode(String.self, forKey: .device_id)
        signature = try c.decode(String.self, forKey: .sig)
        resume = try c.decodeIfPresent(Resume.self, forKey: .resume)
        app = try c.decodeIfPresent(String.self, forKey: .app)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.wireType, forKey: .t)
        try c.encode(version, forKey: .v)
        try c.encode(deviceID, forKey: .device_id)
        try c.encode(signature, forKey: .sig)
        if let resume { try c.encode(resume, forKey: .resume) } else { try c.encodeNil(forKey: .resume) }
        try c.encodeIfPresent(app, forKey: .app)
    }
}

/// `{"t":"welcome","v":1,"epoch":"<e>","seq":<last seq>,"resumed":true,"bridge":{"version":"<x>","name":"<Mac name>"},
/// "pebble":{"running":true,"version":"1.9.28"},"methods":[...],"elevated":[...],
/// "limits":{"max_request":131072,"max_frame":8388608}}`
public struct WelcomeFrame: Sendable, Hashable, Codable {
    public static let wireType = "welcome"

    public struct Bridge: Sendable, Hashable, Codable {
        public var version: String
        /// The Mac's name.
        public var name: String
        public init(version: String, name: String) {
            self.version = version
            self.name = name
        }
        enum CodingKeys: String, CodingKey { case version, name }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        }
    }

    public struct Pebble: Sendable, Hashable, Codable {
        public var running: Bool
        /// nil while Pebble is not running.
        public var version: String?
        public init(running: Bool, version: String?) {
            self.running = running
            self.version = version
        }
        enum CodingKeys: String, CodingKey { case running, version }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            running = try c.decodeIfPresent(Bool.self, forKey: .running) ?? false
            version = try c.decodeIfPresent(String.self, forKey: .version)
        }
    }

    public struct Limits: Sendable, Hashable, Codable {
        /// "max_request": the largest request frame the bridge accepts, in bytes.
        public var maxRequest: Int
        /// "max_frame": the largest frame the bridge sends, in bytes.
        public var maxFrame: Int
        public init(maxRequest: Int, maxFrame: Int) {
            self.maxRequest = maxRequest
            self.maxFrame = maxFrame
        }
        /// Section 3.9's numbers, for a welcome that leaves them out.
        public static let contract = Limits(maxRequest: 131_072, maxFrame: 8_388_608)
        enum CodingKeys: String, CodingKey { case max_request, max_frame }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            maxRequest = try c.decodeIfPresent(Int.self, forKey: .max_request) ?? Self.contract.maxRequest
            maxFrame = try c.decodeIfPresent(Int.self, forKey: .max_frame) ?? Self.contract.maxFrame
        }
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(maxRequest, forKey: .max_request)
            try c.encode(maxFrame, forKey: .max_frame)
        }
    }

    /// "v"
    public var version: Int
    /// Changes when the bridge restarts; `seq` counts within it.
    public var epoch: String
    /// The last event seq the bridge has sent in this epoch.
    public var seq: Int
    /// True: the bridge replays every event after `hello.resume.seq` before any live one. False: refetch everything.
    public var resumed: Bool
    public var bridge: Bridge?
    public var pebble: Pebble?
    /// Methods the phone may call.
    public var methods: [String]
    /// Methods that need a Face ID proof (3.6).
    public var elevated: [String]
    public var limits: Limits?
    /// "unlock_seconds" (contract C1): how long a Face ID unlock lets this phone act; nil from a bridge before v0.3.
    public var unlockSeconds: Int?

    public init(
        version: Int = RemoteContract.version, epoch: String, seq: Int, resumed: Bool, bridge: Bridge?,
        pebble: Pebble?, methods: [String], elevated: [String], limits: Limits? = nil, unlockSeconds: Int? = nil
    ) {
        self.unlockSeconds = unlockSeconds
        self.version = version
        self.epoch = epoch
        self.seq = seq
        self.resumed = resumed
        self.bridge = bridge
        self.pebble = pebble
        self.methods = methods
        self.elevated = elevated
        self.limits = limits
    }

    enum CodingKeys: String, CodingKey { case t, v, epoch, seq, resumed, bridge, pebble, methods, elevated, limits, unlock_seconds }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .v) ?? RemoteContract.version
        epoch = try c.decode(String.self, forKey: .epoch)
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        resumed = try c.decodeIfPresent(Bool.self, forKey: .resumed) ?? false
        bridge = try c.decodeIfPresent(Bridge.self, forKey: .bridge)
        pebble = try c.decodeIfPresent(Pebble.self, forKey: .pebble)
        methods = try c.decodeIfPresent([String].self, forKey: .methods) ?? []
        elevated = try c.decodeIfPresent([String].self, forKey: .elevated) ?? []
        limits = try c.decodeIfPresent(Limits.self, forKey: .limits)
        unlockSeconds = try c.decodeIfPresent(Int.self, forKey: .unlock_seconds)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.wireType, forKey: .t)
        try c.encode(version, forKey: .v)
        try c.encode(epoch, forKey: .epoch)
        try c.encode(seq, forKey: .seq)
        try c.encode(resumed, forKey: .resumed)
        try c.encodeIfPresent(bridge, forKey: .bridge)
        try c.encodeIfPresent(pebble, forKey: .pebble)
        try c.encode(methods, forKey: .methods)
        try c.encode(elevated, forKey: .elevated)
        try c.encodeIfPresent(limits, forKey: .limits)
        try c.encodeIfPresent(unlockSeconds, forKey: .unlock_seconds)
    }
}

/// `{"t":"bye","code":"unknown_device|revoked|bad_signature|bad_version|replaced|busy","error":"<words for the person>"}`
public struct ByeFrame: Sendable, Hashable, Codable {
    public static let wireType = "bye"
    public var code: ByeCode
    /// A sentence for the person, in Pebble's voice.
    public var error: String?

    public init(code: ByeCode, error: String? = nil) {
        self.code = code
        self.error = error
    }

    enum CodingKeys: String, CodingKey { case t, code, error }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = ByeCode(rawValue: try c.decodeIfPresent(String.self, forKey: .code) ?? "")
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.wireType, forKey: .t)
        try c.encode(code.rawValue, forKey: .code)
        try c.encodeIfPresent(error, forKey: .error)
    }
}

/// Why the bridge said `bye`. Tolerant: any string is kept.
public struct ByeCode: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    /// The bridge does not know this phone: pair again.
    public static let unknownDevice = ByeCode(rawValue: "unknown_device")
    /// The person removed this phone on the Mac.
    public static let revoked = ByeCode(rawValue: "revoked")
    public static let badSignature = ByeCode(rawValue: "bad_signature")
    /// The bridge does not speak this contract version.
    public static let badVersion = ByeCode(rawValue: "bad_version")
    /// A newer connection from this phone took over; do not reconnect from this one.
    public static let replaced = ByeCode(rawValue: "replaced")
    public static let busy = ByeCode(rawValue: "busy")
    /// A pairing code that is wrong, used, expired or out of tries (proposed for contract v0.2; lane C's mock sends
    /// it): show a new link. Any other unknown code: show the bye's own words.
    public static let badCode = ByeCode(rawValue: "bad_code")
}

// MARK: - Pairing (3.2)

/// `{"t":"pair","v":1,"code":"<code>","device":{"name":..,"model":..,"os":..,"app":..},"device_key":"<b64url X9.63>",
/// "approve_key":"<b64url X9.63>","sig":"<b64url DER over T_pair>","approve_sig":"<b64url DER over T_pair>"}`
public struct PairFrame: Sendable, Hashable, Codable {
    public static let wireType = "pair"

    /// What the Mac shows in its list of paired phones.
    public struct Device: Sendable, Hashable, Codable {
        /// "iPhone 17"
        public var name: String
        /// "iPhone18,3"
        public var model: String
        /// "iOS 26.1"
        public var os: String
        /// "1.0 (1)"
        public var app: String
        public init(name: String, model: String, os: String, app: String) {
            self.name = name
            self.model = model
            self.os = os
            self.app = app
        }
        enum CodingKeys: String, CodingKey { case name, model, os, app }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
            os = try c.decodeIfPresent(String.self, forKey: .os) ?? ""
            app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
        }
    }

    /// "v"
    public var version: Int
    /// The pairing link's one-time code.
    public var code: String
    public var device: Device
    /// "device_key": base64url X9.63 uncompressed P-256 public key (65 bytes); it signs connection challenges.
    public var deviceKey: String
    /// "approve_key": base64url X9.63; needs Face ID; it signs elevated calls.
    public var approveKey: String
    /// "sig": by the device key over T_pair.
    public var signature: String
    /// "approve_sig": by the approve key over T_pair.
    public var approveSignature: String

    public init(
        version: Int = RemoteContract.version, code: String, device: Device, deviceKey: String, approveKey: String,
        signature: String, approveSignature: String
    ) {
        self.version = version
        self.code = code
        self.device = device
        self.deviceKey = deviceKey
        self.approveKey = approveKey
        self.signature = signature
        self.approveSignature = approveSignature
    }

    enum CodingKeys: String, CodingKey { case t, v, code, device, device_key, approve_key, sig, approve_sig }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .v) ?? RemoteContract.version
        code = try c.decode(String.self, forKey: .code)
        device = try c.decode(Device.self, forKey: .device)
        deviceKey = try c.decode(String.self, forKey: .device_key)
        approveKey = try c.decode(String.self, forKey: .approve_key)
        signature = try c.decode(String.self, forKey: .sig)
        approveSignature = try c.decode(String.self, forKey: .approve_sig)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.wireType, forKey: .t)
        try c.encode(version, forKey: .v)
        try c.encode(code, forKey: .code)
        try c.encode(device, forKey: .device)
        try c.encode(deviceKey, forKey: .device_key)
        try c.encode(approveKey, forKey: .approve_key)
        try c.encode(signature, forKey: .sig)
        try c.encode(approveSignature, forKey: .approve_sig)
    }
}

/// `{"t":"paired","device_id":"<id>"}`
public struct PairedFrame: Sendable, Hashable, Codable {
    public static let wireType = "paired"
    /// "device_id": the id the phone sends in every later `hello`.
    public var deviceID: String

    public init(deviceID: String) { self.deviceID = deviceID }

    enum CodingKeys: String, CodingKey { case t, device_id }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try c.decode(String.self, forKey: .device_id)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.wireType, forKey: .t)
        try c.encode(deviceID, forKey: .device_id)
    }
}

// MARK: - Requests and responses (3.4, 3.6)

/// Normal: `{"t":"req","id":"<id>","method":"<name>","params":{...},"idem":"<uuid>"}`.
/// Elevated: `{"t":"req","id":"r42","method":"approve","params_json":"{...}","idem":"<uuid>",
/// "proof":{"ts":<unix ms>,"sig":"<b64url DER by the approve key over T_proof>"}}`.
public struct RequestFrame: Sendable, Hashable, Codable {
    public static let wireType = "req"

    public enum Body: Sendable, Hashable {
        /// The normal form: `params` as JSON.
        case params(JSONValue)
        /// The elevated form: the params as the exact JSON text the proof covers, so nobody canonicalizes JSON.
        /// The proof is nil only when decoding a frame that left it out (the bridge answers `proof_required`).
        case elevated(paramsJSON: String, proof: Proof?)
    }

    /// "proof": `ts` is the phone's clock in unix milliseconds; `sig` is base64url DER over T_proof.
    public struct Proof: Sendable, Hashable, Codable {
        public var ts: Int64
        public var sig: String
        public init(ts: Int64, sig: String) {
            self.ts = ts
            self.sig = sig
        }
        enum CodingKeys: String, CodingKey { case ts, sig }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ts = try c.decodeMillis(forKey: .ts)
            sig = try c.decode(String.self, forKey: .sig)
        }
    }

    /// Unique per connection, at most 64 characters.
    public var id: String
    public var method: String
    public var body: Body
    /// The idempotency key (3.4); the same key on a retry makes the bridge return its first answer.
    public var idem: String?

    public init(id: String, method: String, body: Body, idem: String? = nil) {
        self.id = id
        self.method = method
        self.body = body
        self.idem = idem
    }

    /// A normal call.
    public init(id: String, method: String, params: JSONValue = .object([:]), idem: String? = nil) {
        self.init(id: id, method: method, body: .params(params), idem: idem)
    }

    /// An elevated call (3.6). `paramsJSON` must be the exact text the proof's hash was computed over.
    public init(id: String, method: String, paramsJSON: String, proof: Proof, idem: String? = nil) {
        self.init(id: id, method: method, body: .elevated(paramsJSON: paramsJSON, proof: proof), idem: idem)
    }

    /// The normal form's params, or nil for an elevated call.
    public var params: JSONValue? {
        if case .params(let params) = body { params } else { nil }
    }
    /// The elevated form's params text, or nil for a normal call.
    public var paramsJSON: String? {
        if case .elevated(let text, _) = body { text } else { nil }
    }
    public var proof: Proof? {
        if case .elevated(_, let proof) = body { proof } else { nil }
    }
    public var isElevated: Bool { paramsJSON != nil }

    enum CodingKeys: String, CodingKey { case t, id, method, params, params_json, proof, idem }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        method = try c.decode(String.self, forKey: .method)
        idem = try c.decodeIfPresent(String.self, forKey: .idem)
        if let text = try c.decodeIfPresent(String.self, forKey: .params_json) {
            body = .elevated(paramsJSON: text, proof: try c.decodeIfPresent(Proof.self, forKey: .proof))
        } else {
            body = .params(try c.decodeIfPresent(JSONValue.self, forKey: .params) ?? .object([:]))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.wireType, forKey: .t)
        try c.encode(id, forKey: .id)
        try c.encode(method, forKey: .method)
        switch body {
        case .params(let params):
            try c.encode(params, forKey: .params)
        case .elevated(let text, let proof):
            try c.encode(text, forKey: .params_json)
            try c.encodeIfPresent(proof, forKey: .proof)
        }
        try c.encodeIfPresent(idem, forKey: .idem)
    }
}

/// Success: `{"t":"res","id":"<same>","ok":true,"result":<Pebble's result>}`.
/// Refusal: `{"t":"res","id":"<same>","ok":false,"error":"<message for the person>","code":"<content-free code>"}`.
public struct ResponseFrame: Sendable, Hashable, Codable {
    public static let wireType = "res"

    public enum Outcome: Sendable, Hashable {
        case success(JSONValue)
        /// `error` is a sentence for the person; `code` is Pebble's own code passed through (`trashed_conversation`)
        /// or the bridge's (`BridgeErrorCode`).
        case failure(error: String, code: String?)
    }

    /// The request's id.
    public var id: String
    public var outcome: Outcome

    public init(id: String, outcome: Outcome) {
        self.id = id
        self.outcome = outcome
    }

    public var ok: Bool {
        if case .success = outcome { true } else { false }
    }
    /// The result of a successful call, or nil for a refusal.
    public var result: JSONValue? {
        if case .success(let value) = outcome { value } else { nil }
    }

    enum CodingKeys: String, CodingKey { case t, id, ok, result, error, code }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let error = try c.decodeIfPresent(String.self, forKey: .error)
        let ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? (error == nil)
        if ok {
            outcome = .success(try c.decodeIfPresent(JSONValue.self, forKey: .result) ?? .null)
        } else {
            outcome = .failure(error: error ?? "", code: try c.decodeIfPresent(String.self, forKey: .code))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.wireType, forKey: .t)
        try c.encode(id, forKey: .id)
        switch outcome {
        case .success(let result):
            try c.encode(true, forKey: .ok)
            try c.encode(result, forKey: .result)
        case .failure(let error, let code):
            try c.encode(false, forKey: .ok)
            try c.encode(error, forKey: .error)
            try c.encodeIfPresent(code, forKey: .code)
        }
    }
}

/// The bridge's own refusal codes (3.4). Pebble's codes pass through unchanged next to these.
public struct BridgeErrorCode: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let notAllowed = BridgeErrorCode(rawValue: "not_allowed")
    public static let proofRequired = BridgeErrorCode(rawValue: "proof_required")
    public static let badProof = BridgeErrorCode(rawValue: "bad_proof")
    public static let tooLarge = BridgeErrorCode(rawValue: "too_large")
    public static let rateLimited = BridgeErrorCode(rawValue: "rate_limited")
    public static let pebbleOffline = BridgeErrorCode(rawValue: "pebble_offline")
    public static let timeout = BridgeErrorCode(rawValue: "timeout")
    public static let badRequest = BridgeErrorCode(rawValue: "bad_request")
}

// MARK: - Events (3.5)

extension PebbleEvent {
    /// `{"t":"evt","seq":<n>,"event":"<name>","data":{...},"ts":<unix ms on the Mac>}`
    public static let wireType = "evt"

    enum FrameKeys: String, CodingKey { case t, seq, event, data, ts }

    init(frameFrom decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: FrameKeys.self)
        let millis = try c.decodeMillisIfPresent(forKey: .ts)
        self.init(
            seq: try c.decode(Int.self, forKey: .seq),
            name: try c.decode(String.self, forKey: .event),
            data: try c.decodeIfPresent(JSONValue.self, forKey: .data) ?? .object([:]),
            time: millis.map { Date(timeIntervalSince1970: Double($0) / 1000) })
    }

    func encodeFrame(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: FrameKeys.self)
        try c.encode(Self.wireType, forKey: .t)
        try c.encode(seq, forKey: .seq)
        try c.encode(name, forKey: .event)
        try c.encode(data, forKey: .data)
        if let time { try c.encode(Int64((time.timeIntervalSince1970 * 1000).rounded()), forKey: .ts) }
    }
}

// MARK: - The codec

extension Frame: Codable {
    private enum TypeKey: String, CodingKey { case t }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .t)
        switch type {
        case ChallengeFrame.wireType: self = .challenge(try ChallengeFrame(from: decoder))
        case HelloFrame.wireType: self = .hello(try HelloFrame(from: decoder))
        case WelcomeFrame.wireType: self = .welcome(try WelcomeFrame(from: decoder))
        case ByeFrame.wireType: self = .bye(try ByeFrame(from: decoder))
        case PairFrame.wireType: self = .pair(try PairFrame(from: decoder))
        case PairedFrame.wireType: self = .paired(try PairedFrame(from: decoder))
        case RequestFrame.wireType: self = .request(try RequestFrame(from: decoder))
        case ResponseFrame.wireType: self = .response(try ResponseFrame(from: decoder))
        case PebbleEvent.wireType: self = .event(try PebbleEvent(frameFrom: decoder))
        default: self = .unknown(type: type, raw: try JSONValue(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .challenge(let frame): try frame.encode(to: encoder)
        case .hello(let frame): try frame.encode(to: encoder)
        case .welcome(let frame): try frame.encode(to: encoder)
        case .bye(let frame): try frame.encode(to: encoder)
        case .pair(let frame): try frame.encode(to: encoder)
        case .paired(let frame): try frame.encode(to: encoder)
        case .request(let frame): try frame.encode(to: encoder)
        case .response(let frame): try frame.encode(to: encoder)
        case .event(let event): try event.encodeFrame(to: encoder)
        case .unknown(let type, let raw):
            var object = raw.object ?? [:]
            object["t"] = .string(type)
            try JSONValue.object(object).encode(to: encoder)
        }
    }
}

/// A frame that could not be read. Content-free on purpose: safe to log.
public struct FrameDecodingError: Error, Sendable, Hashable, CustomStringConvertible {
    public var reason: String
    public init(reason: String) { self.reason = reason }
    public var description: String { "frame not readable: \(reason)" }
}

/// Encodes and decodes frames as UTF-8 JSON text, one frame per WebSocket message.
public enum FrameCodec {
    public static func decode(_ data: Data) throws -> Frame {
        // Measured first: the decoder recurses per level and a deep frame would overflow the stack (JSONNesting).
        guard !JSONNesting.exceeds(JSONNesting.maximumDepth, in: data) else {
            throw FrameDecodingError(reason: "nested too deeply")
        }
        do {
            return try JSONDecoder().decode(Frame.self, from: data)
        } catch let error as DecodingError {
            throw FrameDecodingError(reason: Self.describe(error))
        } catch {
            throw FrameDecodingError(reason: "not JSON")
        }
    }

    public static func decode(_ text: String) throws -> Frame {
        try decode(Data(text.utf8))
    }

    /// Compact JSON, keys sorted, slashes left alone.
    public static func encode(_ frame: Frame) throws -> Data {
        try encoder().encode(frame)
    }

    public static func encodeText(_ frame: Frame) throws -> String {
        String(decoding: try encode(frame), as: UTF8.self)
    }

    /// Compact JSON text for a value, keys sorted. Use it to make an elevated call's `params_json`, then sign exactly
    /// these characters' UTF-8 bytes.
    public static func jsonText(_ value: JSONValue) throws -> String {
        String(decoding: try encoder().encode(value), as: UTF8.self)
    }

    /// Reads JSON text into a value (an elevated call's `params_json`, a stored payload).
    public static func jsonValue(_ text: String) throws -> JSONValue {
        let data = Data(text.utf8)
        guard !JSONNesting.exceeds(JSONNesting.maximumDepth, in: data) else {
            throw FrameDecodingError(reason: "nested too deeply")
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw FrameDecodingError(reason: "not JSON")
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            let at = path(context)
            return "missing \(at.isEmpty ? key.stringValue : at + "." + key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "wrong type at \(path(context).isEmpty ? "top level" : path(context))"
        case .dataCorrupted(let context):
            return context.codingPath.isEmpty ? "not JSON" : "unreadable value at \(path(context))"
        @unknown default:
            return "unreadable"
        }
    }
}

// MARK: - The contract's fixed values

public enum RemoteContract {
    /// "v" in every versioned frame.
    public static let version = 1
    /// `wss://<host>:<port>` + this path.
    public static let path = "/pebble-remote/v1"
    /// The WebSocket subprotocol.
    public static let subprotocol = "pebble-remote.v1"
    /// Calls that must carry an `idem` key (3.4). The bridge answers a repeat with its first answer.
    public static let idempotentMethods: Set<String> = [
        "send", "new_chat", "run_steer", "approve", "approve_simple", "reject", "reject_simple", "undo",
        "question_answer", "question_cancel", "setting", "cancel", "run_pause", "run_resume", "remote.revoke_device",
    ]

    /// Calls a connection may make without the unlock (contract C1): reads. Every other call needs a Face ID proof from the
    /// device within the bridge's `unlock_seconds` (any elevated call counts, or `remote.unlock`).
    /// `remote.lock` (S-05: ends this device's unlock at once; params `{}`, result `{}`) is one of them: no proof, no
    /// `idem`, allowed while locked.
    public static let readMethods: Set<String> = [
        "state", "get_chat", "chat_search", "run_list", "run_get", "run_activity", "run_events", "stream_read",
        "artifact_get", "remote.status", "remote.devices", "remote.ping", "remote.chat_tail", "remote.chat_before",
        "remote.lock",
    ]
    /// Ends this device's unlock on the bridge (S-05); a bridge that offers it lists it in `welcome.methods`.
    public static let lockMethod = "remote.lock"
    /// How long an unlock lasts when the bridge does not say (C1: 15 minutes; the person can change it on the Mac).
    public static let defaultUnlockSeconds = 900
}

// MARK: - Tolerant timestamps

extension KeyedDecodingContainer {
    /// Unix milliseconds, sent as a whole or a fractional number.
    func decodeMillis(forKey key: Key) throws -> Int64 {
        if let whole = try? decode(Int64.self, forKey: key) { return whole }
        let value = try decode(Double.self, forKey: key)
        guard value.isFinite, abs(value) < 9.0e18 else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not a time")
        }
        return Int64(value.rounded())
    }

    func decodeMillisIfPresent(forKey key: Key) throws -> Int64? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeMillis(forKey: key)
    }
}
