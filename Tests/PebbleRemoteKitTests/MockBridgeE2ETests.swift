import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane B: LiveClient end to end against lane C's mock bridge (bridge-mock/mock_bridge.py) over real TLS 1.3, the real
// pin check and Network.framework's WebSocket. Skipped unless PEBBLE_MOCK_E2E=1:
//
//     PEBBLE_MOCK_E2E=1 scripts/swift.sh test --filter MockBridgeE2ETests

/// What the mock prints on stdout, kept as it arrives: `PAIRING_LINK=`, `READY=1`, and (X-1, lane X) a
/// `PAIRING_CODE=123456` each time a pairing waits for the person to confirm its code on the Mac. It is read with the
/// pipe's own readability handler, which runs on a dispatch queue: a task that waited on the pipe would hold one of the
/// few threads the tests share for as long as the mock lives.
final class MockStdout: Sendable {
    private struct State {
        var lines: [String] = []
        var partial = Data()
    }

    private let state = Mutex(State())

    /// The complete lines so far.
    var lines: [String] { state.withLock { $0.lines } }

    /// Starts collecting what `handle` delivers, until the mock closes it.
    func read(_ handle: FileHandle) {
        handle.readabilityHandler = { [self] file in
            let data = file.availableData
            guard !data.isEmpty else {
                file.readabilityHandler = nil  // the mock closed its output
                return
            }
            state.withLock { state in
                state.partial.append(data)
                while let newline = state.partial.firstIndex(of: UInt8(ascii: "\n")) {
                    state.lines.append(String(decoding: state.partial[..<newline], as: UTF8.self))
                    state.partial.removeSubrange(...newline)
                }
            }
        }
    }
}

/// The mock bridge, run as a child process on 127.0.0.1 with an ephemeral port and its own state folder.
final class MockBridgeProcess {
    let process: Process
    let stateFolder: URL
    let pairingLink: String
    private let stdout: MockStdout

    /// The six digits the Mac shows for each pairing that waited for its person to confirm, oldest first (X-1).
    var pairingCodes: [String] {
        stdout.lines.compactMap { $0.hasPrefix("PAIRING_CODE=") ? String($0.dropFirst("PAIRING_CODE=".count)) : nil }
    }

    /// The same, once the mock has printed at least `count` of them: its stdout is read on a dispatch queue, a moment
    /// behind the pairing that the phone has just finished.
    func pairingCodes(waitingFor count: Int, timeout: Duration = .seconds(5)) async throws -> [String] {
        let deadline = ContinuousClock.now + timeout
        while pairingCodes.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return pairingCodes
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    struct LaunchFailed: Error, CustomStringConvertible {
        var description: String
    }

    /// `extraArguments` go to the mock as they are (lane N: `--folders-root <a test tree>`).
    static func launch(speed: Double = 4, extraArguments: [String] = []) async throws -> MockBridgeProcess {
        let state = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pebble-remote-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-I", repositoryRoot.appendingPathComponent("bridge-mock/mock_bridge.py").path,
            "--host", "127.0.0.1", "--port", "0", "--state-dir", state.path, "--print-pairing", "--speed",
            String(speed), "--quiet",
        ] + extraArguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // `--pair-confirm ask` reads the Mac's answer from stdin: there is none here, so it times out like a person
        // who walked away (`--pair-confirm-timeout`).
        process.standardInput = FileHandle.nullDevice
        // PEBBLE_MOCK_LOG=<file> keeps the mock's (content-free) log, for diagnosing a failure.
        if let path = ProcessInfo.processInfo.environment["PEBBLE_MOCK_LOG"],
            FileManager.default.createFile(atPath: path, contents: nil),
            let log = FileHandle(forWritingAtPath: path)
        {
            process.standardError = log
            process.arguments?.removeAll { $0 == "--quiet" }
        }
        try process.run()
        let stdout = MockStdout()
        stdout.read(output.fileHandleForReading)
        let deadline = ContinuousClock.now + .seconds(20)
        while !stdout.lines.contains("READY=1"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard stdout.lines.contains("READY=1") else {
            process.terminate()
            try? FileManager.default.removeItem(at: state)
            throw LaunchFailed(description: "the mock did not say READY=1 within 20 s")
        }
        guard let link = stdout.lines.first(where: { $0.hasPrefix("PAIRING_LINK=") })?.dropFirst("PAIRING_LINK=".count)
        else {
            process.terminate()
            try? FileManager.default.removeItem(at: state)
            throw LaunchFailed(description: "the mock printed no PAIRING_LINK")
        }
        return MockBridgeProcess(process: process, stateFolder: state, pairingLink: String(link), stdout: stdout)
    }

    private init(process: Process, stateFolder: URL, pairingLink: String, stdout: MockStdout) {
        self.process = process
        self.stateFolder = stateFolder
        self.pairingLink = pairingLink
        self.stdout = stdout
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            // Waits for it to go, but never for ever: Foundation's `waitUntilExit` runs the thread's run loop until the
            // task's termination notice arrives, and a notice that came before it began to wait never comes (a test run
            // hung there for ten minutes on 2026-10-30, holding one of the few threads the tests share).
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning, Date() < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        try? FileManager.default.removeItem(at: stateFolder)
    }
}

/// The real connector, keeping the sockets it opened so a test can drop one.
final class RecordingConnector: FrameSocketConnector {
    let inner = NetworkSocketConnector()
    private let opened = Mutex<[any FrameSocket]>([])

    func open(_ endpoint: Endpoint, pin: String) async throws -> any FrameSocket {
        let socket = try await inner.open(endpoint, pin: pin)
        opened.withLock { $0.append(socket) }
        return socket
    }

    var count: Int { opened.withLock { $0.count } }

    /// Closes the newest socket under the client, as if the network dropped it.
    func dropNewest() async {
        if let socket = opened.withLock({ $0.last }) { await socket.close() }
    }
}

@Suite("Lane B: end to end with the mock bridge", .serialized)
struct MockBridgeE2ETests {
    static let enabled = ProcessInfo.processInfo.environment["PEBBLE_MOCK_E2E"] == "1"

    @Test(.enabled(if: enabled), .timeLimit(.minutes(1)))
    func pairsCallsApprovesAndResumes() async throws {
        let mock = try await MockBridgeProcess.launch()
        defer { mock.stop() }
        let link = try #require(PairingLink(string: mock.pairingLink))
        let keys = RecordingKeyProvider()
        let connector = RecordingConnector()
        let client = LiveClient(
            keys: keys, pairingReason: { "Pair with \($0)" }, unlockReason: "Unlock Pebble", connector: connector,
            pathWatcher: StillPathWatcher(),
            discovery: NoBridgeDiscovery(), device: DeviceDescription(model: "iPhone18,3", os: "iOS 26.1", app: "1.0 (1)"),
            configuration: LiveClient.Configuration(backoff: Backoff(initial: .milliseconds(100), maximum: .seconds(1))))
        let log = UpdateLog(client)

        // Pairing: T_pair signed by both keys; the approve signature is the one Face ID would guard.
        let mac = try await client.pair(link, deviceName: "Test iPhone")
        #expect(!mac.deviceID.isEmpty && mac.pin == link.pin && mac.bridgeID == link.bridgeID)
        #expect(keys.reasons == ["Pair with \(link.macName)"])

        // A spent pairing code is refused in the bridge's words.
        do {
            _ = try await LiveClient(
                keys: RecordingKeyProvider(), pairingReason: { $0 }, connector: NetworkSocketConnector(),
                pathWatcher: StillPathWatcher(), discovery: NoBridgeDiscovery()
            ).pair(link, deviceName: "Another iPhone")
            Issue.record("a spent code was accepted")
        } catch RemoteCallError.transport(let code) {
            #expect(code == "bad_code")  // v0.3 item 1: a pairing problem the screens put in words
        }

        // Connecting: hello signed by the device key over the TLS-pinned channel.
        await client.connect(to: mac)
        try await eventually("connected", timeout: .seconds(15)) { log.connectedCount >= 1 }
        let info = try #require(log.welcomes.first)
        #expect(info.methods.contains("state") && info.elevated.contains("approve") && info.pebbleRunning)
        try await eventually("a round trip") { await client.connectionStatus.roundTrip != nil }

        // Reads, and a refusal from the allowlist.
        let state = try await client.call("state", [:])
        let chats = try #require(state["chats"]?.array)
        let tidy = try #require(chats.first { $0["title"]?.string == "Tidy the test suite" })
        let chatID = try #require(tidy["id"]?.string)
        let chat = try await client.call("get_chat", ["id": .string(chatID)])
        let card = try #require(
            chat["actions"]?.array?.first { $0["status"]?.string == "pending" && $0["kind"]?.string == "command" })
        let actionID = try #require(card["id"]?.string)
        // A sign-in stays the Mac's own (v0.5 item 4); `open_url` moved to the elevated methods in v0.5.
        do {
            _ = try await client.call("chatgpt_start", [:])
            Issue.record("chatgpt_start was allowed")
        } catch RemoteCallError.refused(let refusal) {
            #expect(refusal.code == "not_allowed")
        }

        // The unlock (C1): the first call that acts is refused with unlock_required; the client asks Face ID, sends
        // remote.unlock, and tries again with the same idem.
        #expect(await client.unlockedUntil == nil)
        let renamed = try await client.call("chat_rename", ["id": .string(chatID), "title": "Tidy the test suite"])
        #expect(renamed["title"]?.string == "Tidy the test suite")
        #expect(keys.reasons.last == "Unlock Pebble")
        #expect((await client.unlockedUntil ?? .distantPast) > Date())
        #expect(log.all.contains { if case .unlocked(let until?) = $0 { until > Date() } else { false } })

        // Approving needs a proof by the approve key over T_proof v0.3 (this connection's nonce, the call's idem).
        let result = try await client.callElevated(
            "approve", ["id": .string(chatID), "action_id": .string(actionID)], reason: "Approve: run npm test")
        #expect(result["exit_code"]?.int == 0)
        #expect(keys.reasons.last == "Approve: run npm test")
        // Without the proof the bridge refuses.
        do {
            _ = try await client.call("approve", ["id": .string(chatID), "action_id": .string(actionID)])
            Issue.record("approve without a proof was accepted")
        } catch RemoteCallError.refused(let refusal) {
            #expect(refusal.code == "proof_required")
        }

        // Dropping the connection while the run streams: the client reconnects and resumes from its seq.
        let eventsBeforeDrop = log.events.count
        await connector.dropNewest()
        try await eventually("reconnected", timeout: .seconds(15)) { log.connectedCount >= 2 }
        #expect(log.welcomes.count == 2 && log.welcomes.last?.resumed == true)
        #expect(log.resyncCount == 1)
        try await eventually("the run finished", timeout: .seconds(20)) {
            let events = log.events
            guard let complete = events.last(where: { $0.name == "complete" && $0.chatID == chatID }) else {
                return false
            }
            return events.contains { $0.name == "idle" && $0.chatID == chatID && $0.seq > complete.seq }
        }
        let seqs = log.events.map(\.seq)
        #expect(log.events.count > eventsBeforeDrop)
        #expect(seqs == Array((seqs.first ?? 1)...(seqs.last ?? 0)), "events arrive once each, in order, none missing")

        // An idempotent call over the resumed connection.
        let sent = try await client.call("send", ["id": .string(chatID), "text": "Thanks, that is all."])
        #expect(sent["message_id"]?.string != nil)

        await client.disconnect()
        #expect(await client.connectionStatus.phase == .idle)
    }
}
