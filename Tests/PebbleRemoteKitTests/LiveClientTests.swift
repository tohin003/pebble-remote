import CryptoKit
import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane B: LiveClient against the in-memory bridge (FakeBridge.swift): handshake, correlation, idempotent retries,
// elevated calls, events and resume, refusals, racing, heartbeats, path changes and pairing.

/// A connected-or-connectable client with everything it talks to.
struct LiveHarness {
    static let lan = Endpoint(host: "192.168.1.20", port: 47800)
    static let lanName = Endpoint(host: "studio.local", port: 47800)
    static let tailnet = Endpoint(host: "studio.tail1.ts.net", port: 47800)

    static let fast = LiveClient.Configuration(
        requestTimeout: .seconds(3), readTimeout: .seconds(2), pingInterval: .seconds(60), pingTimeout: .seconds(1),
        raceDelay: .milliseconds(150), backoff: Backoff(initial: .milliseconds(20), maximum: .milliseconds(100)))

    let bridge: FakeBridge
    let keys: RecordingKeyProvider
    let watcher: ManualPathWatcher
    let discovery: ManualDiscovery
    let client: LiveClient
    let log: UpdateLog
    let mac: PairedMac

    static func make(
        endpoints: [Endpoint] = [lan], configuration: LiveClient.Configuration = fast, register: Bool = true,
        saveKeys: Bool = true, unlockReason: String? = nil
    ) async throws -> LiveHarness {
        let bridge = FakeBridge()
        let keys = RecordingKeyProvider()
        let deviceKeys = try await keys.makeKeys()
        if saveKeys { try await keys.save(deviceKeys, for: bridge.bridgeID) }
        if register { bridge.register(deviceKeys, id: "dev-1") }
        let watcher = ManualPathWatcher()
        let discovery = ManualDiscovery()
        let client = LiveClient(
            keys: keys, pairingReason: { "Pair with \($0)" }, unlockReason: unlockReason,
            connector: FakeBridgeConnector(bridge: bridge), pathWatcher: watcher, discovery: discovery,
            device: DeviceDescription(model: "iPhone18,3", os: "iOS 26.1", app: "1.0 (1)"), configuration: configuration)
        let mac = PairedMac(
            bridgeID: bridge.bridgeID, name: "Studio Mac", deviceID: "dev-1", pin: bridge.pin, endpoints: endpoints,
            pairedAt: Date())
        return LiveHarness(
            bridge: bridge, keys: keys, watcher: watcher, discovery: discovery, client: client, log: UpdateLog(client),
            mac: mac)
    }

    func connected(times: Int = 1) async throws {
        let log = self.log
        try await eventually("connected \(times)x") { log.connectedCount >= times }
    }

    func connect() async throws {
        await client.connect(to: mac)
        try await connected()
    }

    func phase() async -> ConnectionPhase { await client.connectionStatus.phase }
}

func isUUID(_ text: String?) -> Bool {
    guard let text, let uuid = UUID(uuidString: text) else { return false }
    return uuid.uuidString.lowercased() == text
}

@Suite("Lane B: LiveClient")
struct LiveClientTests {
    // MARK: Handshake

    @Test func handshakeSignsHelloAndWelcomes() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        #expect(h.bridge.problems.isEmpty)
        let hello = try #require(h.bridge.hellos.first)
        #expect(hello.deviceID == "dev-1" && hello.resume == nil && hello.app == "1.0 (1)")
        let info = try #require(h.log.welcomes.first)
        #expect(info.macName == "Studio Mac" && info.pebbleRunning && info.pebbleVersion == "1.9.28")
        #expect(info.methods.contains("state") && info.elevated.contains("setting:permissions") && !info.resumed)
        try await eventually("the first resync") { h.log.resyncCount == 1 }  // it follows the connected status
        #expect(h.log.phases.first == .connecting)
        let status = await h.client.connectionStatus
        #expect(status.route == .lan && status.endpoint == LiveHarness.lan)
        // The first ping goes out on connecting.
        try await eventually("a round trip") { await h.client.connectionStatus.roundTrip != nil }
        await h.client.disconnect()
        #expect(await h.phase() == .idle)
        let allClosed = h.bridge.sockets.allSatisfy { $0.isClosed }
        #expect(allClosed)
    }

    @Test func callsBeforeConnectingAreRefused() async throws {
        let h = try await LiveHarness.make()
        await #expect(throws: RemoteCallError.notConnected) { try await h.client.call("state", [:]) }
    }

    @Test func missingKeysNeedPairingAgain() async throws {
        let h = try await LiveHarness.make(saveKeys: false)
        await h.client.connect(to: h.mac)
        try await eventually("failed") { await h.phase() == .failed(.unknownDevice) }
        #expect(h.bridge.opens.isEmpty)
    }

    // MARK: Calls

    @Test func answersFindTheirCallsInAnyOrder() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { _ in .silent }
        try await h.connect()
        async let first = h.client.call("get_chat", ["id": "c1"])
        async let second = h.client.call("get_chat", ["id": "c2"])
        try await eventually("two requests") { h.bridge.requests.count == 2 }
        let requests = h.bridge.requests
        let id1 = try #require(requests.first { $0.params?["id"] == "c1" }?.id)
        let id2 = try #require(requests.first { $0.params?["id"] == "c2" }?.id)
        #expect(id1 != id2)
        h.bridge.answer(id2, .success(["title": "two"]))
        h.bridge.answer(id1, .success(["title": "one"]))
        #expect(try await first == ["title": "one"])
        #expect(try await second == ["title": "two"])
    }

    @Test func idemGoesOnEveryCallThatActs() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        _ = try await h.client.call("send", ["chat_id": "c1", "text": "hi"])
        _ = try await h.client.call("state", [:])
        _ = try await h.client.call("cancel", ["chat_id": "c1"])
        _ = try await h.client.call("chat_rename", ["id": "c1", "title": "New"])
        _ = try await h.client.call("model_profiles", [:])  // not a read in C1's list, so it carries a key
        for method in ["send", "cancel", "chat_rename", "model_profiles"] {
            #expect(isUUID(h.bridge.requests(method).first?.idem), "\(method) carries idem")
        }
        #expect(h.bridge.requests("state").first?.idem == nil)
        #expect(h.bridge.requests("send").first?.params == ["chat_id": "c1", "text": "hi"])
        #expect(h.bridge.problems.isEmpty)
    }

    @Test func requestIDsUseTheContractsCharacters() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        for _ in 0..<5 { _ = try await h.client.call("state", [:]) }
        _ = try await h.client.callElevated("approve", ["id": "c1", "action_id": "a1"], reason: "Approve")
        let ids = h.bridge.requests.map(\.id)
        #expect(ids.count == 6 && Set(ids).count == 6)
        #expect(ids.allSatisfy { $0.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil })
        #expect(h.bridge.problems.isEmpty)
    }

    @Test func refusalsKeepTheBridgesWords() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { _ in .answer(.failure(error: "Pebble is not running.", code: "pebble_offline")) }
        try await h.connect()
        do {
            _ = try await h.client.call("state", [:])
            Issue.record("expected a refusal")
        } catch RemoteCallError.refused(let refusal) {
            #expect(refusal.message == "Pebble is not running." && refusal.code == "pebble_offline")
        }
    }

    @Test func unansweredCallsTimeOut() async throws {
        var configuration = LiveHarness.fast
        configuration.requestTimeout = .milliseconds(300)
        let h = try await LiveHarness.make(configuration: configuration)
        h.bridge.respond { _ in .silent }
        try await h.connect()
        await #expect(throws: RemoteCallError.timedOut) { try await h.client.call("state", [:]) }
    }

    @Test func oversizedRequestsAreNotSent() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        let big = JSONValue.string(String(repeating: "x", count: 140_000))
        await #expect(throws: RemoteCallError.transport("too_large")) {
            try await h.client.call("send", ["chat_id": "c1", "text": big])
        }
        #expect(h.bridge.requests.isEmpty)
    }

    @Test func callsWaitForAConnectionInProgress() async throws {
        let h = try await LiveHarness.make()
        h.bridge.set(.accept(after: .milliseconds(300)), for: LiveHarness.lan)
        await h.client.connect(to: h.mac)
        let result = try await h.client.call("state", [:])
        #expect(result == [:])
        #expect(h.bridge.requests("state").count == 1)
    }

    // MARK: Elevated calls

    @Test func elevatedCallsCarryParamsJSONAndAProof() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { _ in .answer(.success(["approved": true])) }
        try await h.connect()
        let result = try await h.client.callElevated(
            "approve", ["id": "c1", "action_id": "a9"], reason: "Approve: run npm test")
        #expect(result == ["approved": true])
        let request = try #require(h.bridge.requests("approve").first)
        #expect(request.paramsJSON == #"{"action_id":"a9","id":"c1"}"#)
        #expect(request.params == nil)
        #expect(isUUID(request.idem))
        #expect(h.bridge.proofsChecked == 1 && h.bridge.problems.isEmpty)
        #expect(h.keys.reasons == ["Approve: run npm test"])
    }

    @Test func aProofFromAnotherKeyIsRefused() async throws {
        let h = try await LiveHarness.make(register: false)
        // The bridge knows a different approve key for this device.
        let other = try await RecordingKeyProvider().makeKeys()
        let mine = try #require(try await h.keys.keys(for: h.bridge.bridgeID))
        h.bridge.register(DeviceKeys(device: mine.device, approve: other.approve), id: "dev-1")
        try await h.connect()
        do {
            _ = try await h.client.callElevated("approve", ["id": "c1", "action_id": "a9"], reason: "Approve")
            Issue.record("expected bad_proof")
        } catch RemoteCallError.refused(let refusal) {
            #expect(refusal.code == "bad_proof")
        }
    }

    @Test func elevatedCallsWaitToSignUntilConnected() async throws {
        let h = try await LiveHarness.make()
        h.bridge.set(.accept(after: .milliseconds(300)), for: LiveHarness.lan)
        await h.client.connect(to: h.mac)
        _ = try await h.client.callElevated("approve_simple", ["id": "c1", "action_id": "a1"], reason: "Approve")
        #expect(h.bridge.proofsChecked == 1)
    }

    // MARK: Events and resume

    @Test func eventsArriveOnceInOrderAndGapsAskForARefetch() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        h.bridge.emit("token", ["chat_id": "c1", "id": "m1", "text": "Hel"])
        h.bridge.emit("token", ["chat_id": "c1", "id": "m1", "text": "lo"])
        h.bridge.push(.event(PebbleEvent(seq: 2, name: "token", data: ["chat_id": "c1", "id": "m1", "text": "lo"])))
        h.bridge.skip(1)
        h.bridge.emit("complete", ["chat_id": "c1", "id": "m1", "seconds": 2])
        try await eventually("three events") { h.log.events.count == 3 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.log.events.map(\.seq) == [1, 2, 4])
        #expect(h.log.events.map(\.name) == ["token", "token", "complete"])
        #expect(h.log.resyncCount == 2)
        // The refetch request comes before the event after the gap.
        let order = h.log.all.compactMap { update -> String? in
            switch update {
            case .resyncNeeded: "resync"
            case .event(let event): "\(event.seq)"
            default: nil
            }
        }
        #expect(order == ["resync", "1", "2", "resync", "4"])
    }

    @Test func aDroppedConnectionResumesWithoutLosingEvents() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        for text in ["a", "b", "c"] { h.bridge.emit("token", ["chat_id": "c1", "id": "m1", "text": .string(text)]) }
        try await eventually("three events") { h.log.events.count == 3 }
        h.bridge.drop()
        h.bridge.emit("token", ["chat_id": "c1", "id": "m1", "text": "d"])
        h.bridge.emit("complete", ["chat_id": "c1", "id": "m1"])
        try await h.connected(times: 2)
        try await eventually("five events") { h.log.events.count == 5 }
        #expect(h.log.events.map(\.seq) == [1, 2, 3, 4, 5])
        #expect(h.bridge.hellos.count == 2)
        #expect(h.bridge.hellos[1].resume == HelloFrame.Resume(epoch: "e1", seq: 3))
        #expect(h.log.welcomes.last?.resumed == true)
        #expect(h.log.resyncCount == 1)
        #expect(h.log.phases.contains { if case .reconnecting = $0 { true } else { false } })
    }

    @Test func disconnectKeepsTheResumePoint() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { request in request.method == "get_chat" ? .silent : .answer(.success([:])) }
        try await h.connect()
        h.bridge.emit("run", ["chat_id": "c1", "run_id": "r1", "state": "running"])
        try await eventually("an event") { h.log.events.count == 1 }
        let pending = Task { try await h.client.call("get_chat", ["id": "c1"]) }
        try await eventually("the request") { h.bridge.requests("get_chat").count == 1 }
        await h.client.disconnect()
        await #expect(throws: RemoteCallError.notConnected) { try await pending.value }
        #expect(await h.phase() == .idle)
        h.bridge.emit("run", ["chat_id": "c1", "run_id": "r1", "state": "completed"])
        await h.client.connect(to: h.mac)
        try await eventually("the missed event") { h.log.events.count == 2 }
        #expect(h.bridge.hellos.last?.resume == HelloFrame.Resume(epoch: "e1", seq: 1))
        #expect(h.log.resyncCount == 1)
    }

    // MARK: Retries after a lost answer

    @Test func anIdempotentCallIsResentOnceWithTheSameKey() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { request in
            request.method == "send" ? .loseAnswer(.success(["message_id": "m9"])) : .answer(.success([:]))
        }
        try await h.connect()
        let result = try await h.client.call("send", ["chat_id": "c1", "text": "hi"])
        #expect(result == ["message_id": "m9"])
        let sends = h.bridge.requests("send")
        #expect(sends.count == 2)
        #expect(sends[0].idem == sends[1].idem && sends[0].id == sends[1].id)
        #expect(h.bridge.executions(of: "send") == 1)  // done once; the repeat got the first answer
    }

    @Test func aReadIsResentOnceThenGivenUp() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { request in
            request.method == "state" ? .loseAnswer(.success(["pebble": [:]])) : .answer(.success([:]))
        }
        try await h.connect()
        await #expect(throws: RemoteCallError.transport("connection_lost")) { try await h.client.call("state", [:]) }
        #expect(h.bridge.executions(of: "state") == 2)
    }

    @Test func everyActIsResentOnceWithItsKey() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { request in
            request.method == "chat_rename" ? .loseAnswer(.success(["renamed": true])) : .answer(.success([:]))
        }
        try await h.connect()
        let result = try await h.client.call("chat_rename", ["id": "c1", "title": "New"])
        #expect(result == ["renamed": true])
        let renames = h.bridge.requests("chat_rename")
        #expect(renames.count == 2 && renames[0].idem == renames[1].idem)
        #expect(h.bridge.executions(of: "chat_rename") == 1)
    }

    @Test func aRestartedBridgeNeverGetsTheCallAgain() async throws {
        let h = try await LiveHarness.make()
        h.bridge.respond { request in request.method == "send" ? .silent : .answer(.success([:])) }
        try await h.connect()
        let pending = Task { try await h.client.call("send", ["chat_id": "c1", "text": "hi"]) }
        try await eventually("the send") { h.bridge.requests("send").count == 1 }
        h.bridge.restart(epoch: "e2")
        await #expect(throws: RemoteCallError.transport("bridge_restarted")) { try await pending.value }
        #expect(h.bridge.requests("send").count == 1)
        try await h.connected(times: 2)
        // `.resyncNeeded` follows the connected status in the stream, so the log may not have it the moment the status shows.
        try await eventually("the second resync") { h.log.resyncCount == 2 }
        #expect(h.log.welcomes.last?.resumed == false)
    }

    // MARK: Refusals

    @Test func revokedStopsForGood() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        h.bridge.bye(.revoked, "This iPhone was removed on the Mac.")
        try await eventually("revoked") { await h.phase() == .failed(.revoked) }
        await #expect(throws: RemoteCallError.notConnected) { try await h.client.call("state", [:]) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(h.bridge.opens.count == 1)
        #expect(!h.watcher.isWatching)
    }

    @Test func unknownDeviceAndOldBridgesNeedThePerson() async throws {
        let unknown = try await LiveHarness.make(register: false)
        await unknown.client.connect(to: unknown.mac)
        try await eventually("unknown device") { await unknown.phase() == .failed(.unknownDevice) }

        let old = try await LiveHarness.make()
        old.bridge.refuseNextHello(ByeFrame(code: .badVersion, error: "Update Pebble on the Mac."))
        await old.client.connect(to: old.mac)
        try await eventually("bridge too old") { await old.phase() == .failed(.bridgeTooOld) }

        let other = try await LiveHarness.make()
        other.bridge.refuseNextHello(ByeFrame(code: ByeCode(rawValue: "maintenance"), error: "Remote is off on the Mac."))
        await other.client.connect(to: other.mac)
        try await eventually("other") { await other.phase() == .failed(.other("Remote is off on the Mac.")) }
    }

    @Test func busyIsRetried() async throws {
        let h = try await LiveHarness.make()
        h.bridge.refuseNextHello(ByeFrame(code: .busy, error: "Busy."))
        await h.client.connect(to: h.mac)
        try await h.connected()
        #expect(h.bridge.hellos.count == 2)
    }

    @Test func connectingAgainSkipsTheBackoffWait() async throws {
        var configuration = LiveHarness.fast
        configuration.backoff = Backoff(initial: .seconds(20), maximum: .seconds(30))
        let h = try await LiveHarness.make(configuration: configuration)
        h.bridge.set(.unreachable(after: .zero), for: LiveHarness.lan)
        await h.client.connect(to: h.mac)
        try await eventually("waiting to retry") {
            if case .reconnecting(_, let next?) = await h.phase() { return next > Date() } else { return false }
        }
        h.bridge.set(.accept(after: .zero), for: LiveHarness.lan)
        await h.client.connect(to: h.mac)  // the app comes back to the foreground
        try await h.connected()
        #expect(h.bridge.opens.count == 2)
    }

    @Test func aWrongKeyIsRefusedUntilTheNetworkChanges() async throws {
        let h = try await LiveHarness.make(endpoints: [LiveHarness.lan, LiveHarness.tailnet])
        h.bridge.set(.wrongKey, for: LiveHarness.lan)
        h.bridge.set(.unreachable(after: .zero), for: LiveHarness.tailnet)
        await h.client.connect(to: h.mac)
        try await eventually("pin mismatch") { await h.phase() == .failed(.pinMismatch) }
        #expect(h.bridge.hellos.isEmpty)
        // At home again: the real Mac answers.
        h.bridge.set(.accept(after: .zero), for: LiveHarness.lan)
        h.watcher.change()
        try await h.connected()
    }

    /// The person's first pairing (2026-10-30): the app's Local Network switch was off, so no connection left the
    /// phone. The app says so, and connects when it comes back from Settings.
    @Test func aBlockedLocalNetworkSaysSoAndConnectsBackFromSettings() async throws {
        let h = try await LiveHarness.make(endpoints: [LiveHarness.lan, LiveHarness.tailnet])
        h.bridge.set(.localNetworkDenied, for: LiveHarness.lan)
        h.bridge.set(.unreachable(after: .zero), for: LiveHarness.tailnet)
        await h.client.connect(to: h.mac)
        try await eventually("local network") { await h.phase() == .failed(.localNetworkDenied) }
        h.bridge.set(.accept(after: .zero), for: LiveHarness.lan)
        await h.client.connect(to: h.mac)  // the app comes back to the foreground
        try await h.connected()
        #expect(LiveClient.callError(for: Handshake.Failure.localNetworkDenied) == .transport("local_network"))
    }

    // MARK: Racing

    @Test func lanWinsAndOnlyTheWinnerSaysHello() async throws {
        let h = try await LiveHarness.make(endpoints: [LiveHarness.tailnet, LiveHarness.lan])
        h.bridge.set(.accept(after: .milliseconds(40)), for: LiveHarness.lan)
        try await h.connect()
        #expect(await h.client.connectionStatus.route == .lan)
        #expect(!h.bridge.opens.contains(LiveHarness.tailnet))
        #expect(h.bridge.hellos.count == 1)
    }

    @Test func tailnetTakesOverWhenLANIsUnreachable() async throws {
        let h = try await LiveHarness.make(endpoints: [LiveHarness.lan, LiveHarness.lanName, LiveHarness.tailnet])
        h.bridge.set(.unreachable(after: .zero), for: LiveHarness.lan)
        h.bridge.set(.unreachable(after: .milliseconds(10)), for: LiveHarness.lanName)
        try await h.connect()
        #expect(await h.client.connectionStatus.route == .tailscale)
    }

    @Test func racingSocketsThatLoseAreClosedUnused() async throws {
        let h = try await LiveHarness.make(endpoints: [LiveHarness.lan, LiveHarness.lanName])
        try await h.connect()
        try await eventually("losers closed") {
            let sockets = h.bridge.sockets
            return sockets.count == 2 && sockets.filter { !$0.isClosed }.count == 1
        }
        let used = h.bridge.sockets.filter { !$0.sent.isEmpty }
        #expect(used.count == 1 && used.first?.isClosed == false)
        #expect(h.bridge.hellos.count == 1)
    }

    // MARK: Heartbeat and path changes

    @Test func anUnansweredPingReconnects() async throws {
        var configuration = LiveHarness.fast
        configuration.pingTimeout = .milliseconds(150)
        let h = try await LiveHarness.make(configuration: configuration)
        h.bridge.setPingMode(.hang)
        try await h.connect()
        h.bridge.setPingMode(.answer)
        try await h.connected(times: 2)
        #expect(h.bridge.sockets.first?.isClosed == true)
        try await eventually("a round trip") { await h.client.connectionStatus.roundTrip != nil }
    }

    @Test func aNewNetworkRacesAgainAndKeepsEverything() async throws {
        let h = try await LiveHarness.make(endpoints: [LiveHarness.lan, LiveHarness.tailnet])
        try await h.connect()
        h.bridge.emit("token", ["chat_id": "c1", "id": "m1", "text": "a"])
        try await eventually("an event") { h.log.events.count == 1 }
        h.watcher.change()
        try await eventually("a second hello and the old socket closed") {
            h.bridge.hellos.count == 2 && h.bridge.sockets.first?.isClosed == true
        }
        try await eventually("connected") { await h.phase() == .connected }
        #expect(h.bridge.hellos[1].resume == HelloFrame.Resume(epoch: "e1", seq: 1))
        h.bridge.emit("token", ["chat_id": "c1", "id": "m1", "text": "b"])
        try await eventually("the next event") { h.log.events.count == 2 }
        #expect(h.log.events.map(\.seq) == [1, 2])
        #expect(!h.log.phases.contains { if case .failed = $0 { true } else { false } })
        _ = try await h.client.call("state", [:])
    }

    // MARK: Pairing

    @Test func pairingSignsWithBothKeysAndKeepsThem() async throws {
        let bridge = FakeBridge()
        bridge.allowPairing(code: "c0de-ONE")
        let keys = RecordingKeyProvider()
        let client = LiveClient(
            keys: keys, pairingReason: { "Pair with \($0)" }, connector: FakeBridgeConnector(bridge: bridge),
            pathWatcher: ManualPathWatcher(), discovery: NoBridgeDiscovery(),
            device: DeviceDescription(model: "iPhone18,3", os: "iOS 26.1", app: "1.0 (1)"),
            configuration: LiveHarness.fast)
        let log = UpdateLog(client)
        let link = PairingLink(
            version: 1, bridgeID: bridge.bridgeID, macName: "Mac", pin: bridge.pin, code: "c0de-ONE",
            endpoints: [LiveHarness.lan])
        let mac = try await client.pair(link, deviceName: "Sam's iPhone")
        #expect(mac.deviceID == "dev-1" && mac.name == "Studio Mac" && mac.pin == bridge.pin)
        #expect(mac.endpoints == [LiveHarness.lan] && mac.bridgeID == bridge.bridgeID)
        #expect(bridge.problems.isEmpty)
        let pair = try #require(bridge.pairs.first)
        #expect(pair.device == PairFrame.Device(name: "Sam's iPhone", model: "iPhone18,3", os: "iOS 26.1", app: "1.0 (1)"))
        #expect(keys.reasons == ["Pair with Mac"])
        let kept = try #require(try await keys.keys(for: bridge.bridgeID))
        #expect(kept.device.publicKeyText == pair.deviceKey && kept.approve.publicKeyText == pair.approveKey)
        let pairingSocketsClosed = bridge.sockets.allSatisfy { $0.isClosed }
        #expect(pairingSocketsClosed)

        await client.connect(to: mac)
        try await eventually("connected") { log.connectedCount == 1 }
        #expect(bridge.hellos.count == 1 && bridge.problems.isEmpty)
    }

    @Test func aRefusedPairingKeepsNothing() async throws {
        let bridge = FakeBridge()
        bridge.allowPairing(code: "right")
        let keys = RecordingKeyProvider()
        let client = LiveClient(
            keys: keys, pairingReason: { "Pair with \($0)" }, connector: FakeBridgeConnector(bridge: bridge),
            pathWatcher: ManualPathWatcher(), discovery: NoBridgeDiscovery(), configuration: LiveHarness.fast)
        let link = PairingLink(
            version: 1, bridgeID: bridge.bridgeID, macName: "Mac", pin: bridge.pin, code: "wrong",
            endpoints: [LiveHarness.lan])
        do {
            _ = try await client.pair(link, deviceName: "iPhone")
            Issue.record("expected a refusal")
        } catch RemoteCallError.transport(let code) {
            #expect(code == "bad_code")  // v0.3 item 1: a pairing problem the screens put in words
        }
        #expect(try await keys.keys(for: bridge.bridgeID) == nil)

        var wrongPin = link
        wrongPin.pin = "AAAA" + bridge.pin.dropFirst(4)
        await #expect(throws: RemoteCallError.transport("pin_mismatch")) {
            try await client.pair(wrongPin, deviceName: "iPhone")
        }
    }

    @Test func forgettingAMacDeletesItsKeys() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        await h.client.forget(h.mac)
        #expect(await h.phase() == .idle)
        #expect(try await h.keys.keys(for: h.bridge.bridgeID) == nil)
        await #expect(throws: RemoteCallError.notConnected) { try await h.client.call("state", [:]) }
    }
}
