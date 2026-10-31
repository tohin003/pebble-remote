import Foundation
import PebbleProtocol

/// Opening an authenticated connection (contract 3.2 and 3.3): race the endpoints to the bridge's `challenge`, then
/// answer it on the winner only (`hello`, or `pair` when pairing) and wait for `welcome`. Only one socket ever sends
/// `hello`, so the bridge never replaces one of this phone's connections with another from the same race, and a
/// pairing code is spent at most once. A pairing also waits for the person to confirm on the Mac (X-1): the phone
/// shows a code made from T_pair, and the bridge sends `paired` only once the person has confirmed that the Mac shows
/// the same one.
enum Handshake {
    /// What to answer the challenge with.
    enum Answer: Sendable {
        case hello(deviceID: String, deviceKey: any SigningKey, resume: HelloFrame.Resume?, app: String)
        /// `showingCode` is called once, as soon as `pair` has gone out (X-1): the person compares this code with the
        /// Mac's and confirms there, which can take up to two minutes.
        case pair(
            code: String, keys: DeviceKeys, device: PairFrame.Device, reason: String,
            showingCode: @Sendable (PairingCode) -> Void)
    }

    /// An open, authenticated connection.
    struct Established: Sendable {
        var socket: any FrameSocket
        var endpoint: Endpoint
        var welcome: WelcomeFrame
        /// This connection's `challenge.nonce`: every proof made on it names it (T_proof, contract v0.3).
        var nonce: String
        /// From `paired`, when pairing.
        var pairedDeviceID: String?
    }

    /// Why a handshake did not finish. Content-free: safe to log.
    enum Failure: Error, Sendable {
        /// The bridge refused with `bye`.
        case bye(ByeFrame)
        /// Every endpoint failed; `pinMismatch` when at least one presented a key other than the pinned one.
        case unreachable(pinMismatch: Bool)
        /// Every endpoint failed, and iOS kept at least one on the phone: the app may not use the local network.
        case localNetworkDenied
        /// The challenge came from another bridge (another `bid`) behind the pinned key.
        case wrongBridge
        /// The bridge speaks another contract version.
        case badVersion
        /// The bridge said something the contract does not allow here, or nothing in time.
        case protocolViolation(String)
        /// Pairing only: the Mac never confirmed. Its answer did not come in the time the person has (two minutes, and a
        /// few seconds more), or the connection ended with no word (a `bye` `bad_code` is `.bye`).
        case notConfirmed
    }

    private struct Opened: Sendable {
        var socket: any FrameSocket
        var challenge: ChallengeFrame
    }

    /// `confirmationTimeout` is how long a pairing waits for the person to confirm on the Mac, and `pingInterval` how
    /// often it pings meanwhile, so that neither side takes the quiet for a dead connection.
    static func establish(
        bridgeID: String, pin: String, endpoints: [Endpoint], answer: Answer, connector: any FrameSocketConnector,
        raceDelay: Duration, readTimeout: Duration,
        confirmationTimeout: Duration = LiveClient.Configuration.defaultPairingConfirmationTimeout,
        pingInterval: Duration = .seconds(15)
    ) async throws -> Established {
        let opened: Opened
        let endpoint: Endpoint
        do {
            (opened, endpoint) = try await EndpointRace.run(
                endpoints, delay: raceDelay,
                attempt: { endpoint in
                    let socket = try await connector.open(endpoint, pin: pin)
                    do {
                        let challenge = try await readChallenge(socket, timeout: readTimeout)
                        return Opened(socket: socket, challenge: challenge)
                    } catch {
                        await socket.close()
                        throw error
                    }
                },
                discard: { opened in await opened.socket.close() })
        } catch let failure as EndpointRace.AllFailed {
            let errors = failure.failures.compactMap { $0.error as? FrameSocketError }
            if !errors.contains(.pinMismatch), errors.contains(.localNetworkDenied) { throw Failure.localNetworkDenied }
            throw Failure.unreachable(pinMismatch: errors.contains(.pinMismatch))
        }

        let socket = opened.socket
        let challenge = opened.challenge
        do {
            guard challenge.version == RemoteContract.version else { throw Failure.badVersion }
            guard challenge.bridgeID == bridgeID else { throw Failure.wrongBridge }
            switch answer {
            case .hello(let deviceID, let deviceKey, let resume, let app):
                let transcript = try SignedTranscript.hello(
                    bridgeID: bridgeID, deviceID: deviceID, nonce: challenge.nonce, pin: pin)
                let signature = try await deviceKey.sign(transcript, reason: "")
                let hello = HelloFrame(
                    deviceID: deviceID, signature: Base64URL.encode(signature), resume: resume, app: app)
                try await socket.send(FrameCodec.encodeText(.hello(hello)))
                let welcome = try await readWelcome(socket, timeout: readTimeout)
                return Established(
                    socket: socket, endpoint: endpoint, welcome: welcome, nonce: challenge.nonce, pairedDeviceID: nil)

            case .pair(let code, let keys, let device, let reason, let showingCode):
                let transcript = try SignedTranscript.pair(
                    bridgeID: bridgeID, nonce: challenge.nonce, pin: pin, code: code,
                    deviceKey: keys.device.publicKeyText, approveKey: keys.approve.publicKeyText)
                let signature = try await keys.device.sign(transcript, reason: "")
                // Face ID, once: proves the phone holds the approve key.
                let approveSignature = try await keys.approve.sign(transcript, reason: reason)
                let pair = PairFrame(
                    code: code, device: device, deviceKey: keys.device.publicKeyText,
                    approveKey: keys.approve.publicKeyText, signature: Base64URL.encode(signature),
                    approveSignature: Base64URL.encode(approveSignature))
                try await socket.send(FrameCodec.encodeText(.pair(pair)))
                // X-1: the Mac shows a code made from the same T_pair, and sends `paired` only once the person has
                // confirmed there that the two match. The phone shows its code now and waits.
                showingCode(PairingCode(pairTranscript: transcript))
                let deviceID = try await readPaired(socket, timeout: confirmationTimeout, pingInterval: pingInterval)
                let welcome = try await readWelcome(socket, timeout: readTimeout)
                return Established(
                    socket: socket, endpoint: endpoint, welcome: welcome, nonce: challenge.nonce,
                    pairedDeviceID: deviceID)
            }
        } catch {
            await socket.close()
            throw error
        }
    }

    /// The first frame must be the challenge.
    private static func readChallenge(_ socket: any FrameSocket, timeout: Duration) async throws -> ChallengeFrame {
        try await withDeadline(timeout, closing: socket) {
            let text = try await socket.receive()
            switch try FrameCodec.decode(text) {
            case .challenge(let challenge): return challenge
            case .bye(let bye): throw Failure.bye(bye)
            default: throw Failure.protocolViolation("expected challenge")
            }
        }
    }

    /// `welcome`, or the bridge's `bye`. When pairing, `paired` came before it (`readPaired`).
    private static func readWelcome(
        _ socket: any FrameSocket, timeout: Duration
    ) async throws -> WelcomeFrame {
        try await withDeadline(timeout, closing: socket) {
            while true {
                let text = try await socket.receive()
                switch try FrameCodec.decode(text) {
                case .welcome(let welcome):
                    return welcome
                case .bye(let bye):
                    throw Failure.bye(bye)
                case .unknown:
                    continue  // a newer bridge's frame
                default:
                    throw Failure.protocolViolation("expected welcome")
                }
            }
        }
    }

    /// `paired`'s device id (X-1). The Mac sends it only after the person has confirmed there that its code matches the
    /// phone's, so this waits for a person: up to `timeout`. A cancel on the Mac, or two minutes there without an answer,
    /// is its `bye` `bad_code` (thrown as `.bye`). A connection that ends with no word, or no answer by `timeout`, is
    /// `.notConfirmed`. While it waits the phone pings every `pingInterval`, so that a bridge that closes a silent
    /// connection never takes a person's thinking for a dead phone.
    private static func readPaired(
        _ socket: any FrameSocket, timeout: Duration, pingInterval: Duration
    ) async throws -> String {
        let keepAlive = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: pingInterval)
                guard !Task.isCancelled else { return }
                try? await socket.ping()
            }
        }
        defer { keepAlive.cancel() }
        do {
            return try await withDeadline(timeout, closing: socket) {
                while true {
                    let text = try await socket.receive()
                    switch try FrameCodec.decode(text) {
                    case .paired(let paired):
                        return paired.deviceID
                    case .bye(let bye):
                        throw Failure.bye(bye)
                    case .unknown:
                        continue  // a newer bridge's frame
                    default:
                        throw Failure.protocolViolation("expected paired")
                    }
                }
            }
        } catch FrameSocketError.closed {
            // Closed by the deadline above, by the Mac, or by the network. Closed by the person leaving is no failure.
            if Task.isCancelled { throw CancellationError() }
            throw Failure.notConfirmed
        }
    }

    /// Runs `body`, closing `socket` if it takes longer than `timeout` (which ends any wait in `receive`).
    static func withDeadline<Value: Sendable>(
        _ timeout: Duration, closing socket: any FrameSocket, _ body: () async throws -> Value
    ) async throws -> Value {
        let watchdog = Task {
            try await Task.sleep(for: timeout)
            await socket.close()
        }
        defer { watchdog.cancel() }
        return try await body()
    }
}
