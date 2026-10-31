import Foundation
import PebbleProtocol
import os

/// The live connection to Pebble's bridge on the Mac (the bridge contract).
///
/// - **Connecting:** races the Mac's endpoints (LAN at once, the others 150 ms later), answers the bridge's challenge
///   on the first socket to deliver one (`hello`, signed by the device key, with the resume point), and waits for
///   `welcome`.
/// - **Calls:** request/response by id (`r<n>`, within `[A-Za-z0-9_-]{1,64}`), answered within the request timeout.
///   Every call that is not a read (contract C1's list) carries an `idem` key (v0.3 item 4). Elevated calls carry
///   `params_json` and a proof by the approve key (Face ID, 3.6) bound to the connection's nonce and the call's
///   `idem` (v0.3 item 3). Calls made while reconnecting wait for the connection.
/// - **The unlock (C1):** a call refused with `unlock_required` asks for Face ID (`unlockReason`), sends
///   `remote.unlock`, and is tried once more with the same `idem`. Any elevated call counts as an unlock;
///   `unlockedUntil` says until when, from `welcome.unlock_seconds` (15 minutes when the bridge does not say).
/// - **Ending the unlock (S-05):** `lock()` clears `unlockedUntil`, ends the window in which one Face ID check covers
///   the next approvals (S-14) and, when the bridge offers `remote.lock`, asks it to end this device's unlock at once,
///   briefly and ignoring failure. Such a bridge also ends a device's unlock when
///   its last connection closes, so `unlockedUntil` is cleared when the connection ends, by `disconnect()` or by
///   a loss (not when a newer connection of this phone takes over: that one carries the unlock on).
/// - **Losing the connection:** reconnects with exponential backoff and jitter (0.5 s to 30 s), at once when the
///   network path changes. An unanswered call is sent again once, with the same `idem`, if the bridge is still in
///   the same epoch (an elevated call with a new proof for the new connection); otherwise it fails as
///   `bridge_restarted`, and after a second loss as `connection_lost`.
/// - **Events:** delivered once each, in `seq` order; the epoch and last seq are the resume point, kept across
///   `disconnect()` and `connect(to:)` for the same Mac, so a return from the background misses nothing. When the
///   bridge cannot replay (`resumed` false) or events are missing, `.resyncNeeded` tells the store to refetch.
/// - **Heartbeat:** a WebSocket ping on connecting and every 15 s; the round trip goes into
///   `ConnectionStatus.roundTrip`. A ping unanswered for 10 s counts as a lost connection.
/// - **Refusals:** `bye` codes become `ConnectionProblem`s; those that need the person stop reconnecting.
/// - **The burst limit (3.9):** a call the bridge answers `rate_limited` was refused before the bridge acted on it, so
///   nothing ran and neither its id nor its `idem` was kept. The same frame goes again on the same connection after
///   `Configuration.rateLimitPause`, doubling, up to `rateLimitRetries` times; only then does the refusal reach the
///   caller. `lock()`'s brief call is not sent again.
///
/// Client-side failures are `RemoteCallError.transport` with a content-free code for the screens to put in words:
/// `connection_lost`, `bridge_restarted`, `too_large`, `bad_params`, and, from `pair`, `unreachable`,
/// `pin_mismatch`, `wrong_bridge`, `bad_version`, `biometry_unavailable`, `keys_unavailable`, `protocol`, `bad_code` (a
/// `bye` `bad_code`: the Mac's person cancelled or did not confirm in time, or the link was used or had expired) and
/// `not_confirmed` (nothing came from the Mac in time, or it closed the connection with no word). The person
/// cancelling a pairing is `RemoteCallError.cancelledByPerson`.
public actor LiveClient: RemoteClient {
    public struct Configuration: Sendable {
        /// How long a call waits for its answer after each send, and for a connection before its first. The bridge
        /// answers within 30 s (3.4); the extra 2 s let its own `timeout` answer, in words, arrive first.
        public var requestTimeout: Duration
        /// How long the bridge has to send `challenge` once the socket opens, and `welcome` after `hello`.
        public var readTimeout: Duration
        public var pingInterval: Duration
        public var pingTimeout: Duration
        /// How long LAN endpoints race alone before the others start.
        public var raceDelay: Duration
        public var backoff: Backoff
        /// How long a pairing waits for the person to confirm the code on the Mac (X-1): the Mac gives them two
        /// minutes, and a few seconds more cover the time its `bye` takes to reach the phone.
        public var pairingConfirmationTimeout: Duration
        /// 130 seconds: the Mac's two minutes, and ten seconds for its `bye` to arrive.
        public static let defaultPairingConfirmationTimeout = Duration.seconds(130)
        /// How long `lock()` waits for the bridge's answer to `remote.lock` (S-05): briefly, because the app is on its
        /// way to the background.
        public var lockTimeout: Duration
        /// How long a call the bridge's burst limit refused (`rate_limited`; 3.9: 20 requests in a burst, 10 a second)
        /// waits before it goes again. Each further try waits twice as long, plus up to half again at random, so a
        /// refused burst spreads out instead of arriving together.
        public var rateLimitPause: Duration

        public init(
            requestTimeout: Duration = .seconds(32), readTimeout: Duration = .seconds(10),
            pingInterval: Duration = .seconds(15), pingTimeout: Duration = .seconds(10),
            raceDelay: Duration = .milliseconds(150), backoff: Backoff = Backoff(),
            pairingConfirmationTimeout: Duration = Configuration.defaultPairingConfirmationTimeout,
            lockTimeout: Duration = .seconds(2), rateLimitPause: Duration = .milliseconds(250)
        ) {
            self.requestTimeout = requestTimeout
            self.readTimeout = readTimeout
            self.pingInterval = pingInterval
            self.pingTimeout = pingTimeout
            self.raceDelay = raceDelay
            self.backoff = backoff
            self.pairingConfirmationTimeout = pairingConfirmationTimeout
            self.lockTimeout = lockTimeout
            self.rateLimitPause = rateLimitPause
        }
    }

    /// The reads (contract C1): allowed without the unlock, sent without `idem`. Every other call carries one.
    public static var readMethods: Set<String> { RemoteContract.readMethods }

    /// How long an unlock lasts when `welcome.unlock_seconds` is missing (contract C1).
    public static var defaultUnlockSeconds: Int { RemoteContract.defaultUnlockSeconds }

    /// The most LAN endpoints Bonjour may add to a race (the paired Mac advertises one or two).
    public static let maximumDiscoveredEndpoints = 4

    public nonisolated let updates: AsyncStream<ClientUpdate>
    private nonisolated let sink: AsyncStream<ClientUpdate>.Continuation

    private let keyProvider: any KeyProvider
    private let connector: any FrameSocketConnector
    private let pathWatcher: any PathWatching
    private let discovery: any BridgeDiscovering
    private let device: DeviceDescription
    private let configuration: Configuration
    private let pairingReason: @Sendable (String) -> String
    private let unlockReason: String?
    private let clock: @Sendable () -> Date
    private static let log = Logger(subsystem: "PebbleRemote", category: "transport")

    // The session: from connect(to:) until disconnect() or a refusal that needs the person.
    private var mac: PairedMac?
    private var deviceKeys: DeviceKeys?
    private var session = 0
    private var running = false
    private var problem: ConnectionProblem?
    private var watchingPath = false
    /// LAN endpoints Bonjour found for this Mac (contract 3.1), raced with the paired ones.
    private var discovered: [Endpoint] = []

    // Getting connected.
    private var attemptTask: Task<Void, Never>?
    private var attemptID = 0
    private var retryTask: Task<Void, Never>?
    private var retryAt: Date?
    /// Consecutive attempts that failed (the backoff step).
    private var failures = 0
    private var hasConnected = false

    // The connection in use.
    private var active: Connection?
    private var nextConnectionID = 0
    private var roundTrip: Double?

    // Where to resume: the epoch and the last event seq delivered, for `resumeBridgeID`.
    private var resumeBridgeID: String?
    private var resumePoint: HelloFrame.Resume?

    // Calls.
    private var calls: [String: PendingCall] = [:]
    private var nextCallNumber = 0
    private var nextRequestNumber = 0
    private var activeWaiters: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var nextWaiterID = 0

    private var status = ConnectionStatus.idle

    // The unlock (C1): until when acting is unlocked, as far as this phone knows.
    private var unlockedUntilDate: Date?
    private var unlocking: Task<Void, any Error>?
    private var unlockLapse: Task<Void, Never>?

    /// - Parameters:
    ///   - keys: where the pairing keys are made and kept (`SecureEnclaveKeyProvider` on the phone).
    ///   - pairingReason: the sentence Face ID shows when pairing, given the Mac's name (from PebbleDesign's copy).
    ///   - unlockReason: the sentence Face ID shows when a call needs the unlock (C1). Without it, `unlock_required`
    ///     refusals reach the caller, which can call `unlock(reason:)` itself.
    public init(
        keys: any KeyProvider, pairingReason: @escaping @Sendable (String) -> String, unlockReason: String? = nil,
        connector: any FrameSocketConnector = NetworkSocketConnector(),
        pathWatcher: any PathWatching = NetworkPathWatcher(),
        discovery: any BridgeDiscovering = BonjourBridgeDiscovery(), device: DeviceDescription = .current,
        configuration: Configuration = Configuration(), clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        (updates, sink) = AsyncStream<ClientUpdate>.makeStream(bufferingPolicy: .unbounded)
        self.keyProvider = keys
        self.pairingReason = pairingReason
        self.unlockReason = unlockReason
        self.connector = connector
        self.pathWatcher = pathWatcher
        self.discovery = discovery
        self.device = device
        self.configuration = configuration
        self.clock = clock
    }

    deinit {
        sink.finish()
    }

    /// The latest status (also sent as `.status` updates).
    public var connectionStatus: ConnectionStatus { status }

    // MARK: - RemoteClient

    public func connect(to mac: PairedMac) async {
        if running, let current = self.mac, current.bridgeID == mac.bridgeID, current.deviceID == mac.deviceID,
            current.pin == mac.pin
        {
            self.mac = mac  // newer endpoints apply to the next race
            // Asked again while waiting out a backoff step (back in the foreground): try now.
            if active == nil, attemptTask == nil, deviceKeys != nil {
                failures = 0
                startAttempt()
            }
            return
        }
        let sockets = teardown(keepWatchingPath: false)
        closeLater(sockets)
        session += 1
        let session = self.session
        self.mac = mac
        deviceKeys = nil
        problem = nil
        running = true
        failures = 0
        hasConnected = false
        if resumeBridgeID != mac.bridgeID {
            resumeBridgeID = mac.bridgeID
            resumePoint = nil
        }
        publish()

        let loaded: DeviceKeys?
        do {
            loaded = try await keyProvider.keys(for: mac.bridgeID)
        } catch {
            guard session == self.session else { return }
            Self.log.error("keys unreadable")
            fail(.other("keys_unavailable"))
            return
        }
        guard session == self.session else { return }
        guard let loaded else {
            fail(.unknownDevice)
            return
        }
        deviceKeys = loaded
        watchPath()
        startAttempt()
    }

    public func disconnect() async {
        let sockets = teardown(keepWatchingPath: false)
        problem = nil
        publish()
        for socket in sockets { await socket.close() }
        await keyProvider.endApprovalWindow()  // the Face ID of a moment ago covers no approval after the app is away (S-14)
    }

    /// Forgets a Mac on this phone: disconnects if it is the one in use, deletes its pairing keys and the resume point.
    /// (Removing this phone from the Mac is `remote.revoke_device`, called before this while still connected.)
    public func forget(_ mac: PairedMac) async {
        if self.mac?.bridgeID == mac.bridgeID {
            let sockets = teardown(keepWatchingPath: false)
            problem = nil
            self.mac = nil
            deviceKeys = nil
            publish()
            for socket in sockets { await socket.close() }
        }
        if resumeBridgeID == mac.bridgeID {
            resumeBridgeID = nil
            resumePoint = nil
            setUnlocked(until: nil)
        }
        do {
            try await keyProvider.deleteKeys(for: mac.bridgeID)
        } catch {
            Self.log.error("pairing keys not deleted")
        }
    }

    public func call(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        guard running else { throw RemoteCallError.notConnected }
        let isRead = Self.readMethods.contains(method)
        let idem = isRead ? nil : Self.makeIdem()
        do {
            return try await submit(method: method, params: params, idem: idem)
        } catch RemoteCallError.refused(let refusal) where refusal.code == "unlock_required" {
            setUnlocked(until: nil)
            guard let unlockReason else { throw RemoteCallError.refused(refusal) }
            try await unlock(reason: unlockReason)
            // Once more with the same idem: if a lost first try did run, the bridge answers with its result.
            return try await submit(method: method, params: params, idem: idem)
        }
    }

    public func callElevated(_ method: String, _ params: JSONValue, reason: String) async throws -> JSONValue {
        guard running else { throw RemoteCallError.notConnected }
        let paramsJSON: String
        do {
            paramsJSON = try FrameCodec.jsonText(params)
        } catch {
            throw RemoteCallError.transport("bad_params")
        }
        let id = makeRequestID()
        let idem = Self.makeIdem()  // every elevated call acts (v0.3 item 4), and T_proof names it
        var firstEpoch: String?
        var sends = 0
        var signings = 0
        while true {
            // The proof names the connection (its nonce and epoch), so it is signed once connected, and signed again
            // for a new connection.
            let connection = try await waitForActive()
            if let firstEpoch, firstEpoch != connection.welcome.epoch {
                throw RemoteCallError.transport("bridge_restarted")
            }
            guard let mac, let deviceKeys, signings < 4 else { throw RemoteCallError.transport("connection_lost") }
            signings += 1
            func signed(at timestamp: Int64) async throws -> Data {
                let transcript = try SignedTranscript.proof(
                    bridgeID: mac.bridgeID, deviceID: mac.deviceID, epoch: connection.welcome.epoch,
                    nonce: connection.nonce, requestID: id, idem: idem, method: method, paramsJSON: paramsJSON,
                    timestamp: timestamp)
                do {
                    return try await deviceKeys.approve.sign(transcript, reason: reason)
                } catch {
                    throw Self.callError(for: error)
                }
            }
            var timestamp = Int64((clock().timeIntervalSince1970 * 1000).rounded())
            var signature = try await signed(at: timestamp)
            let now = Int64((clock().timeIntervalSince1970 * 1000).rounded())
            if now - timestamp > 20_000 {
                // Face ID took long and the bridge allows 60 s: sign the current time (Face ID's 30 s reuse covers it).
                timestamp = now
                signature = try await signed(at: timestamp)
            }
            guard active === connection else { continue }  // the connection changed while Face ID was up
            let frame = RequestFrame(
                id: id, method: method, paramsJSON: paramsJSON,
                proof: RequestFrame.Proof(ts: timestamp, sig: Base64URL.encode(signature)), idem: idem)
            do {
                let result = try await submit(
                    frame, kind: .elevated, epoch: connection.welcome.epoch, boundTo: connection)
                // Every accepted proof unlocks acting (C1); `remote.unlock` may say for how long.
                let seconds =
                    (method == "remote.unlock" ? result["unlock_seconds"]?.int : nil)
                    ?? connection.welcome.unlockSeconds ?? Self.defaultUnlockSeconds
                setUnlocked(until: Date(timeIntervalSince1970: Double(timestamp) / 1000 + Double(seconds)))
                return result
            } catch let resign as ResignNeeded where resign.wasSent {
                // Sent, then the connection dropped before the answer: once more, in the same epoch only.
                firstEpoch = connection.welcome.epoch
                sends += 1
                guard sends < 2 else { throw RemoteCallError.transport("connection_lost") }
            } catch is ResignNeeded {
                continue  // never sent: sign for the next connection
            }
        }
    }

    /// Unlocks acting on the Mac (contract C1): asks for Face ID with `reason` and sends `remote.unlock`. Until when
    /// is `unlockedUntil`, also reported as `ClientUpdate.unlocked(until:)`. Callers that arrive while an unlock is
    /// under way share it (one Face ID).
    public func unlock(reason: String) async throws {
        if let unlocking { return try await unlocking.value }
        let task = Task { () async throws -> Void in
            _ = try await self.callElevated("remote.unlock", .object([:]), reason: reason)
        }
        unlocking = task
        defer { unlocking = nil }
        try await task.value
    }

    /// Ends this phone's unlock now (S-05), for when the app goes to the background or its own lock engages:
    /// `unlockedUntil` is cleared first, so the screens never claim an unlock that is ending, and then, if the connected
    /// bridge offers `remote.lock`, it is asked to end the device's unlock at once. That call is brief
    /// (`Configuration.lockTimeout`) and its failure is ignored: a bridge also ends the unlock when the device's last
    /// connection closes. A bridge without `remote.lock` is not asked, and keeps its old behaviour.
    public func lock() async {
        let offered = active?.welcome.methods.contains(RemoteContract.lockMethod) ?? false
        setUnlocked(until: nil)
        await keyProvider.endApprovalWindow()  // and the Face ID that covers the next approvals for 30 s (S-14)
        guard running, offered else { return }
        let frame = RequestFrame(id: makeRequestID(), method: RemoteContract.lockMethod, params: .object([:]), idem: nil)
        _ = try? await submit(frame, kind: .read, epoch: nil, boundTo: nil, timeout: configuration.lockTimeout)
    }

    /// Until when calls that act are unlocked (C1), as far as this phone knows: the last Face ID proof the bridge
    /// accepted plus `welcome.unlock_seconds` (15 minutes when it does not say). Nil before the first, once it lapses,
    /// after an `unlock_required` refusal, and after the bridge restarted.
    public var unlockedUntil: Date? { unlockedUntilDate }

    /// Records the unlock, tells the store, and arranges to tell it again when the unlock lapses.
    private func setUnlocked(until date: Date?) {
        let lapsed = date.map { $0 <= clock() } ?? false
        let value = lapsed ? nil : date
        unlockLapse?.cancel()
        unlockLapse = nil
        if let value {
            let delay = value.timeIntervalSince(clock())
            unlockLapse = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self.setUnlocked(until: nil)
            }
        }
        guard value != unlockedUntilDate else { return }
        unlockedUntilDate = value
        sink.yield(.unlocked(until: value))
    }

    public func pair(_ link: PairingLink, deviceName: String) async throws -> PairedMac {
        try await pair(link, deviceName: deviceName, showingCode: { _ in })
    }

    /// Pairs with a Mac from the link it showed. Once `pair` has gone out, `showingCode` gets the six digits the Mac
    /// shows too (X-1): the person checks that they match and confirms on the Mac, which sends `paired` only then. It
    /// can take up to two minutes (`Configuration.pairingConfirmationTimeout`). Cancelling the calling task, which is
    /// the person leaving, throws `cancelledByPerson` and keeps nothing.
    public func pair(
        _ link: PairingLink, deviceName: String, showingCode: @escaping @Sendable (PairingCode) -> Void
    ) async throws -> PairedMac {
        let fresh: DeviceKeys
        do {
            fresh = try await keyProvider.makeKeys()
        } catch {
            throw Self.callError(for: error)
        }
        let established: Handshake.Established
        do {
            established = try await Handshake.establish(
                bridgeID: link.bridgeID, pin: link.pin, endpoints: link.endpoints,
                answer: .pair(
                    code: link.code, keys: fresh, device: device.pairDevice(named: deviceName),
                    reason: pairingReason(link.macName), showingCode: showingCode),
                connector: connector, raceDelay: configuration.raceDelay, readTimeout: configuration.readTimeout,
                confirmationTimeout: configuration.pairingConfirmationTimeout, pingInterval: configuration.pingInterval)
        } catch {
            Self.log.notice("pairing refused or failed")
            if Task.isCancelled { throw RemoteCallError.cancelledByPerson }
            throw Self.callError(for: error)
        }
        guard let deviceID = established.pairedDeviceID, !deviceID.isEmpty else {
            await established.socket.close()
            throw RemoteCallError.transport("protocol")
        }
        do {
            try await keyProvider.save(fresh, for: link.bridgeID)
        } catch {
            await established.socket.close()
            throw Self.callError(for: error)
        }
        // The pairing connection has done its job; connect(to:) opens the working one.
        await established.socket.close()
        if resumeBridgeID == link.bridgeID { resumePoint = nil }
        // The bridge's own name for the Mac, as one plain line (S-08).
        let bridgeName = DisplayText.line(established.welcome.bridge?.name ?? "", limit: PairingLink.maximumNameLength)
        Self.log.notice("paired via \(established.endpoint.routeKind.rawValue, privacy: .public)")
        return PairedMac(
            bridgeID: link.bridgeID, name: bridgeName.isEmpty ? link.macName : bridgeName, deviceID: deviceID,
            pin: link.pin, endpoints: link.endpoints, pairedAt: clock())
    }

    // MARK: - Getting connected

    private func startAttempt() {
        guard running, let mac, let deviceKeys, attemptTask == nil else { return }
        retryTask?.cancel()
        retryTask = nil
        retryAt = nil
        attemptID += 1
        let attemptID = self.attemptID
        let session = self.session
        let resume = resumeBridgeID == mac.bridgeID ? resumePoint : nil
        let answer = Handshake.Answer.hello(
            deviceID: mac.deviceID, deviceKey: deviceKeys.device, resume: resume, app: device.app)
        let connector = self.connector
        let raceDelay = configuration.raceDelay
        let readTimeout = configuration.readTimeout
        let endpoints = mac.endpoints + discovered  // the race drops duplicates
        let started = ContinuousClock.now
        attemptTask = Task {
            let result: Result<Handshake.Established, any Error>
            do {
                result = .success(
                    try await Handshake.establish(
                        bridgeID: mac.bridgeID, pin: mac.pin, endpoints: endpoints, answer: answer,
                        connector: connector, raceDelay: raceDelay, readTimeout: readTimeout))
            } catch {
                result = .failure(error)
            }
            await self.attemptFinished(
                result, attemptID: attemptID, session: session, took: ContinuousClock.now - started)
        }
        publish()
    }

    private func attemptFinished(
        _ result: Result<Handshake.Established, any Error>, attemptID: Int, session: Int, took: Duration
    ) async {
        guard session == self.session, attemptID == self.attemptID else {
            if case .success(let established) = result { await established.socket.close() }
            return
        }
        attemptTask = nil
        switch result {
        case .success(let established):
            Self.log.notice(
                "connected via \(established.endpoint.routeKind.rawValue, privacy: .public) in \(Int(took.inMilliseconds)) ms"
            )
            activate(established)
        case .failure(let error):
            if let problem = Self.problem(for: error) {
                Self.log.notice("connection refused: \(String(describing: problem), privacy: .public)")
                fail(problem)
            } else if active != nil {
                Self.log.info("re-race failed; keeping the current connection")
            } else {
                Self.log.info("connection attempt failed")
                scheduleRetry()
            }
        }
    }

    private func activate(_ established: Handshake.Established) {
        guard let mac else { return }
        let welcome = established.welcome
        nextConnectionID += 1
        let (outbox, outboxContinuation) = AsyncStream<String>.makeStream(bufferingPolicy: .unbounded)
        let connection = Connection(established, id: nextConnectionID, outbox: outboxContinuation)

        let resumed: Bool
        if welcome.resumed, resumeBridgeID == mac.bridgeID, let point = resumePoint, point.epoch == welcome.epoch,
            point.seq <= welcome.seq
        {
            resumed = true
        } else {
            resumed = false
            if resumePoint?.epoch != welcome.epoch { setUnlocked(until: nil) }  // a restarted bridge forgot the unlock
            resumePoint = HelloFrame.Resume(epoch: welcome.epoch, seq: welcome.seq)
        }
        resumeBridgeID = mac.bridgeID

        let previous = active
        active = connection
        failures = 0
        hasConnected = true
        roundTrip = nil
        if let previous { retire(previous) }

        connection.tasks = [reader(for: connection), writer(for: connection, outbox: outbox), pinger(for: connection)]

        let bridgeName = DisplayText.line(welcome.bridge?.name ?? "", limit: PairingLink.maximumNameLength)
        sink.yield(
            .welcome(
                BridgeInfo(
                    bridgeVersion: welcome.bridge?.version ?? "",
                    macName: bridgeName.isEmpty ? mac.name : bridgeName,
                    pebbleRunning: welcome.pebble?.running ?? false, pebbleVersion: welcome.pebble?.version,
                    methods: Set(welcome.methods), elevated: Set(welcome.elevated), resumed: resumed,
                    unlockSeconds: welcome.unlockSeconds)))
        publish()
        if !resumed { sink.yield(.resyncNeeded) }

        // Calls that waited for a connection, oldest first; then elevated calls waiting to sign.
        for call in calls.values.filter({ $0.sentOn == nil }).sorted(by: { $0.number < $1.number }) {
            dispatch(call.id)
        }
        let waiters = activeWaiters
        activeWaiters = [:]
        for waiter in waiters.values { waiter.resume() }
    }

    private func scheduleRetry() {
        guard running, attemptTask == nil, retryTask == nil else { return }
        failures += 1
        let delay = configuration.backoff.delay(attempt: failures)
        retryAt = clock().addingTimeInterval(delay.inSeconds)
        let session = self.session
        retryTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.retryFired(session: session)
        }
        publish()
    }

    private func retryFired(session: Int) {
        guard session == self.session, running else { return }
        retryTask = nil
        retryAt = nil
        startAttempt()
    }

    private func watchPath() {
        guard !watchingPath, let bridgeID = mac?.bridgeID else { return }
        watchingPath = true
        pathWatcher.start { [weak self] in
            Task { await self?.pathChanged() }
        }
        discovery.start(bridgeID: bridgeID) { [weak self] endpoints in
            Task { await self?.bonjourFound(endpoints, for: bridgeID) }
        }
    }

    /// Bonjour found the Mac's bridge at these LAN endpoints. A new one is raced at once if the client is waiting to
    /// retry (the Mac's address changed); otherwise the next race includes it.
    func bonjourFound(_ endpoints: [Endpoint], for bridgeID: String) {
        guard let mac, mac.bridgeID == bridgeID else { return }
        let known = Set(mac.endpoints + discovered)
        // Anyone on the LAN can advertise this bridge's id (it is in the TXT record, C6): race only a few well-formed
        // addresses, never hundreds at once (security review 2026-10-30, S-07). The pin still decides who answers.
        var seen = Set(mac.endpoints)
        discovered = Array(
            endpoints.filter { Endpoint.isValidHost($0.host) && seen.insert($0).inserted }
                .prefix(Self.maximumDiscoveredEndpoints))
        guard discovered.contains(where: { !known.contains($0) }) else { return }
        Self.log.info("Bonjour found the Mac at a new address")
        if problem == .pinMismatch || (running && active == nil) { pathChanged() }
    }

    /// The phone's network changed: race again now. While connected, the old connection carries on until a new
    /// one is welcomed (which may be a better route: LAN once home); if the race fails, nothing is lost.
    func pathChanged() {
        if problem == .pinMismatch, let mac {
            // Another network may reach the real Mac: try again from the start.
            problem = nil
            session += 1
            running = true
            failures = 0
            self.mac = mac
            publish()
            startAttempt()
            return
        }
        guard running else { return }
        failures = 0
        guard attemptTask == nil else { return }
        startAttempt()
    }

    // MARK: - The connection in use

    private final class Connection {
        let id: Int
        let socket: any FrameSocket
        let endpoint: Endpoint
        let welcome: WelcomeFrame
        /// The challenge's nonce: every proof on this connection names it.
        let nonce: String
        let outbox: AsyncStream<String>.Continuation
        var tasks: [Task<Void, Never>] = []

        init(_ established: Handshake.Established, id: Int, outbox: AsyncStream<String>.Continuation) {
            self.id = id
            self.socket = established.socket
            self.endpoint = established.endpoint
            self.welcome = established.welcome
            self.nonce = established.nonce
            self.outbox = outbox
        }

        /// The bridge offers `remote.lock`, so it ends a device's unlock when the device's last connection closes (S-05).
        var endsUnlockWhenClosed: Bool { welcome.methods.contains(RemoteContract.lockMethod) }

        func stop() {
            outbox.finish()
            for task in tasks { task.cancel() }
        }
    }

    private func reader(for connection: Connection) -> Task<Void, Never> {
        let socket = connection.socket
        let id = connection.id
        return Task {
            while true {
                let text: String
                do {
                    text = try await socket.receive()
                } catch {
                    break
                }
                self.received(text, on: id)
            }
            self.connectionEnded(id)
        }
    }

    private func writer(for connection: Connection, outbox: AsyncStream<String>) -> Task<Void, Never> {
        let socket = connection.socket
        return Task {
            for await text in outbox {
                do {
                    try await socket.send(text)
                } catch {
                    // The reader sees the connection end and the client reconnects.
                    await socket.close()
                    return
                }
            }
        }
    }

    private func pinger(for connection: Connection) -> Task<Void, Never> {
        let socket = connection.socket
        let id = connection.id
        let interval = configuration.pingInterval
        let timeout = configuration.pingTimeout
        return Task {
            var first = true
            while !Task.isCancelled {
                if !first { try? await Task.sleep(for: interval) }
                first = false
                guard !Task.isCancelled else { return }
                let start = ContinuousClock.now
                let answered = await Self.ping(socket, timeout: timeout)
                guard !Task.isCancelled else { return }
                guard answered else {
                    Self.log.notice("ping unanswered; reconnecting")
                    await socket.close()
                    return
                }
                self.measured(ContinuousClock.now - start, on: id)
            }
        }
    }

    private static func ping(_ socket: any FrameSocket, timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await socket.ping()) != nil }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let answered = await group.next() ?? false
            group.cancelAll()
            return answered
        }
    }

    private func measured(_ roundTrip: Duration, on connectionID: Int) {
        guard active?.id == connectionID else { return }
        self.roundTrip = (roundTrip.inMilliseconds * 10).rounded() / 10
        publish()
    }

    private func received(_ text: String, on connectionID: Int) {
        guard let connection = active, connection.id == connectionID else { return }
        let frame: Frame
        do {
            frame = try FrameCodec.decode(text)
        } catch {
            Self.log.error("unreadable frame: \(String(describing: error), privacy: .public)")
            return
        }
        switch frame {
        case .response(let response):
            resolve(response)
        case .event(let event):
            deliver(event, epoch: connection.welcome.epoch)
        case .bye(let bye):
            byeReceived(bye, on: connection)
        default:
            break  // nothing else is expected after welcome; a newer bridge's frames are ignored
        }
    }

    private func deliver(_ event: PebbleEvent, epoch: String) {
        guard let point = resumePoint, point.epoch == epoch else { return }
        guard event.seq > point.seq else { return }  // seen already (a replay overlapping what arrived live)
        if event.seq > point.seq + 1 {
            Self.log.notice("events missing between \(point.seq) and \(event.seq); refetching")
            sink.yield(.resyncNeeded)
        }
        resumePoint = HelloFrame.Resume(epoch: epoch, seq: event.seq)
        sink.yield(.event(event))
    }

    private func byeReceived(_ bye: ByeFrame, on connection: Connection) {
        Self.log.notice("bye \(bye.code.rawValue, privacy: .public)")
        if bye.code == .replaced, attemptTask != nil {
            // Our own re-race took over; its welcome is on the way.
            drop(connection, keepingUnlock: true)
            return
        }
        if let problem = Self.problem(for: bye) {
            fail(problem)
        } else {
            drop(connection)
            if attemptTask == nil { scheduleRetry() }
        }
    }

    private func connectionEnded(_ connectionID: Int) {
        guard let connection = active, connection.id == connectionID else { return }
        Self.log.notice("connection lost")
        drop(connection)
        if attemptTask == nil { scheduleRetry() }
    }

    /// The active connection is gone. A bridge that offers `remote.lock` ends a device's unlock when its last connection
    /// closes (S-05), so the phone stops claiming it too, unless a newer connection of this phone is taking over
    /// (`keepingUnlock`): then the device never had none, and the unlock carries on there.
    private func drop(_ connection: Connection, keepingUnlock: Bool = false) {
        guard active?.id == connection.id else { return }
        active = nil
        roundTrip = nil
        if !keepingUnlock, connection.endsUnlockWhenClosed { setUnlocked(until: nil) }
        retire(connection)
        publish()
    }

    /// Stops using a connection: closes it, and puts its unanswered calls back to wait for the next one (or fails
    /// them, per the rules in the type's description).
    private func retire(_ connection: Connection) {
        connection.stop()
        closeLater([connection.socket])
        for id in calls.keys.sorted() where calls[id]?.sentOn == connection.id {
            requeue(id)
        }
    }

    // MARK: - Calls

    /// An elevated call's proof names a connection that is gone: sign again for the next one.
    private struct ResignNeeded: Error {
        /// The call went out before the connection was lost (so its answer was lost).
        var wasSent: Bool
    }

    private struct PendingCall {
        enum Kind { case read, idempotent, elevated }
        let number: Int
        let id: String
        let method: String
        let text: String
        let kind: Kind
        /// The only epoch the call may be sent in: an elevated call's proof epoch, or where an idempotent call was
        /// first sent (the bridge's memory of `idem` keys does not outlive a restart).
        var epoch: String?
        var sentOn: Int?
        /// An elevated call goes only on the connection its proof names.
        var boundTo: Int?
        /// How long this call waits for its answer, when not the configuration's `requestTimeout` (`lock()`).
        var timeout: Duration?
        var sends = 0
        /// How many times the bridge's burst limit refused it (`sendAgainLater`).
        var rateRetries = 0
        var timer: Task<Void, Never>?
        var timerGeneration = 0
        let started: ContinuousClock.Instant
        let continuation: CheckedContinuation<JSONValue, any Error>
    }

    /// A normal call: a read, or a call that acts with its `idem`.
    private func submit(method: String, params: JSONValue, idem: String?) async throws -> JSONValue {
        let frame = RequestFrame(id: makeRequestID(), method: method, params: params, idem: idem)
        return try await submit(frame, kind: idem == nil ? .read : .idempotent, epoch: nil, boundTo: nil)
    }

    private func submit(
        _ frame: RequestFrame, kind: PendingCall.Kind, epoch: String?, boundTo connection: Connection?,
        timeout: Duration? = nil
    ) async throws -> JSONValue {
        let text: String
        do {
            text = try FrameCodec.encodeText(.request(frame))
        } catch {
            throw RemoteCallError.transport("bad_params")
        }
        let limit = active?.welcome.limits?.maxRequest ?? WelcomeFrame.Limits.contract.maxRequest
        guard text.utf8.count <= limit else { throw RemoteCallError.transport("too_large") }
        guard running else { throw RemoteCallError.notConnected }
        nextCallNumber += 1
        let number = nextCallNumber
        return try await withCheckedThrowingContinuation { continuation in
            calls[frame.id] = PendingCall(
                number: number, id: frame.id, method: frame.method, text: text, kind: kind, epoch: epoch,
                boundTo: connection?.id, timeout: timeout, started: .now, continuation: continuation)
            dispatch(frame.id)
        }
    }

    /// Sends a waiting call on the active connection, or leaves it waiting for one.
    private func dispatch(_ id: String) {
        guard var call = calls[id] else { return }
        if let bound = call.boundTo, active?.id != bound {
            finish(id, .failure(ResignNeeded(wasSent: false)))
            return
        }
        guard let active else {
            armTimer(id)
            return
        }
        if let epoch = call.epoch, epoch != active.welcome.epoch {
            finish(id, .failure(RemoteCallError.transport("bridge_restarted")))
            return
        }
        if call.kind == .idempotent, call.epoch == nil { call.epoch = active.welcome.epoch }
        call.sentOn = active.id
        call.sends += 1
        calls[id] = call
        armTimer(id)
        active.outbox.yield(call.text)
    }

    private func requeue(_ id: String) {
        guard var call = calls[id] else { return }
        if call.kind == .elevated {
            // Its proof names the lost connection: callElevated signs again for the next (once).
            finish(id, .failure(ResignNeeded(wasSent: true)))
            return
        }
        guard call.sends < 2 else {
            finish(id, .failure(RemoteCallError.transport("connection_lost")))
            return
        }
        call.sentOn = nil
        calls[id] = call
        armTimer(id)
    }

    private func resolve(_ response: ResponseFrame) {
        guard calls[response.id] != nil else { return }  // a late answer to a call that already timed out
        switch response.outcome {
        case .success(let result):
            finish(response.id, .success(result))
        case .failure(let error, let code):
            if code == BridgeErrorCode.rateLimited.rawValue, sendAgainLater(response.id) { return }
            finish(response.id, .failure(RemoteCallError.refused(PersonFacingError(message: error, code: code))))
        }
    }

    /// How many times a call the bridge's burst limit refused goes again before the refusal reaches its caller.
    static let rateLimitRetries = 4

    /// The bridge's burst limit refused the call before acting on it (3.9; Pebble's bridge takes its token before it
    /// records the request id or looks at the proof, the unlock or `idem`), so nothing ran and nothing was kept: the
    /// same frame goes again on the same connection after a pause (`Configuration.rateLimitPause`, doubling, with
    /// jitter). A connection lost meanwhile requeues the call as it would any other. False when the call is given up:
    /// tried `rateLimitRetries` times, or `lock()`'s brief call.
    private func sendAgainLater(_ id: String) -> Bool {
        guard var call = calls[id], call.timeout == nil, let connection = call.sentOn,
            call.rateRetries < Self.rateLimitRetries
        else { return false }
        call.rateRetries += 1
        call.sends -= 1  // the bridge never read that send
        calls[id] = call
        let retries = call.rateRetries
        let seconds =
            configuration.rateLimitPause.inSeconds * Double(1 << (retries - 1)) * Double.random(in: 1...1.5)
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            self.sendAgain(id, on: connection, retries: retries)
        }
        return true
    }

    /// Sends a call `sendAgainLater` held, unless it ended or moved meanwhile (answered, timed out, or requeued by a
    /// lost connection, which sends it again itself).
    private func sendAgain(_ id: String, on connection: Int, retries: Int) {
        guard let call = calls[id], call.sentOn == connection, call.rateRetries == retries else { return }
        dispatch(id)
    }

    private func finish(_ id: String, _ result: Result<JSONValue, any Error>) {
        guard let call = calls.removeValue(forKey: id) else { return }
        call.timer?.cancel()
        let millis = Int((ContinuousClock.now - call.started).inMilliseconds)
        switch result {
        case .success:
            Self.log.info("\(call.method, privacy: .public) answered in \(millis) ms")
        case .failure(let error):
            Self.log.info("\(call.method, privacy: .public) failed after \(millis) ms: \(Self.code(of: error), privacy: .public)")
        }
        call.continuation.resume(with: result)
    }

    private func armTimer(_ id: String) {
        guard var call = calls[id] else { return }
        call.timer?.cancel()
        call.timerGeneration += 1
        let generation = call.timerGeneration
        let timeout = call.timeout ?? configuration.requestTimeout
        call.timer = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.timerFired(id, generation: generation)
        }
        calls[id] = call
    }

    private func timerFired(_ id: String, generation: Int) {
        guard let call = calls[id], call.timerGeneration == generation else { return }
        finish(id, .failure(call.sentOn == nil ? RemoteCallError.notConnected : RemoteCallError.timedOut))
    }

    private func waitForActive() async throws -> Connection {
        if let active { return active }
        guard running else { throw RemoteCallError.notConnected }
        nextWaiterID += 1
        let waiterID = nextWaiterID
        let timeout = configuration.requestTimeout
        let timer = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self.waiterTimedOut(waiterID)
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { activeWaiters[waiterID] = $0 }
        guard let active else { throw RemoteCallError.notConnected }
        return active
    }

    private func waiterTimedOut(_ waiterID: Int) {
        activeWaiters.removeValue(forKey: waiterID)?.resume(throwing: RemoteCallError.notConnected)
    }

    /// Unique for the client's life, so also within each connection, and a call sent again keeps its id.
    private func makeRequestID() -> String {
        nextRequestNumber += 1
        return "r\(nextRequestNumber)"
    }

    private static func makeIdem() -> String {
        UUID().uuidString.lowercased()
    }

    // MARK: - Ending

    /// Stops everything in the session and returns the sockets to close. Pending calls fail as `notConnected`. The
    /// session's unlock ends with it (S-05): the screens never claim one for a connection that is gone.
    private func teardown(keepWatchingPath: Bool) -> [any FrameSocket] {
        session += 1
        running = false
        setUnlocked(until: nil)
        attemptTask?.cancel()
        attemptTask = nil
        retryTask?.cancel()
        retryTask = nil
        retryAt = nil
        if !keepWatchingPath, watchingPath {
            watchingPath = false
            pathWatcher.stop()
            discovery.stop()
            discovered = []
        }
        var sockets: [any FrameSocket] = []
        if let active {
            active.stop()
            sockets.append(active.socket)
        }
        active = nil
        roundTrip = nil
        for id in calls.keys.sorted() {
            finish(id, .failure(RemoteCallError.notConnected))
        }
        let waiters = activeWaiters
        activeWaiters = [:]
        for waiter in waiters.values { waiter.resume(throwing: RemoteCallError.notConnected) }
        return sockets
    }

    /// A refusal that needs the person: stop reconnecting and say why. A pin mismatch keeps watching the network,
    /// since another network may reach the real Mac.
    private func fail(_ problem: ConnectionProblem) {
        let sockets = teardown(keepWatchingPath: problem == .pinMismatch)
        self.problem = problem
        publish()
        closeLater(sockets)
    }

    private nonisolated func closeLater(_ sockets: [any FrameSocket]) {
        guard !sockets.isEmpty else { return }
        Task {
            for socket in sockets { await socket.close() }
        }
    }

    private func publish() {
        let phase: ConnectionPhase
        if let problem {
            phase = .failed(problem)
        } else if !running {
            phase = .idle
        } else if active != nil {
            phase = .connected
        } else if retryTask != nil {
            phase = .reconnecting(attempt: failures, nextTry: retryAt)
        } else if hasConnected || failures > 0 {
            phase = .reconnecting(attempt: max(failures, 1), nextTry: nil)
        } else {
            phase = .connecting
        }
        let next = ConnectionStatus(
            phase: phase, route: active?.endpoint.routeKind, endpoint: active?.endpoint,
            roundTrip: active == nil ? nil : roundTrip, since: phase == status.phase ? status.since : clock())
        guard next != status else { return }
        status = next
        sink.yield(.status(next))
    }

    // MARK: - Errors

    /// A refusal that needs the person, or nil for a failure worth retrying.
    static func problem(for error: any Error) -> ConnectionProblem? {
        if let failure = error as? Handshake.Failure {
            switch failure {
            case .bye(let bye): return problem(for: bye)
            case .unreachable(let pinMismatch): return pinMismatch ? .pinMismatch : nil
            // Only the person can turn the switch on; the app connects again when it comes back from Settings.
            case .localNetworkDenied: return .localNetworkDenied
            case .wrongBridge: return .unknownDevice
            case .badVersion: return .bridgeTooOld
            case .protocolViolation: return nil
            // Only a pairing waits for the person, and a pairing never reconnects.
            case .notConfirmed: return nil
            }
        }
        if error is RemoteKeyError { return .other("keys_unavailable") }
        return nil
    }

    static func problem(for bye: ByeFrame) -> ConnectionProblem? {
        switch bye.code {
        case .revoked: return .revoked
        case .unknownDevice: return .unknownDevice
        case .badVersion: return .bridgeTooOld
        case .busy: return nil
        // A frame the bridge could not read (v0.3 item 6): reconnect; the call that caused it is sent once more at
        // most, then fails.
        case ByeCode(rawValue: "too_large"): return nil
        default: return .other(bye.error.flatMap { $0.isEmpty ? nil : $0 } ?? bye.code.rawValue)
        }
    }

    static func callError(for error: any Error) -> RemoteCallError {
        if let error = error as? RemoteCallError { return error }
        // The person leaving a pairing that waits for the Mac, or a Face ID they walked away from.
        if error is CancellationError { return .cancelledByPerson }
        if let failure = error as? Handshake.Failure {
            switch failure {
            case .bye(let bye) where bye.code.rawValue == "bad_code":
                // The Mac's person cancelled, or two minutes passed without an answer (X-1), or the link was already
                // used or had expired (v0.3 item 1): the phone cannot tell which, and the screens say what to do.
                return .transport("bad_code")
            case .bye(let bye):
                return .refused(PersonFacingError(message: bye.error ?? "", code: bye.code.rawValue))
            case .unreachable(let pinMismatch): return .transport(pinMismatch ? "pin_mismatch" : "unreachable")
            case .localNetworkDenied: return .transport("local_network")
            case .wrongBridge: return .transport("wrong_bridge")
            case .badVersion: return .transport("bad_version")
            case .protocolViolation: return .transport("protocol")
            case .notConfirmed: return .transport("not_confirmed")
            }
        }
        if let keyError = error as? RemoteKeyError {
            return .transport(keyError == .biometryUnavailable ? "biometry_unavailable" : "keys_unavailable")
        }
        return .transport("protocol")
    }

    /// A content-free name for a failure, for the log.
    static func code(of error: any Error) -> String {
        switch error as? RemoteCallError {
        case .refused(let refusal): "refused \(refusal.code ?? "-")"
        case .notConnected: "not_connected"
        case .timedOut: "timed_out"
        case .cancelledByPerson: "cancelled"
        case .transport(let code): code
        case .notImplemented: "not_implemented"
        case nil: "error"
        }
    }
}

extension LiveClient {
    /// The client the app uses: keys in the Secure Enclave on a real iPhone (approvals need Face ID), or software keys
    /// kept in the Keychain where there is no Secure Enclave (the simulator). `unlockReason` is the Face ID sentence
    /// for the unlock (C1); without it, `unlock_required` refusals reach the store.
    public static func standard(
        pairingReason: @escaping @Sendable (String) -> String, unlockReason: String? = nil
    ) -> LiveClient {
        LiveClient(keys: keyProvider(simulator: runsInSimulator), pairingReason: pairingReason, unlockReason: unlockReason)
    }

    /// The app's keys: in the Secure Enclave, whose approve key asks for Face ID. Software keys, which never ask, only in
    /// the simulator, which has no Secure Enclave. On a real iPhone whose Enclave cannot make keys, pairing fails in
    /// words (`keys_unavailable`) instead of quietly pairing keys that approve without Face ID (security review
    /// 2026-10-30, S-10).
    static func keyProvider(simulator: Bool) -> any KeyProvider {
        simulator ? SoftwareKeyProvider(store: KeychainSecretStore(service: "PebbleRemote.keys")) : SecureEnclaveKeyProvider()
    }

    static var runsInSimulator: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }
}
