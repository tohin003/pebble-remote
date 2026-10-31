import Foundation
import PebbleProtocol

/// What the demo's Pebble remembers (lane Z, item 4), shaped as Pebble stores it (memory.py, app.py memory_list,
/// memory_contests, memory_resolve_contest): a few memories in each layer, from the demo's own conversations, and one
/// pair that disagrees ("British spelling" against "American spelling"), so Settings › Memory shows every part. Like
/// Pebble, it refuses to forget or decide while a task runs.
struct DemoMemory {
    struct Memory {
        var id: String
        var kind: String
        var content: String
        var scope: String
        var chatID: String?
        var origin: String
        var updated: Date
        var expires: Date?
        var evidence: String?
        var contested = false

        var json: JSONValue {
            [
                "id": .string(id), "kind": .string(kind), "content": .string(content), "scope": .string(scope),
                "chat_id": chatID.map(JSONValue.string) ?? .null, "origin": .string(origin),
                "created": .double(updated.timeIntervalSince1970), "updated": .double(updated.timeIntervalSince1970),
                "expires": expires.map { JSONValue.double($0.timeIntervalSince1970) } ?? .null,
                "learning_status": contested ? JSONValue.string("contested") : .null,
                "provenance": evidence.map { JSONValue.string(#"{"evidence_class":"\#($0)"}"#) } ?? .null,
            ]
        }
    }

    /// memory.py KINDS, in Pebble's order, with Pebble's names.
    static let kinds: [(id: String, name: String)] = [
        ("working", "Working context"), ("episodic", "Past experiences"), ("semantic", "Facts & knowledge"),
        ("procedural", "Procedures"), ("temporal", "Time-sensitive information"), ("profile", "Your preferences"),
    ]

    var memories: [Memory]
    /// Contested memory id → the ids that disagree with it.
    var contests: [String: [String]]

    init(now: Date) {
        func ago(_ seconds: Double) -> Date { now.addingTimeInterval(-seconds) }
        let web = "/Users/you/Projects/pebble-web"
        memories = [
            Memory(
                id: DemoData.loginChat, kind: "working",
                content: #"{"current_goal":"Fix the login redirect loop","phase":"running_tests","actions":[{"kind":"edit","path":"src/auth/session.ts","status":"applied"},{"kind":"tests","status":"running"}]}"#,
                scope: "chat:" + DemoData.loginChat, chatID: DemoData.loginChat, origin: "broker", updated: ago(40)),
            Memory(
                id: "mem-episode-1", kind: "episodic",
                content: #"{"user_request":"Summarize this week's commits for the changelog.","task_outcome":"completed","tool_steps":{"command":2}}"#,
                scope: web, chatID: DemoData.commitsChat, origin: "conversation", updated: ago(2 * 3600)),
            Memory(
                id: "mem-episode-2", kind: "episodic",
                content: #"{"claim_class":"observed_outcome","observation":"npm test passes in pebble-web after a fresh npm install."}"#,
                scope: web, origin: "auto-learned", updated: ago(26 * 3600), evidence: "host_lesson"),
            Memory(
                id: "mem-fact-1", kind: "semantic",
                content: #"{"quote":"The app supports iOS 26 and later.","path":"README.md"}"#, scope: "/Users/you/Projects/pebble-docs",
                origin: "auto-learned", updated: ago(9 * 60), evidence: "attributed_file_quote"),
            Memory(
                id: "mem-fact-2", kind: "semantic", content: "The staging site is staging.pebble-web.dev; production deploys need a review.",
                scope: web, origin: "user", updated: ago(3 * 86400)),
            Memory(
                id: "mem-recipe-1", kind: "procedural", content: #"{"recipe":"npm test","language":"JavaScript"}"#,
                scope: web, origin: "auto-learned", updated: ago(26 * 3600)),
            Memory(
                id: "mem-weather-1", kind: "temporal",
                content: #"{"place":"Lisbon","date":"Saturday","temperature_c":24,"forecast_low_c":17,"forecast_high_c":25}"#,
                scope: "global", chatID: DemoData.weatherChat, origin: "auto-learned", updated: ago(3 * 86400),
                expires: now.addingTimeInterval(2 * 86400), evidence: "weather_service"),
            Memory(
                id: "mem-pref-1", kind: "profile", content: "Prefers short replies with the exact commands to run.",
                scope: "global", origin: "direct-user", updated: ago(5 * 86400), evidence: "human_preference"),
            Memory(
                id: "mem-pref-2", kind: "profile", content: "Write documents in British spelling.", scope: "global",
                origin: "direct-user", updated: ago(86400), evidence: "human_preference", contested: true),
            Memory(
                id: "mem-pref-3", kind: "profile", content: "Write documents in American spelling.", scope: "global",
                chatID: DemoData.readmeChat, origin: "conversation", updated: ago(12 * 86400)),
        ]
        contests = ["mem-pref-2": ["mem-pref-3"]]
    }

    // MARK: Calls

    /// `memory_list {kind, query?, offset?, limit?}`: newest first; the working layer ignores the search and pages.
    func list(_ params: JSONValue) throws -> JSONValue {
        let kind = params["kind"]?.string
        if let kind, !Self.kinds.contains(where: { $0.id == kind }) { throw Self.refusal("Unknown memory type.") }
        let query = (params["query"]?.string ?? "").lowercased().split(whereSeparator: \.isWhitespace)
        var rows = memories.filter { kind == nil || $0.kind == kind }.sorted { $0.updated > $1.updated }
        if kind != "working" {
            rows = rows.filter { memory in query.allSatisfy { memory.content.lowercased().contains($0) } }
            let offset = max(0, params["offset"]?.int ?? 0)
            let limit = min(300, max(1, params["limit"]?.int ?? 300))
            rows = Array(rows.dropFirst(offset).prefix(limit))
        }
        return .array(rows.map(\.json))
    }

    /// `memory_delete {id, kind}`.
    mutating func delete(_ params: JSONValue, taskRunning: Bool) throws -> JSONValue {
        if taskRunning { throw Self.refusal("Stop the current task before forgetting memories.") }
        guard let id = params["id"]?.string, memories.contains(where: { $0.id == id }) else {
            throw Self.refusal("Memory not found.")
        }
        forget([id])
        return ["forgotten": true]
    }

    /// `memory_contests`.
    func contestsJSON() -> JSONValue {
        func describe(_ id: String) -> JSONValue? {
            guard let memory = memories.first(where: { $0.id == id }) else { return nil }
            return [
                "memory_id": .string(memory.id), "kind": .string(memory.kind), "label": "spelling",
                "content": .string(memory.content), "scope": .string(memory.scope), "origin": .string(memory.origin),
                "created": .double(memory.updated.timeIntervalSince1970),
            ]
        }
        let groups = contests.keys.sorted().compactMap { id -> JSONValue? in
            guard case .object(var group)? = describe(id) else { return nil }
            group["counterparts"] = .array((contests[id] ?? []).compactMap(describe))
            return .object(group)
        }
        return ["groups": .array(groups), "authorization": "none"]
    }

    /// `memory_resolve_contest {memory_id, decision}`.
    mutating func resolve(_ params: JSONValue, taskRunning: Bool) throws -> JSONValue {
        if taskRunning { throw Self.refusal("Wait for the current task before resolving a memory conflict.") }
        guard let id = params["memory_id"]?.string, let others = contests[id] else {
            throw Self.refusal("That memory is not contested.")
        }
        let decision = params["decision"]?.string ?? ""
        let forgotten: [String]
        switch decision {
        case "keep": forgotten = others
        case "reject": forgotten = [id]
        case "keep_both": forgotten = []
        default: throw Self.refusal("Choose keep, reject or keep_both.")
        }
        contests[id] = nil
        if let index = memories.firstIndex(where: { $0.id == id }) { memories[index].contested = false }
        forget(forgotten)
        return [
            "memory_id": .string(id), "decision": .string(decision), "forgotten": .array(forgotten.sorted().map(JSONValue.string)),
            "authorization": "none",
        ]
    }

    // MARK: Reading

    /// `state().memory`: whether memory is on, and each layer with its count and switch (memory.py `stats`).
    func stats(enabled: Bool, layers: JSONValue?) -> JSONValue {
        [
            "enabled": .bool(enabled),
            "types": .array(Self.kinds.map { kind -> JSONValue in
                [
                    "id": .string(kind.id), "name": .string(kind.name),
                    "count": .int(memories.count { $0.kind == kind.id }),
                    "enabled": .bool(layers?[kind.id]?.bool ?? true),
                ]
            }),
        ]
    }

    /// "/memory": Pebble's reply's shape (runtime_commands.py).
    func statusReply() -> String {
        "Personalized memory: on.\n\n"
            + Self.kinds.map { kind in "- \(kind.name): \(memories.count { $0.kind == kind.id }) records; on" }
                .joined(separator: "\n")
            + "\n\nNo proposed memories. Memory never grants permissions."
    }

    private mutating func forget(_ ids: [String]) {
        memories.removeAll { ids.contains($0.id) }
        for (contested, others) in contests {
            if ids.contains(contested) {
                contests[contested] = nil
            } else {
                contests[contested] = others.filter { !ids.contains($0) }
                if contests[contested]?.isEmpty == true { contests[contested] = nil }
            }
        }
        for index in memories.indices where contests[memories[index].id] == nil { memories[index].contested = false }
    }

    static func refusal(_ message: String) -> RemoteCallError {
        .refused(PersonFacingError(message: message))
    }
}
