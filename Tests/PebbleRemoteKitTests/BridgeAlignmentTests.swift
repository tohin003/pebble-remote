import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// The phone against Pebble 1.9.29's own bridge, not the mock (read-only Pebble checkout: backend/pebble/
// remote_bridge.py, remote_policy.py, remote_keys.py and remote.py, as of 2026-10-30 20:59): its welcome, what each of
// the phone's calls needs there, its pairing links and answers, X-8 (removing another phone), the burst limit and
// trimmed events. The review: docs/reviews/bridge-alignment-2026-10-31.md.

enum RealBridge {
    /// The welcome the bridge sends (remote_bridge.authenticate). `methods` is remote_policy.METHODS (main.rs's ALLOWED
    /// minus PHONE_EXCLUDED, then the `remote.*` methods) and `elevated` remote_policy.ELEVATED, both in the bridge's
    /// order; only the line breaks are added.
    static let welcome = #"""
        {"t":"welcome","v":1,"epoch":"e-Zk9qX3RyYWlu","seq":42,"resumed":false,
        "bridge":{"version":"1.9.29","name":"Sam’s MacBook Pro"},"pebble":{"running":true,"version":"1.9.29"},
        "methods":[
            "state", "new_chat", "get_chat", "set_workspace", "send", "cancel", "model_load", "model_unload",
            "approve", "reject", "apps", "attach_url", "attach_bytes", "remove_source", "delete_chat", "chat_rename",
            "chat_search", "setting", "open_app", "undo", "model_profiles", "model_select", "model_effort",
            "memory_list", "memory_save", "memory_delete", "memory_clear", "memory_candidates", "memory_maintain",
            "memory_resolve", "extensions", "skill_inspect", "hook_events", "extension_toggle", "media_artifact",
            "connector_status", "terminal_propose", "open_url", "chatgpt_status", "view_stage", "view_stop",
            "artifact_get", "artifact_history", "artifact_submit", "artifact_stop", "artifact_view_open", "mods",
            "mod_toggle", "run_list", "run_get", "run_activity", "run_handoff", "run_compact", "run_context_archive",
            "search_stats", "run_events", "stream_read", "process_list", "process_read", "process_stop",
            "process_inspect", "process_dismiss", "run_pause", "run_resume", "run_held_tests", "run_held_finish",
            "run_held_accept", "run_reconcile", "run_readback", "process_terminal", "process_input_human",
            "memory_contests", "memory_resolve_contest", "memory_relations", "memory_forget_preview",
            "model_handoff_preview", "model_handoff_approve", "model_handoff_start", "research_sources",
            "screen_windows", "screen_session_grant", "screen_sessions", "screen_handoff_done",
            "screen_session_revoke", "browser_status", "browser_start", "browser_stop", "browser_tabs",
            "browser_open_tab", "command_catalogue", "run_steer", "question_answer", "question_cancel", "agent_list",
            "agent_get", "agent_steer", "agent_cancel", "job_list", "job_get", "job_preview", "job_create",
            "job_pause", "job_preview_resume", "job_resume", "job_delete", "notification_ack", "git_capabilities",
            "git_identity", "git_status", "git_diff", "git_history", "git_worktrees", "git_inspect",
            "git_preview_create", "git_create_worktree", "git_preview_remove", "git_remove_worktree",
            "git_forget_worktree", "git_plan_propose", "git_plan_receipts", "git_plan_readback", "agent_worktrees",
            "agent_worktree_retire", "agent_worktree_reconcile", "project_recipes", "environment_list",
            "environment_plan", "environment_remove", "notification_status", "notification_mute", "goal_list",
            "goal_get", "goal_create", "goal_state", "goal_criterion_add", "goal_criterion_edit",
            "goal_criterion_check", "goal_criterion_review", "goal_step_add", "goal_step_edit", "goal_step_block",
            "goal_blockers", "goal_continue", "export_preview", "export_render", "export_cancel", "export_list",
            "export_get", "export_discard", "telemetry_get", "telemetry_set", "artifact_refresh", "quiz_attempt",
            "quiz_start", "quiz_save", "quiz_submit", "quiz_share", "rewind_preview", "rewind_apply",
            "context_inspect", "context_compact", "browser_extension_status", "browser_extension_pause",
            "browser_extension_resume", "browser_extension_stop", "storage_summary", "storage_restore_chat",
            "storage_purge_chat", "storage_refresh", "storage_trash_chat", "storage_trash_all", "storage_purge_all",
            "browser_connect_status", "shell_grants", "shell_grant_add", "shell_grant_remove", "shell_undo",
            "toolbox_list", "toolbox_get", "toolbox_remove", "toolbox_decide", "app_control_status",
            "app_control_request", "approve_simple", "reject_simple", "toolbox_undo_remove", "remote.status",
            "remote.devices", "remote.revoke_device", "remote.keep_awake", "remote.chat_tail", "remote.chat_before",
            "remote.ping", "remote.unlock", "remote.lock", "remote.screenshot", "remote.folders"
        ],
        "elevated":[
            "agent_worktree_retire", "app_control_request", "approve", "approve_simple", "artifact_view_open",
            "browser_open_tab", "browser_start", "delete_chat", "environment_remove", "extension_toggle",
            "git_remove_worktree", "job_create", "job_resume", "memory_clear", "memory_delete", "mod_toggle",
            "model_handoff_approve", "open_app", "open_url", "process_input_human", "process_terminal", "quiz_share",
            "remote.unlock", "rewind_apply", "run_held_accept", "run_held_finish", "screen_session_grant",
            "shell_grant_add", "shell_grant_remove", "storage_purge_all", "storage_purge_chat", "storage_trash_all",
            "terminal_propose", "view_stage", "setting:git_decisions", "setting:memory_enabled",
            "setting:memory_layers", "setting:notifications", "setting:permissions", "setting:stealth",
            "setting:storage"
        ],
        "unlock_seconds":900,"limits":{"max_request":131072,"max_frame":8388608}}
        """#

    /// remote_policy.UNLOCK_FREE: the reads that need neither the unlock nor `idem`.
    static let unlockFree: Set<String> = [
        "state", "get_chat", "chat_search", "run_list", "run_get", "run_activity", "run_events", "stream_read",
        "artifact_get", "remote.status", "remote.devices", "remote.ping", "remote.chat_tail", "remote.chat_before",
        "remote.lock",
    ]

    /// remote_policy.READ_ONLY: `idem` optional, never recorded as a change on the Mac (some need the unlock).
    static let readOnly: Set<String> = unlockFree.union([
        "model_profiles", "screen_sessions", "toolbox_list", "toolbox_get", "job_list", "job_get", "job_preview",
        "job_preview_resume", "goal_list", "goal_get", "notification_status", "command_catalogue", "storage_summary",
        "browser_status", "remote.screenshot", "remote.folders",
    ])

    /// Every method the Kit calls (RemoteStore and its extensions, LiveClient; not the demo), 2026-10-31.
    static let phoneCalls: Set<String> = [
        "state", "get_chat", "chat_search", "run_list", "run_activity", "remote.status", "remote.devices",
        "remote.chat_tail", "remote.chat_before", "remote.lock", "remote.unlock", "remote.keep_awake",
        "remote.screenshot", "remote.folders", "remote.folder_create", "remote.revoke_device", "send", "new_chat",
        "set_workspace", "chat_rename", "cancel", "run_pause", "run_resume", "approve", "approve_simple", "reject",
        "reject_simple", "question_answer", "question_cancel", "setting", "model_profiles", "model_select",
        "model_effort", "attach_bytes", "attach_url", "remove_source", "terminal_propose", "storage_summary",
        "storage_trash_chat", "storage_restore_chat", "storage_purge_chat", "job_list", "job_preview", "job_create",
        "job_pause", "job_preview_resume", "job_resume", "job_delete", "notification_status", "notification_ack",
        "toolbox_list", "toolbox_get", "toolbox_remove", "toolbox_undo_remove", "toolbox_decide", "screen_sessions",
        "screen_session_revoke", "screen_handoff_done", "screen_session_grant", "command_catalogue", "memory_list",
        "memory_delete", "memory_contests", "memory_resolve_contest", "context_inspect", "context_compact",
        "rewind_preview", "rewind_apply", "goal_list", "goal_get", "goal_create", "goal_state", "goal_criterion_add",
        "goal_criterion_check", "goal_criterion_review", "goal_continue", "agent_list", "agent_steer", "agent_cancel",
        "browser_extension_status", "browser_extension_pause", "browser_extension_resume", "browser_extension_stop",
        "browser_status", "browser_start", "browser_stop", "browser_tabs", "run_held_tests", "run_held_finish",
        "run_held_accept", "run_readback", "run_reconcile", "undo", "shell_undo", "git_plan_propose",
        "shell_grant_add", "process_list", "process_read", "process_terminal", "process_stop", "process_input_human",
        "process_inspect", "process_dismiss", "model_handoff_preview", "model_handoff_approve", "model_handoff_start",
        // Lane Q: taking a quiz (RemoteStore+Quiz).
        "quiz_attempt", "quiz_start", "quiz_save", "quiz_submit", "quiz_share",
    ]

    /// The welcome as the client turns it into `BridgeInfo` (LiveClient.activate).
    static func info() throws -> BridgeInfo {
        guard case .welcome(let welcome) = try FrameCodec.decode(Self.welcome) else {
            throw FrameDecodingError(reason: "not a welcome")
        }
        return BridgeInfo(
            bridgeVersion: welcome.bridge?.version ?? "", macName: welcome.bridge?.name ?? "",
            pebbleRunning: welcome.pebble?.running ?? false, pebbleVersion: welcome.pebble?.version,
            methods: Set(welcome.methods), elevated: Set(welcome.elevated), resumed: welcome.resumed,
            unlockSeconds: welcome.unlockSeconds)
    }

    /// remote.devices as Registry.listing writes it for the phone that asks: unix milliseconds, and `current`.
    static let devices: JSONValue = [
        [
            "device_id": "d-AbCdEfGhIjKlMnOp", "name": "iPhone 17", "paired_at": 1_761_800_000_000,
            "last_seen": 1_761_900_000_000, "current": true,
        ],
        [
            "device_id": "d-QrStUvWxYz012345", "name": "iPad", "paired_at": 1_761_700_000_000,
            "last_seen": 1_761_850_000_000, "current": false,
        ],
    ]
}

/// Says yes `count` times, then no; usable from the fakes' `@Sendable` closures.
final class Countdown: Sendable {
    private let left: Mutex<Int>
    init(_ count: Int) { left = Mutex(count) }
    func take() -> Bool {
        left.withLock { left in
            guard left > 0 else { return false }
            left -= 1
            return true
        }
    }
}

// MARK: - What the bridge offers and guards

@Test func everyCallThePhoneMakesIsOfferedExceptNewFolder() throws {
    let info = try RealBridge.info()
    #expect(info.methods.count == 197 && info.elevated.count == 41)
    #expect(info.bridgeVersion == "1.9.29" && info.pebbleVersion == "1.9.29" && info.macName == "Sam’s MacBook Pro")
    // Proposal v0.6 is not in 1.9.29: "New Folder" hides itself (`bridgeOffers("remote.folder_create")`).
    #expect(RealBridge.phoneCalls.subtracting(info.methods) == ["remote.folder_create"])
    #expect(info.offersUnlock && info.unlockSeconds == 900 && info.methods.contains(RemoteContract.lockMethod))
}

@Test func theReadsThePhoneSendsWithoutAKeyAreTheBridgesReads() {
    // Sent without `idem` and before the unlock: exactly the bridge's unlock-free reads, all of them ones it lets
    // through without a key (a call outside READ_ONLY without `idem` is `bad_request`).
    #expect(RemoteContract.readMethods == RealBridge.unlockFree)
    #expect(RemoteContract.readMethods.isSubset(of: RealBridge.readOnly))
}

@Test(arguments: ["permissions", "stealth", "memory_enabled", "memory_layers", "git_decisions", "notifications"])
func settingKeysTheBridgeGuardsAskForFaceID(key: String) throws {
    #expect(try RealBridge.info().needsProof("setting", ["key": .string(key), "value": true]))
}

@Test(arguments: ["fast_replies", "theme", "reduced_motion", "companion"])
func plainSettingKeysNeedOnlyTheUnlock(key: String) throws {
    #expect(try !RealBridge.info().needsProof("setting", ["key": .string(key), "value": true]))
}

// MARK: - Pairing links (remote_keys.pairing_link; the bridge's own tests' links)

@Test func theBridgesPairingLinkParsesWithEveryEndpoint() throws {
    let pin = String(repeating: "P", count: 43)
    let code = String(repeating: "C", count: 22)
    let link =
        "pebble-remote://pair?v=1&bid=b-0123456789abcdef&name=Sam%E2%80%99s%20MacBook%20Pro&pin=\(pin)&code=\(code)"
        + "&ep=192.168.1.20%3A47800&ep=Sams-MacBook-Pro.local%3A47800&ep=100.101.102.103%3A47800"
        + "&ep=sams-macbook-pro.tail1234.ts.net%3A47800"
    let expected = [
        Endpoint(host: "192.168.1.20", port: 47800), Endpoint(host: "Sams-MacBook-Pro.local", port: 47800),
        Endpoint(host: "100.101.102.103", port: 47800), Endpoint(host: "sams-macbook-pro.tail1234.ts.net", port: 47800),
    ]
    // Scanned or pasted (`init(string:)`), and opened as a link (`init(url:)`).
    for parsed in [PairingLink(string: link), URL(string: link).flatMap { PairingLink(url: $0) }] {
        let pairing = try #require(parsed)
        #expect(pairing.version == 1 && pairing.bridgeID == "b-0123456789abcdef")
        #expect(pairing.macName == "Sam’s MacBook Pro" && pairing.pin == pin && pairing.code == code)
        #expect(pairing.endpoints == expected)
        #expect(pairing.endpoints.map(\.routeKind) == [.lan, .lan, .tailscale, .tailscale])
    }
    // The bridge upgrades only GET /pebble-remote/v1 (remote_ws.PATH).
    #expect(
        expected.compactMap { NetworkSocketConnector.url(for: $0)?.absoluteString } == [
            "wss://192.168.1.20:47800/pebble-remote/v1", "wss://Sams-MacBook-Pro.local:47800/pebble-remote/v1",
            "wss://100.101.102.103:47800/pebble-remote/v1",
            "wss://sams-macbook-pro.tail1234.ts.net:47800/pebble-remote/v1",
        ])
}

@Test func aNameWithAnAmpersandAndAnIPv6EndpointSurviveTheBridgesEncoding() throws {
    // test_the_pairing_link_is_percent_encoded's link: every value through quote(value, safe='').
    let pairing = try #require(
        PairingLink(
            string: "pebble-remote://pair?v=1&bid=b-AAAA&name=Sam%E2%80%99s%20Mac%20%26%20co&pin=pin&code=code"
                + "&ep=192.168.1.2%3A47800&ep=%5Bfe80%3A%3A1%5D%3A1"))
    #expect(pairing.macName == "Sam’s Mac & co")
    #expect(pairing.endpoints == [Endpoint(host: "192.168.1.2", port: 47800), Endpoint(host: "fe80::1", port: 1)])
}

// MARK: - The bridge's own answers

@Test func remoteStatusAndDevicesReadAsTheBridgeWritesThem() {
    let status = RemoteStatusDTO(json: [
        "mac": [
            "name": "Sam’s MacBook Pro", "battery_percent": 81, "charging": false, "on_power": false,
            "keep_awake": true,
        ],
        "pebble": ["running": true, "version": "1.9.29"],
        "bridge": [
            "version": "1.9.29", "epoch": "e-Zk9qX3RyYWlu",
            "endpoints": [
                "192.168.1.20:47800", "Sams-MacBook-Pro.local:47800", "100.101.102.103:47800",
                "sams-macbook-pro.tail1234.ts.net:47800",
            ],
        ],
    ])
    #expect(status.mac?.batteryPercent == 81 && status.mac?.onPower == false && status.mac?.keepAwake == true)
    #expect(status.pebbleRunning == true && status.pebbleVersion == "1.9.29" && status.bridgeVersion == "1.9.29")
    #expect(status.endpoints.count == 4 && status.endpoints.last?.routeKind == .tailscale)
    // A Mac without a battery: pmset's null percentage.
    #expect(MacDTO(json: ["battery_percent": .null, "on_power": true]).batteryPercent == nil)

    let devices = (RealBridge.devices.array ?? []).compactMap(MacDevice.init(json:))
    #expect(devices.map(\.isCurrent) == [true, false])
    #expect(devices.first?.pairedAt == Date(timeIntervalSince1970: 1_761_800_000))
}

// MARK: - Calls the bridge guards, through the store

@MainActor
private func realStore(
    _ answers: @escaping @Sendable (String, JSONValue) throws -> JSONValue? = { _, _ in nil }
) async throws -> (RemoteStore, FakeClient) {
    let fake = FakeClient { method, params in
        if let answer = try answers(method, params) { return answer }
        switch method {
        case "state": return Fixture.stateJSON()
        case "remote.devices": return RealBridge.devices
        default: return .object([:])
        }
    }
    let store = RemoteStore(client: fake)
    fake.push(.welcome(try RealBridge.info()))
    _ = await eventually { store.pebble != nil }
    await store.load(.devices)
    return (store, fake)
}

@MainActor
@Test func removingAnotherPhoneAsksForFaceIDAtOnce() async throws {
    let (store, fake) = try await realStore()
    let other = try #require(store.devices.first { !$0.isCurrent })
    try await store.revokeDevice(other)
    // X-8: without a proof the bridge answers proof_required, which welcome.elevated cannot announce.
    let calls = fake.calls("remote.revoke_device")
    #expect(calls.count == 1 && calls.first?.elevated == true)
    #expect(calls.first?.params == ["device_id": "d-QrStUvWxYz012345"])
    #expect(calls.first?.reason == "Remove \u{201C}iPad\u{201D} from your Mac")
    #expect(store.devices.map(\.id) == ["d-AbCdEfGhIjKlMnOp"])
}

@MainActor
@Test func removingThisPhoneNeedsOnlyTheUnlock() async throws {
    let (store, fake) = try await realStore()
    try await store.revokeDevice(try #require(store.devices.first { $0.isCurrent }))
    #expect(fake.calls("remote.revoke_device").map(\.elevated) == [false])
}

@MainActor
@Test func aBridgeThatWantsAProofForThisPhoneTooGetsOneOnce() async throws {
    let refusals = Countdown(1)
    let (store, fake) = try await realStore { method, _ in
        guard method == "remote.revoke_device", refusals.take() else { return nil }
        throw RemoteCallError.refused(
            PersonFacingError(message: "Confirm with Face ID to do this.", code: "proof_required"))
    }
    try await store.revokeDevice(try #require(store.devices.first { $0.isCurrent }))
    #expect(fake.calls("remote.revoke_device").map(\.elevated) == [false, true])
    #expect(store.notice == nil && store.devices.count == 1)
}

@MainActor
@Test func callsTheBridgeListsAsElevatedGoWithFaceID() async throws {
    let (store, fake) = try await realStore()
    // `act` reads welcome.elevated: the composer's Terminal command (proposal v0.5) asks for Face ID at once.
    try await store.proposeTerminalCommand("npm test", network: false, in: "c1")
    #expect(fake.calls("terminal_propose").map(\.elevated) == [true])
    // Settings: the keys the bridge lists as `setting:<key>`, and no others.
    for key in ["permissions", "stealth", "memory_enabled", "memory_layers", "git_decisions", "notifications"] {
        #expect(store.settingNeedsProof(key), "setting:\(key)")
    }
    for key in ["fast_replies", "theme", "reduced_motion", "companion"] {
        #expect(!store.settingNeedsProof(key), "setting:\(key)")
    }
}

// MARK: - Events the bridge trims

@Test func aTrimmedEventIsReadAgainNotApplied() throws {
    var world = PebbleWorld()
    world.load(try #require(StateDTO(json: Fixture.stateJSON())))
    world.load(try #require(ChatDetailDTO(json: Fixture.chatDetail(actions: [Fixture.action("a1")]))))
    let cards = world.waitingItems()
    // remote_bridge.publish: an `actions` event over 1 MB arrives as `{chat_id, trimmed: true}`. Read as it stands it
    // would say the conversation has no cards.
    let change = world.apply(Fixture.event("actions", ["chat_id": "c1", "trimmed": true]))
    #expect(change.needsState && change.needsChats == ["c1"])
    #expect(!cards.isEmpty && world.waitingItems() == cards)
    // The bridge's own `remote.devices` event carries an array, never trimmed: it still reads the list again.
    let devices = world.apply(Fixture.event("remote.devices", RealBridge.devices))
    #expect(devices.lists == [.devices] && !devices.needsState)
}

// MARK: - The burst limit (3.9: 20 requests in a burst, 10 a second)

@Suite("Bridge alignment: the burst limit")
struct BurstLimitTests {
    static func harness() async throws -> LiveHarness {
        var configuration = LiveHarness.fast
        configuration.rateLimitPause = .milliseconds(20)
        return try await LiveHarness.make(configuration: configuration)
    }

    @Test func aReadTheLimitRefusedGoesAgainAsTheSameFrame() async throws {
        let h = try await Self.harness()
        let refusals = Countdown(2)
        h.bridge.limitBursts { $0.method == "state" && refusals.take() }
        h.bridge.respond { _ in .answer(.success(["version": "1.9.29"])) }
        try await h.connect()
        let result = try await h.client.call("state", [:])
        #expect(result == ["version": "1.9.29"])
        let sent = h.bridge.requests("state")
        #expect(sent.count == 3 && Set(sent.map(\.id)).count == 1 && sent.allSatisfy { $0.idem == nil })
        #expect(h.bridge.problems.isEmpty)
    }

    @Test func anActTheLimitRefusedKeepsItsIdAndKey() async throws {
        let h = try await Self.harness()
        let refusals = Countdown(1)
        h.bridge.limitBursts { $0.method == "chat_rename" && refusals.take() }
        h.bridge.respond { _ in .answer(.success(["title": "New"])) }
        try await h.connect()
        let result = try await h.client.call("chat_rename", ["id": "c1", "title": "New"])
        #expect(result == ["title": "New"])
        let sent = h.bridge.requests("chat_rename")
        try #require(sent.count == 2)
        #expect(sent[0] == sent[1] && sent[0].idem != nil)
        #expect(h.bridge.executions(of: "chat_rename") == 1)
    }

    @Test func anElevatedCallTheLimitRefusedGoesAgainWithItsProof() async throws {
        let h = try await Self.harness()
        let refusals = Countdown(1)
        h.bridge.limitBursts { $0.method == "approve" && refusals.take() }
        h.bridge.respond { _ in .answer(.success(["approved": true])) }
        try await h.connect()
        let result = try await h.client.callElevated(
            "approve", ["id": "c1", "action_id": "a9"], reason: "Approve: npm test")
        #expect(result == ["approved": true])
        let sent = h.bridge.requests("approve")
        try #require(sent.count == 2)
        #expect(sent[0] == sent[1])  // the same proof: the bridge never checked the first
        #expect(h.keys.reasons == ["Approve: npm test"])  // one Face ID
        #expect(h.bridge.proofsChecked == 1 && h.bridge.problems.isEmpty)
    }

    @Test func aCallStillRefusedAfterItsTriesKeepsTheBridgesWords() async throws {
        let h = try await Self.harness()
        h.bridge.limitBursts { $0.method == "state" }
        try await h.connect()
        do {
            _ = try await h.client.call("state", [:])
            Issue.record("expected the refusal")
        } catch RemoteCallError.refused(let refusal) {
            #expect(refusal.code == "rate_limited")
            #expect(refusal.message == "That's a lot of requests at once. Try again in a moment.")
        }
        #expect(h.bridge.requests("state").count == 1 + LiveClient.rateLimitRetries)
    }
}
