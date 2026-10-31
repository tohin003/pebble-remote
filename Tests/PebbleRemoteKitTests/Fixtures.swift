import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Payloads shaped exactly as Pebble sends them (read-only Pebble checkout: app.py state()/chat(), runner.py and
// controller.py emits, interaction.question()). Times are Unix seconds, as Pebble stores them.

enum Fixture {
    static let t0 = Date(timeIntervalSince1970: 1_761_759_000)

    static func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    static func event(_ name: String, _ data: JSONValue, seq: Int = 1, at seconds: Double = 0) -> PebbleEvent {
        PebbleEvent(seq: seq, name: name, data: data, time: at(seconds))
    }

    static let permissions: JSONValue = [
        "mode": "ask",
        "tools": [
            "files": true, "edits": true, "tests": true, "apps": true, "web": true, "terminal": true, "plugins": true,
            "views": true, "screen": false, "capture": true,
        ],
    ]

    static func stateJSON(
        chats: [JSONValue] = [chatRow("c1", "Fix the login redirect loop", workspace: "/Users/me/Projects/pebble-web")],
        runs: [JSONValue] = [], active: String? = nil, activeRun: String? = nil, mode: String = "ask",
        modelState: String = "ready"
    ) -> JSONValue {
        var permissions = Self.permissions
        if case .object(var object) = permissions {
            object["mode"] = .string(mode)
            permissions = .object(object)
        }
        return [
            "job_notifications": [],
            "chats": .array(chats),
            "model": [
                "state": .string(modelState), "configured": true, "name": "gpt-5.1", "path": "", "context": 272_000,
                "kind": "chatgpt", "profile_id": "chatgpt", "efforts": ["low", "medium", "high"], "effort": "medium",
                "future_field": ["ignored": true],
            ],
            "guard": ["available": true, "error": .null],
            "active": active.map(JSONValue.string) ?? .null,
            "active_run": activeRun.map(JSONValue.string) ?? .null,
            "runs": .array(runs),
            "settings": [
                "theme": "system", "reduced_motion": false, "stealth": false, "memory_enabled": true,
                "permissions": permissions, "fast_replies": "long_tasks",
                "companion": ["pointer": true, "reactions": true, "status_words": "rotate", "ui_guidance": true],
            ],
            "data_dir": "/Users/me/.pebble", "platform": "darwin", "version": "1.9.28", "profiles": [],
        ]
    }

    static func chatRow(_ id: String, _ title: String, workspace: String? = nil, updated: Double = 0) -> JSONValue {
        [
            "id": .string(id), "title": .string(title), "workspace": workspace.map(JSONValue.string) ?? .null,
            "updated": .double(t0.timeIntervalSince1970 + updated),
        ]
    }

    static func runRow(
        _ id: String, chat: String, state: String, created: Double = 0, elapsed: Double = 0, error: String? = nil,
        steps: Int = 0
    ) -> JSONValue {
        [
            "id": .string(id), "chat_id": .string(chat), "state": .string(state), "steps": .int(steps),
            "elapsed": .double(elapsed), "error": error.map(JSONValue.string) ?? .null,
            "created": .double(t0.timeIntervalSince1970 + created), "updated": .double(t0.timeIntervalSince1970 + created),
        ]
    }

    static func message(_ id: String, _ role: String, _ content: String, at seconds: Double = 0, run: String? = nil)
        -> JSONValue
    {
        var object: [String: JSONValue] = [
            "id": .string(id), "chat_id": "c1", "role": .string(role), "content": .string(content),
            "created": .double(t0.timeIntervalSince1970 + seconds), "attachments": [],
        ]
        if let run { object["run_id"] = .string(run) }
        return .object(object)
    }

    static func action(
        _ id: String, chat: String = "c1", kind: String = "command", status: String = "pending",
        payload: JSONValue = ["command": "npm test", "root": "/Users/me/Projects/pebble-web", "writable": false],
        at seconds: Double = 0
    ) -> JSONValue {
        [
            "id": .string(id), "chat_id": .string(chat), "kind": .string(kind), "status": .string(status),
            "payload": payload, "created": .double(t0.timeIntervalSince1970 + seconds),
        ]
    }

    static func question(_ id: String, run: String = "r1", status: String = "pending", required: Bool = true, at seconds: Double = 0)
        -> JSONValue
    {
        [
            "id": .string(id), "run_id": .string(run), "call_id": "3:call_ask", "revision": 1, "required": .bool(required),
            "status": .string(status),
            "items": [
                [
                    "id": "tone", "title": "Which tone should the emails use?",
                    "options": [
                        ["id": "warm", "label": "Warm and friendly", "description": "First names"],
                        ["id": "brief", "label": "Short and direct", "description": ""],
                    ],
                    "allow_free_text": true,
                ]
            ],
            "answer": .null, "created": .double(t0.timeIntervalSince1970 + seconds), "answered": .null, "chat_id": "c1",
        ]
    }

    static func chatDetail(
        _ id: String = "c1", title: String = "Fix the login redirect loop", messages: [JSONValue] = [],
        actions: [JSONValue] = [], runs: [JSONValue] = [], questions: [JSONValue] = [], hasOlder: Bool? = nil
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id), "title": .string(title), "workspace": "/Users/me/Projects/pebble-web",
            "updated": .double(t0.timeIntervalSince1970), "trashed": false, "messages": .array(messages),
            "actions": .array(actions), "artifacts": [], "runs": .array(runs), "questions": .array(questions),
            "plan": .null,
        ]
        if let hasOlder { object["has_older"] = .bool(hasOlder) }
        return .object(object)
    }

    /// A world with Pebble's state and conversation c1 open.
    static func world(
        runs: [JSONValue] = [], messages: [JSONValue] = [], active: String? = nil, activeRun: String? = nil
    ) -> PebbleWorld {
        var world = PebbleWorld()
        world.load(StateDTO(json: stateJSON(runs: runs, active: active, activeRun: activeRun))!)
        world.load(ChatDetailDTO(json: chatDetail(messages: messages, runs: runs))!)
        return world
    }
}

/// A client whose answers the test writes, recording every call.
final class FakeClient: RemoteClient {
    struct Call: Sendable, Hashable {
        var method: String
        var params: JSONValue
        var elevated: Bool
        var reason: String?
    }

    let updates: AsyncStream<ClientUpdate>
    private let continuation: AsyncStream<ClientUpdate>.Continuation
    private let recorded = Mutex<[Call]>([])
    private let answers: @Sendable (String, JSONValue) throws -> JSONValue
    private let reaction = Mutex<(@Sendable (FakeClient, Call) -> Void)?>(nil)

    init(_ answers: @escaping @Sendable (String, JSONValue) throws -> JSONValue = { _, _ in .bool(true) }) {
        (updates, continuation) = AsyncStream.makeStream(of: ClientUpdate.self)
        self.answers = answers
    }

    var calls: [Call] { recorded.withLock { $0 } }
    var methods: [String] { calls.map(\.method) }
    func calls(_ method: String) -> [Call] { calls.filter { $0.method == method } }

    func push(_ update: ClientUpdate) { continuation.yield(update) }
    /// A live event: later than any fixture row, as events after a read are.
    func push(_ name: String, _ data: JSONValue) { continuation.yield(.event(Fixture.event(name, data, at: 10_000))) }

    /// What Pebble does after answering a call (sends events).
    func react(_ body: @escaping @Sendable (FakeClient, Call) -> Void) { reaction.withLock { $0 = body } }

    func connect(to mac: PairedMac) async {}
    func disconnect() async {}

    func call(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        try respond(Call(method: method, params: params, elevated: false, reason: nil))
    }

    func callElevated(_ method: String, _ params: JSONValue, reason: String) async throws -> JSONValue {
        try respond(Call(method: method, params: params, elevated: true, reason: reason))
    }

    private func respond(_ call: Call) throws -> JSONValue {
        recorded.withLock { $0.append(call) }
        let result = try answers(call.method, call.params)
        if let body = reaction.withLock({ $0 }) { body(self, call) }
        return result
    }

    func pair(_ link: PairingLink, deviceName: String) async throws -> PairedMac {
        PairedMac(bridgeID: link.bridgeID, name: link.macName, deviceID: "d1", pin: link.pin, endpoints: link.endpoints, pairedAt: Fixture.t0)
    }
}

extension BridgeInfo {
    static func test(methods: Set<String>? = nil, resumed: Bool = false) -> BridgeInfo {
        BridgeInfo(
            bridgeVersion: "0.1", macName: "Studio Mac", pebbleRunning: true, pebbleVersion: "1.9.28",
            methods: methods ?? [
                "state", "get_chat", "send", "cancel", "run_pause", "run_resume", "approve", "reject", "approve_simple",
                "reject_simple", "question_answer", "question_cancel", "setting", "chat_rename", "chat_search", "new_chat",
                "remote.status", "remote.keep_awake", "remote.chat_tail", "remote.chat_before", "remote.revoke_device",
            ], elevated: ["approve", "approve_simple", "setting"], resumed: resumed)
    }
}

/// Waits (briefly) until the condition holds; the store handles updates on its own task.
@MainActor
func eventually(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
