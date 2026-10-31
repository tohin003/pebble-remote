import CryptoKit
import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane B's test kit: a bridge in memory that speaks the contract over fake sockets. It checks every signature the
// phone makes (T_hello, T_pair, T_proof) with CryptoKit, keeps a replay buffer for resume, remembers `idem` answers,
// replaces a device's older connection, and can drop connections, lose answers, restart or refuse. Lane X added the
// Mac's side of X-1 (a verified `pair` waits for the person to confirm the code on the Mac) and of S-05 (`remote.lock`,
// and an unlock that ends with the device's last connection).

/// A bridge in memory.
final class FakeBridge: Sendable {
    enum Reply: Sendable {
        case answer(ResponseFrame.Outcome)
        /// Never answers.
        case silent
        /// Does the work and remembers the answer (for `idem`), but the connection drops before it is sent.
        case loseAnswer(ResponseFrame.Outcome)
    }

    /// How an endpoint behaves when the phone connects to it.
    enum Behaviour: Sendable {
        case accept(after: Duration)
        case unreachable(after: Duration)
        /// Presents a TLS key other than the pinned one.
        case wrongKey
        /// iOS keeps the connection on the phone (the app's Local Network switch is off).
        case localNetworkDenied
    }

    struct Device: Sendable {
        var id: String
        var device: P256.Signing.PublicKey
        var approve: P256.Signing.PublicKey
    }

    /// A phone whose `pair` verified and whose person has not yet answered on the Mac (X-1).
    struct PendingPair: Sendable {
        var socket: FakeBridgeSocket
        var deviceKey: P256.Signing.PublicKey
        var approveKey: P256.Signing.PublicKey
    }

    let bridgeID = "bridge-1"
    /// What the bridge's TLS key hashes to.
    let pin = Vectors.pin
    let origin = ContinuousClock.now
    static let methods = [
        "state", "get_chat", "send", "new_chat", "cancel", "approve", "approve_simple", "reject", "setting",
        "chat_rename", "model_profiles", "remote.status", "remote.chat_tail", "remote.unlock",
    ]
    static let elevated: Set<String> = ["approve", "approve_simple", "remote.unlock", "setting:permissions"]

    private struct State {
        var epoch = "e1"
        var seq = 0
        var buffer: [PebbleEvent] = []
        var sockets: [FakeBridgeSocket] = []
        var nonces: [Int: String] = [:]
        var deviceOfSocket: [Int: String] = [:]
        var current: FakeBridgeSocket?
        var devices: [String: Device] = [:]
        var nextDevice = 0
        var pairingCode: String?
        /// X-1: a verified `pair` waits for `confirmPairing()` or `refusePairing()` instead of being answered at once.
        var confirmPairings = false
        var pendingPair: PendingPair?
        /// What the Mac would show for each pairing it verified, oldest first.
        var pairingCodes: [String] = []
        /// S-05: `welcome.methods` lists `remote.lock`, and a device's unlock ends with its last connection.
        var offersLock = false
        var hellos: [HelloFrame] = []
        var pairs: [PairFrame] = []
        var requests: [RequestFrame] = []
        var proofsChecked = 0
        var problems: [String] = []
        var idemAnswers: [String: ResponseFrame.Outcome] = [:]
        var executions: [String: Int] = [:]
        var behaviours: [Endpoint: Behaviour] = [:]
        var opens: [(endpoint: Endpoint, at: Duration)] = []
        var byeOnNextHello: ByeFrame?
        /// C1: calls that act need a Face ID proof from the last `unlockWindow` seconds.
        var requireUnlock = false
        var unlockWindow = 900
        /// Sent as `welcome.unlock_seconds` when set.
        var unlockSecondsInWelcome: Int?
        var unlockedUntil: [String: Date] = [:]
        var unlockRefusals = 0
        /// C2: proofs already accepted (a repeat is refused).
        var acceptedProofs: Set<String> = []
        var pingMode: FakeBridgeSocket.PingMode = .answer
        var responder: @Sendable (RequestFrame) -> Reply = { _ in .answer(.success(.object([:]))) }
        /// The burst limit (3.9): the requests it picks are refused `rate_limited` first, as Pebble's bridge does.
        var burstLimit: @Sendable (RequestFrame) -> Bool = { _ in false }
    }

    private let state = Mutex(State())

    // MARK: Set-up

    @discardableResult
    func register(_ keys: DeviceKeys, id: String = "dev-1") -> String {
        state.withLock { s in
            s.devices[id] = Device(id: id, device: keys.device.publicKey, approve: keys.approve.publicKey)
        }
        return id
    }

    func respond(_ responder: @escaping @Sendable (RequestFrame) -> Reply) {
        state.withLock { $0.responder = responder }
    }

    /// Refuses the requests `refuse` picks with `rate_limited`, as Pebble's bridge (remote_bridge.py `on_req`) refuses
    /// a burst: before it looks at the proof, the unlock or `idem`, so nothing is checked, kept or done for them.
    func limitBursts(_ refuse: @escaping @Sendable (RequestFrame) -> Bool) {
        state.withLock { $0.burstLimit = refuse }
    }

    func set(_ behaviour: Behaviour, for endpoint: Endpoint) {
        state.withLock { $0.behaviours[endpoint] = behaviour }
    }

    func allowPairing(code: String) {
        state.withLock { $0.pairingCode = code }
    }

    func refuseNextHello(_ bye: ByeFrame) {
        state.withLock { $0.byeOnNextHello = bye }
    }

    /// X-1: from now on a verified `pair` waits for the person on the Mac (`confirmPairing()`, `refusePairing()`).
    func requirePairingConfirmation() {
        state.withLock { $0.confirmPairings = true }
    }

    /// S-05: the bridge lists `remote.lock`, and ends a device's unlock when its last connection closes.
    func offerLock() {
        state.withLock { $0.offersLock = true }
    }

    func setPingMode(_ mode: FakeBridgeSocket.PingMode) {
        state.withLock { $0.pingMode = mode }
    }

    /// Turns on C1: calls that act need an unlock within `window` seconds; `announce` goes in `welcome`.
    func requireUnlock(window: Int = 900, announce: Int? = nil) {
        state.withLock { s in
            s.requireUnlock = true
            s.unlockWindow = window
            s.unlockSecondsInWelcome = announce
        }
    }

    /// Forgets every unlock, as when the person's window ran out.
    func lock() {
        state.withLock { $0.unlockedUntil = [:] }
    }

    // MARK: What happened

    var hellos: [HelloFrame] { state.withLock { $0.hellos } }
    var pairs: [PairFrame] { state.withLock { $0.pairs } }
    var requests: [RequestFrame] { state.withLock { $0.requests } }
    var proofsChecked: Int { state.withLock { $0.proofsChecked } }
    var unlockRefusals: Int { state.withLock { $0.unlockRefusals } }
    /// The codes the Mac would show for the pairings it verified, oldest first.
    var pairingCodes: [String] { state.withLock { $0.pairingCodes } }
    /// A phone is waiting for the person to confirm on the Mac.
    var isAwaitingConfirmation: Bool { state.withLock { $0.pendingPair != nil } }
    var problems: [String] { state.withLock { $0.problems } }
    var sockets: [FakeBridgeSocket] { state.withLock { $0.sockets } }
    var opens: [Endpoint] { state.withLock { $0.opens.map(\.endpoint) } }
    var current: FakeBridgeSocket? { state.withLock { $0.current } }
    func executions(of method: String) -> Int { state.withLock { $0.executions[method] ?? 0 } }
    func requests(_ method: String) -> [RequestFrame] { requests.filter { $0.method == method } }

    // MARK: Acting

    /// One of Pebble's events: buffered for resume and sent to the phone's current connection.
    func emit(_ name: String, _ data: JSONValue = [:]) {
        state.withLock { s in
            s.seq += 1
            let event = PebbleEvent(seq: s.seq, name: name, data: data)
            s.buffer.append(event)
            if let current = s.current, !current.isClosed {
                current.push(Self.text(.event(event)))
            }
        }
    }

    /// Skips seq numbers, as if events were lost.
    func skip(_ count: Int) {
        state.withLock { $0.seq += count }
    }

    /// Sends any frame to the current connection.
    func push(_ frame: Frame) {
        state.withLock { $0.current }?.push(Self.text(frame))
    }

    /// The person confirms on the Mac that the codes match: the phone is stored and gets `paired`, then `welcome`.
    /// False when no phone is waiting any more (it left).
    @discardableResult
    func confirmPairing() -> Bool {
        state.withLock { s in
            guard let pending = s.pendingPair else { return false }
            s.pendingPair = nil
            guard !pending.socket.isClosed else { return false }
            Self.finishPairing(pending, &s)
            return true
        }
    }

    /// The person cancels on the Mac, or two minutes pass: `bye` `bad_code`, then the close. The pairing code stays spent.
    func refusePairing(words: String = "Pairing wasn't confirmed on your Mac. Show a new pairing link there and try again.") {
        let pending = state.withLock { s in
            defer { s.pendingPair = nil }
            return s.pendingPair
        }
        pending?.socket.push(Self.text(.bye(ByeFrame(code: ByeCode(rawValue: "bad_code"), error: words))))
        pending?.socket.closeNow()
    }

    /// Answers a request that was left unanswered.
    func answer(_ id: String, _ outcome: ResponseFrame.Outcome) {
        push(.response(ResponseFrame(id: id, outcome: outcome)))
    }

    /// The network drops the current connection (no `bye`).
    func drop() {
        state.withLock { $0.current }?.closeNow()
    }

    /// Refuses the current connection and closes it.
    func bye(_ code: ByeCode, _ words: String? = nil) {
        let socket = state.withLock { $0.current }
        socket?.push(Self.text(.bye(ByeFrame(code: code, error: words))))
        socket?.closeNow()
    }

    /// The bridge restarts: a new epoch, an empty buffer, no memory of `idem` keys, every connection gone.
    func restart(epoch: String) {
        let sockets = state.withLock { s in
            s.epoch = epoch
            s.seq = 0
            s.buffer = []
            s.idemAnswers = [:]
            s.current = nil
            return s.sockets
        }
        for socket in sockets { socket.closeNow() }
    }

    // MARK: The connector's side

    func open(_ endpoint: Endpoint, pin: String) async throws -> FakeBridgeSocket {
        let behaviour = state.withLock { s in
            s.opens.append((endpoint, ContinuousClock.now - origin))
            return s.behaviours[endpoint] ?? .accept(after: .zero)
        }
        switch behaviour {
        case .accept(let delay):
            if delay > .zero { try await Task.sleep(for: delay) }
        case .unreachable(let delay):
            if delay > .zero { try await Task.sleep(for: delay) }
            throw FrameSocketError.unreachable("fake")
        case .wrongKey:
            throw FrameSocketError.pinMismatch
        case .localNetworkDenied:
            throw FrameSocketError.localNetworkDenied
        }
        guard pin == self.pin else { throw FrameSocketError.pinMismatch }
        let nonce = Base64URL.encode(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
        let socket = state.withLock { s in
            let socket = FakeBridgeSocket(number: s.sockets.count + 1, endpoint: endpoint, bridge: self, ping: s.pingMode)
            s.sockets.append(socket)
            s.nonces[socket.number] = nonce
            return socket
        }
        socket.push(Self.text(.challenge(ChallengeFrame(bridgeID: bridgeID, nonce: nonce, time: Self.nowMillis()))))
        return socket
    }

    /// A frame from the phone.
    func received(_ text: String, on socket: FakeBridgeSocket) {
        guard let frame = try? FrameCodec.decode(text) else {
            state.withLock { $0.problems.append("unreadable frame") }
            return
        }
        state.withLock { s in
            switch frame {
            case .hello(let hello): Self.hello(hello, on: socket, &s, bridgeID: bridgeID, pin: pin)
            case .pair(let pair): Self.pair(pair, on: socket, &s, bridgeID: bridgeID, pin: pin)
            case .request(let request): Self.request(request, on: socket, &s, bridgeID: bridgeID)
            default: s.problems.append("unexpected \(frame.type)")
            }
        }
    }

    // MARK: The contract, bridge side

    private static func hello(_ hello: HelloFrame, on socket: FakeBridgeSocket, _ s: inout State, bridgeID: String, pin: String) {
        s.hellos.append(hello)
        guard let nonce = s.nonces[socket.number], let device = s.devices[hello.deviceID] else {
            refuse(socket, .unknownDevice)
            return
        }
        guard
            let transcript = try? SignedTranscript.hello(
                bridgeID: bridgeID, deviceID: hello.deviceID, nonce: nonce, pin: pin),
            verify(hello.signature, transcript, device.device)
        else {
            s.problems.append("bad hello signature")
            refuse(socket, .badSignature)
            return
        }
        if let bye = s.byeOnNextHello {
            s.byeOnNextHello = nil
            socket.push(text(.bye(bye)))
            socket.closeNow()
            return
        }
        authenticate(socket, device: device.id, &s)
        var resumed = false
        var replay: [PebbleEvent] = []
        if let resume = hello.resume, resume.epoch == s.epoch, resume.seq <= s.seq,
            resume.seq >= (s.buffer.first?.seq ?? s.seq + 1) - 1
        {
            resumed = true
            replay = s.buffer.filter { $0.seq > resume.seq }
        }
        socket.push(welcomeText(&s, resumed: resumed))
        for event in replay { socket.push(text(.event(event))) }
    }

    private static func pair(_ pair: PairFrame, on socket: FakeBridgeSocket, _ s: inout State, bridgeID: String, pin: String) {
        s.pairs.append(pair)
        guard let code = s.pairingCode, code == pair.code, let nonce = s.nonces[socket.number] else {
            socket.push(text(.bye(ByeFrame(code: ByeCode(rawValue: "bad_code"), error: "That pairing link has expired."))))
            socket.closeNow()
            return
        }
        s.pairingCode = nil  // once
        guard
            let deviceData = Base64URL.decode(pair.deviceKey),
            let approveData = Base64URL.decode(pair.approveKey),
            let deviceKey = try? P256.Signing.PublicKey(x963Representation: deviceData),
            let approveKey = try? P256.Signing.PublicKey(x963Representation: approveData),
            let transcript = try? SignedTranscript.pair(
                bridgeID: bridgeID, nonce: nonce, pin: pin, code: pair.code, deviceKey: pair.deviceKey,
                approveKey: pair.approveKey),
            verify(pair.signature, transcript, deviceKey), verify(pair.approveSignature, transcript, approveKey)
        else {
            s.problems.append("bad pair signature")
            refuse(socket, .badSignature)
            return
        }
        s.pairingCodes.append(macCode(for: transcript))
        let pending = PendingPair(socket: socket, deviceKey: deviceKey, approveKey: approveKey)
        if s.confirmPairings {
            s.pendingPair = pending  // X-1: nothing is stored, and `paired` waits for the person on the Mac
        } else {
            finishPairing(pending, &s)
        }
    }

    /// The Mac's person confirmed (or the bridge is the old kind that never asks): store the phone, then `paired`
    /// and `welcome`.
    private static func finishPairing(_ pending: PendingPair, _ s: inout State) {
        s.nextDevice += 1
        let id = "dev-\(s.nextDevice)"
        s.devices[id] = Device(id: id, device: pending.deviceKey, approve: pending.approveKey)
        authenticate(pending.socket, device: id, &s)
        pending.socket.push(text(.paired(PairedFrame(deviceID: id))))
        pending.socket.push(welcomeText(&s, resumed: false))
    }

    /// The six digits the Mac shows (X-1), computed the other way round from the phone's `PairingCode`: bytes by hand,
    /// and Foundation's own formatting for the zero padding. Checked against fixed vectors in PairingConfirmationTests.
    static func macCode(for transcript: Data) -> String {
        let digest = Array(SHA256.hash(data: Data("pebble-remote/v1/sas\n".utf8) + transcript))
        let number = (Int(digest[0]) << 24) | (Int(digest[1]) << 16) | (Int(digest[2]) << 8) | Int(digest[3])
        return String(format: "%06d", number % 1_000_000)
    }

    private static func request(_ request: RequestFrame, on socket: FakeBridgeSocket, _ s: inout State, bridgeID: String) {
        guard let deviceID = s.deviceOfSocket[socket.number], let device = s.devices[deviceID],
            let nonce = s.nonces[socket.number]
        else {
            s.problems.append("request before welcome")
            return
        }
        s.requests.append(request)
        func refuse(_ code: String, _ words: String) {
            socket.push(text(.response(ResponseFrame(id: request.id, outcome: .failure(error: words, code: code)))))
        }
        if request.id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) == nil {
            s.problems.append("bad request id")
            return refuse("bad_request", "Bad id.")
        }
        if s.burstLimit(request) {
            return refuse("rate_limited", "That's a lot of requests at once. Try again in a moment.")
        }
        let isRead = LiveClient.readMethods.contains(request.method)
        if !isRead && request.idem == nil { s.problems.append("act without idem: \(request.method)") }
        if isRead && request.idem != nil { s.problems.append("read with idem: \(request.method)") }
        if request.method == "remote.lock" {
            // S-05: ends this device's unlock at once (a read: no proof, no idem, allowed while locked). A bridge that
            // does not offer it refuses as it would any method it does not know.
            guard s.offersLock else {
                s.problems.append("remote.lock sent to a bridge that does not offer it")
                return refuse("not_allowed", "That can only be done on your Mac.")
            }
            s.unlockedUntil[deviceID] = nil
        }
        if elevated.contains(request.method) {
            guard let paramsJSON = request.paramsJSON, let proof = request.proof else {
                return refuse("proof_required", "Needs Face ID.")
            }
            // T_proof v0.3: bound to this connection's nonce and the call's idem.
            guard abs(proof.ts - nowMillis()) <= 60_000, let idem = request.idem,
                let transcript = try? SignedTranscript.proof(
                    bridgeID: bridgeID, deviceID: deviceID, epoch: s.epoch, nonce: nonce, requestID: request.id,
                    idem: idem, method: request.method, paramsJSON: paramsJSON, timestamp: proof.ts),
                verify(proof.sig, transcript, device.approve)
            else {
                s.problems.append("bad proof")
                return refuse("bad_proof", "That approval could not be checked.")
            }
            guard s.acceptedProofs.insert(proof.sig).inserted else {
                s.problems.append("proof replayed")
                return refuse("bad_proof", "That approval was already used.")
            }
            s.proofsChecked += 1
            s.unlockedUntil[deviceID] = Date().addingTimeInterval(TimeInterval(s.unlockWindow))
            if request.method == "remote.unlock" {
                let until = Int64(((s.unlockedUntil[deviceID] ?? Date()).timeIntervalSince1970 * 1000).rounded())
                return socket.push(text(.response(ResponseFrame(id: request.id, outcome: .success(["until": .int(Int(until))])))))
            }
        } else if s.requireUnlock && !isRead && (s.unlockedUntil[deviceID] ?? .distantPast) < Date() {
            // C1, refused before the idem is looked up or kept.
            s.unlockRefusals += 1
            return refuse("unlock_required", "Unlock with Face ID first.")
        }
        if let idem = request.idem, let first = s.idemAnswers[idem] {
            socket.push(text(.response(ResponseFrame(id: request.id, outcome: first))))
            return
        }
        s.executions[request.method, default: 0] += 1
        switch s.responder(request) {
        case .answer(let outcome):
            if let idem = request.idem { s.idemAnswers[idem] = outcome }
            socket.push(text(.response(ResponseFrame(id: request.id, outcome: outcome))))
        case .silent:
            break
        case .loseAnswer(let outcome):
            if let idem = request.idem { s.idemAnswers[idem] = outcome }
            socket.closeNow()
        }
    }

    /// One connection per device: a new one replaces the older with `bye replaced`.
    private static func authenticate(_ socket: FakeBridgeSocket, device: String, _ s: inout State) {
        s.deviceOfSocket[socket.number] = device
        // S-05: a device's unlock ends when its last connection closes. A connection that replaces one still open is not
        // that; one that comes after the old was closed finds the unlock gone.
        if s.offersLock, !(s.current.map { !$0.isClosed } ?? false) { s.unlockedUntil[device] = nil }
        if let previous = s.current, previous !== socket, !previous.isClosed {
            previous.push(text(.bye(ByeFrame(code: .replaced, error: "Another connection from this iPhone took over."))))
            previous.closeNow()
        }
        s.current = socket
    }

    private static func welcomeText(_ s: inout State, resumed: Bool) -> String {
        let frame = WelcomeFrame(
            epoch: s.epoch, seq: s.seq, resumed: resumed, bridge: .init(version: "test", name: "Studio Mac"),
            pebble: .init(running: true, version: "1.9.28"), methods: s.offersLock ? methods + ["remote.lock"] : methods,
            elevated: Array(elevated).sorted(), limits: .contract)
        guard let seconds = s.unlockSecondsInWelcome,
            case .object(var object) = try! FrameCodec.jsonValue(text(.welcome(frame)))
        else { return text(.welcome(frame)) }
        object["unlock_seconds"] = .int(seconds)
        return try! FrameCodec.jsonText(.object(object))
    }

    private static func refuse(_ socket: FakeBridgeSocket, _ code: ByeCode) {
        socket.push(text(.bye(ByeFrame(code: code, error: "Refused (\(code.rawValue))."))))
        socket.closeNow()
    }

    static func verify(_ signature: String, _ message: Data, _ key: P256.Signing.PublicKey) -> Bool {
        guard let der = Base64URL.decode(signature),
            let parsed = try? P256.Signing.ECDSASignature(derRepresentation: der)
        else { return false }
        return key.isValidSignature(parsed, for: message)
    }

    static func text(_ frame: Frame) -> String {
        try! FrameCodec.encodeText(frame)
    }

    static func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}

/// One fake connection. Frames pushed by the bridge wait in an inbox for `receive()`.
final class FakeBridgeSocket: FrameSocket {
    enum PingMode: Sendable { case answer, hang }

    let number: Int
    let endpoint: Endpoint
    let bridge: FakeBridge

    private struct State {
        var inbox: [String] = []
        var waiter: CheckedContinuation<String, any Error>?
        var closed = false
        var sent: [String] = []
        var pings = 0
        var pingMode: PingMode
    }

    private let state: Mutex<State>

    init(number: Int, endpoint: Endpoint, bridge: FakeBridge, ping: PingMode) {
        self.number = number
        self.endpoint = endpoint
        self.bridge = bridge
        self.state = Mutex(State(pingMode: ping))
    }

    var isClosed: Bool { state.withLock { $0.closed } }
    var sent: [String] { state.withLock { $0.sent } }
    var pings: Int { state.withLock { $0.pings } }

    /// Bridge to phone.
    func push(_ text: String) {
        let waiter: CheckedContinuation<String, any Error>? = state.withLock { s in
            guard !s.closed else { return nil }
            if let waiter = s.waiter {
                s.waiter = nil
                return waiter
            }
            s.inbox.append(text)
            return nil
        }
        waiter?.resume(returning: text)
    }

    /// Ends the connection (either side). Frames already in the inbox are still read first.
    func closeNow() {
        let waiter: CheckedContinuation<String, any Error>? = state.withLock { s in
            s.closed = true
            defer { s.waiter = nil }
            return s.inbox.isEmpty ? s.waiter : nil
        }
        waiter?.resume(throwing: FrameSocketError.closed)
    }

    func receive() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
                let ready: Result<String, any Error>? = state.withLock { s in
                    if !s.inbox.isEmpty { return .success(s.inbox.removeFirst()) }
                    if s.closed { return .failure(FrameSocketError.closed) }
                    s.waiter = continuation
                    return nil
                }
                if let ready { continuation.resume(with: ready) }
            }
        } onCancel: {
            closeNow()
        }
    }

    func send(_ text: String) async throws {
        let closed = state.withLock { s in
            if !s.closed { s.sent.append(text) }
            return s.closed
        }
        if closed { throw FrameSocketError.closed }
        bridge.received(text, on: self)
    }

    func ping() async throws {
        let (closed, mode) = state.withLock { s in
            s.pings += 1
            return (s.closed, s.pingMode)
        }
        if closed { throw FrameSocketError.closed }
        switch mode {
        case .answer: try await Task.sleep(for: .milliseconds(1))
        case .hang: try await Task.sleep(for: .seconds(3600))
        }
    }

    func close() async {
        closeNow()
    }
}

struct FakeBridgeConnector: FrameSocketConnector {
    let bridge: FakeBridge
    func open(_ endpoint: Endpoint, pin: String) async throws -> any FrameSocket {
        try await bridge.open(endpoint, pin: pin)
    }
}

/// A path watcher the test changes by hand.
final class ManualPathWatcher: PathWatching {
    private let handler = Mutex<(@Sendable () -> Void)?>(nil)
    func start(_ onChange: @escaping @Sendable () -> Void) { handler.withLock { $0 = onChange } }
    func stop() { handler.withLock { $0 = nil } }
    var isWatching: Bool { handler.withLock { $0 != nil } }
    func change() { handler.withLock { $0 }?() }
}

/// Bonjour discovery the test drives by hand.
final class ManualDiscovery: BridgeDiscovering {
    private let handler = Mutex<(bridgeID: String, found: @Sendable ([Endpoint]) -> Void)?>(nil)
    func start(bridgeID: String, found: @escaping @Sendable ([Endpoint]) -> Void) {
        handler.withLock { $0 = (bridgeID, found) }
    }
    func stop() { handler.withLock { $0 = nil } }
    var watchedBridge: String? { handler.withLock { $0?.bridgeID } }
    func find(_ endpoints: [Endpoint]) { handler.withLock { $0 }?.found(endpoints) }
}

/// A key provider whose approve key records the reasons it signs with (what Face ID would show).
final class RecordingKeyProvider: KeyProvider {
    /// Signs with `inner` and writes each reason into the provider's log.
    struct Recorder: SigningKey {
        let inner: SoftwareSigningKey
        let log: RecordingKeyProvider
        var role: KeyRole { inner.role }
        var publicKey: P256.Signing.PublicKey { inner.publicKey }
        func sign(_ message: Data, reason: String) async throws -> Data {
            log.reasonLog.withLock { $0.append(reason) }
            return try await inner.sign(message, reason: reason)
        }
    }

    let reasonLog = Mutex<[String]>([])
    private let kept = Mutex<[String: DeviceKeys]>([:])
    private let windowEnding = Mutex(0)

    var reasons: [String] { reasonLog.withLock { $0 } }
    /// How many times the client ended the approval window (S-14).
    var windowEnds: Int { windowEnding.withLock { $0 } }

    func endApprovalWindow() async {
        windowEnding.withLock { $0 += 1 }
    }

    func makeKeys() async throws -> DeviceKeys {
        DeviceKeys(
            device: SoftwareSigningKey(role: .device),
            approve: Recorder(inner: SoftwareSigningKey(role: .approve), log: self))
    }

    func save(_ keys: DeviceKeys, for bridgeID: String) async throws {
        kept.withLock { $0[bridgeID] = keys }
    }

    func keys(for bridgeID: String) async throws -> DeviceKeys? {
        kept.withLock { $0[bridgeID] }
    }

    func deleteKeys(for bridgeID: String) async throws {
        _ = kept.withLock { $0.removeValue(forKey: bridgeID) }
    }
}

/// Everything a client said through `updates`, in order.
final class UpdateLog: Sendable {
    private let items = Mutex<[ClientUpdate]>([])
    private let consumer = Mutex<Task<Void, Never>?>(nil)

    init(_ client: LiveClient) {
        let stream = client.updates
        let task = Task { [weak self] in
            for await update in stream {
                guard let self else { return }
                self.items.withLock { $0.append(update) }
            }
        }
        consumer.withLock { $0 = task }
    }

    deinit {
        consumer.withLock { $0?.cancel() }
    }

    var all: [ClientUpdate] { items.withLock { $0 } }

    var events: [PebbleEvent] {
        all.compactMap { if case .event(let event) = $0 { event } else { nil } }
    }

    var statuses: [ConnectionStatus] {
        all.compactMap { if case .status(let status) = $0 { status } else { nil } }
    }

    var phases: [ConnectionPhase] { statuses.map(\.phase) }
    var phase: ConnectionPhase? { statuses.last?.phase }

    var welcomes: [BridgeInfo] {
        all.compactMap { if case .welcome(let info) = $0 { info } else { nil } }
    }

    /// Every `.unlocked(until:)` the client reported, in order.
    var unlocks: [Date?] {
        all.compactMap { if case .unlocked(let until) = $0 { .some(until) } else { nil } }
    }

    var resyncCount: Int {
        all.filter { if case .resyncNeeded = $0 { true } else { false } }.count
    }

    /// How many times the client became connected (a round-trip update while connected does not count).
    var connectedCount: Int {
        var count = 0
        var previous: ConnectionPhase?
        for phase in phases {
            if phase == .connected, previous != .connected { count += 1 }
            previous = phase
        }
        return count
    }
}

struct TimedOut: Error, CustomStringConvertible {
    var what: String
    var description: String { "timed out waiting for \(what)" }
}

/// Polls `condition` until it holds, or fails after `timeout`.
func eventually(
    _ what: String, timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    if await condition() { return }
    throw TimedOut(what: what)
}
