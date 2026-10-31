import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// Lane Z, item 4: Settings › Memory reads and changes what Pebble remembers as Pebble's Memory settings do
// (AdvancedSettings.vue, MemoryContests.vue; app.py memory_list, memory_delete, memory_contests,
// memory_resolve_contest).

@MainActor
private func memoryStore(
    elevated: Set<String> = ["approve", "memory_delete", "memory_clear"],
    answer: @escaping @Sendable (String, JSONValue) throws -> JSONValue? = { _, _ in nil }
) async -> (RemoteStore, FakeClient) {
    let fake = FakeClient { method, params in
        if let answer = try answer(method, params) { return answer }
        switch method {
        case "state": return Fixture.stateJSON()
        case "get_chat", "remote.chat_tail": return Fixture.chatDetail()
        default: return .bool(true)
        }
    }
    let store = RemoteStore(client: fake)
    let methods: Set<String> = [
        "state", "get_chat", "memory_list", "memory_delete", "memory_contests", "memory_resolve_contest", "setting",
    ]
    fake.push(.status(ConnectionStatus(phase: .connected, route: .lan, roundTrip: 6)))
    fake.push(
        .welcome(
            BridgeInfo(
                bridgeVersion: "0.1", macName: "Studio Mac", pebbleRunning: true, pebbleVersion: "1.9.29",
                methods: methods, elevated: elevated, resumed: false)))
    _ = await eventually { store.pebble != nil }
    return (store, fake)
}

private let groups: JSONValue = [
    "groups": [
        [
            "memory_id": "m2", "kind": "profile", "label": "spelling", "content": "Write in British spelling.",
            "scope": "global", "origin": "direct-user", "created": 1_761_000_000,
            "counterparts": [
                [
                    "memory_id": "m3", "kind": "profile", "label": "spelling", "content": "Write in American spelling.",
                    "scope": "global", "origin": "conversation", "created": 1_760_000_000,
                ]
            ],
        ]
    ],
    "authorization": "none",
]

struct MemoryModelTests {
    @Test func aRecordReadsPebblesRow() throws {
        let record = try #require(
            MemoryRecord(json: [
                "id": "m1", "kind": "semantic", "content": "The app supports iOS 26.", "scope": "/Users/me/app",
                "chat_id": "c1", "origin": "auto-learned", "created": 1_761_000_000, "updated": 1_761_000_100,
                "expires": .null, "learning_status": "contested",
                "provenance": #"{"evidence_class":"attributed_file_quote","witness":"x"}"#,
            ]))
        #expect(record.kind == "semantic" && record.scope == "/Users/me/app" && record.chatID == "c1")
        #expect(record.updated == Date(timeIntervalSince1970: 1_761_000_100) && record.expires == nil)
        #expect(record.learningStatus == "contested" && record.evidenceClass == "attributed_file_quote")
        #expect(MemoryRecord(json: ["kind": "semantic"]) == nil)
        #expect(MemoryRecord(json: ["id": "m1", "kind": "semantic", "provenance": "not json"])?.evidenceClass == nil)
    }

    @Test func aContestReadsItsMemoryAndTheOnesThatDisagree() throws {
        let contest = try #require(groups["groups"]?.array?.first.flatMap(ContestedMemory.init(json:)))
        #expect(contest.id == "m2" && contest.record.label == "spelling" && contest.record.origin == "direct-user")
        #expect(contest.counterparts.map(\.memoryID) == ["m3"])
        #expect(ContestDecision.keep.forgets(in: contest).map(\.memoryID) == ["m3"])
        #expect(ContestDecision.reject.forgets(in: contest).map(\.memoryID) == ["m2"])
        #expect(ContestDecision.keepBoth.forgets(in: contest).isEmpty)
        #expect(ContestDecision.keepBoth.rawValue == "keep_both")
    }
}

@MainActor
@Test func aLayerIsReadAPageAtATimeWithPebblesSearch() async throws {
    let rows: JSONValue = .array((1...100).map { ["id": .string("m\($0)"), "kind": "semantic", "content": "fact"] })
    let (store, fake) = await memoryStore { method, _ in method == "memory_list" ? rows : nil }
    let page = try await store.memories(in: "semantic", matching: "  release   notes ", after: 100)
    #expect(page.records.count == 100 && page.hasMore)
    #expect(fake.calls("memory_list").last?.params == ["kind": "semantic", "query": "release   notes", "offset": 100, "limit": 100])
}

@MainActor
@Test func theWorkingLayerTakesNoSearchOrPage() async throws {
    let rows: JSONValue = [["id": "c1", "kind": "working", "content": "{}", "scope": "chat:c1", "origin": "broker"]]
    let (store, fake) = await memoryStore { method, _ in method == "memory_list" ? rows : nil }
    let page = try await store.memories(in: "working", matching: "login")
    #expect(page.records.map(\.id) == ["c1"] && !page.hasMore)
    #expect(fake.calls("memory_list").last?.params == ["kind": "working"])
}

@MainActor
@Test func forgettingAsksFaceIDAsTheBridgeElevatesIt() async throws {
    let (store, fake) = await memoryStore()
    let record = MemoryRecord(id: "m1", kind: "profile", content: "Prefers short replies.")
    try await store.forget(record, words: "Prefers short replies.")
    let call = try #require(fake.calls("memory_delete").last)
    #expect(call.elevated && call.params == ["id": "m1", "kind": "profile"])
    #expect(call.reason == "Forget this memory: Prefers short replies.")
}

@MainActor
@Test func contestsAreReadAndDecidedWithoutFaceIDUnlessTheBridgeAsks() async throws {
    let (store, fake) = await memoryStore { method, params in
        switch method {
        case "memory_contests": return groups
        case "memory_resolve_contest":
            return ["memory_id": params["memory_id"] ?? .null, "decision": params["decision"] ?? .null, "forgotten": ["m3"]]
        default: return nil
        }
    }
    let contests = try await store.contestedMemories()
    let contest = try #require(contests.first)
    let forgotten = try await store.resolve(contest, .keep, question: "Keep this memory?")
    #expect(forgotten == 1)
    let call = try #require(fake.calls("memory_resolve_contest").last)
    #expect(!call.elevated && call.params == ["memory_id": "m2", "decision": "keep"])
}

@MainActor
@Test func aBridgeThatElevatesDecisionsGetsFaceID() async throws {
    let (store, fake) = await memoryStore(elevated: ["memory_delete", "memory_resolve_contest"]) { method, _ in
        method == "memory_resolve_contest" ? ["memory_id": "m2", "decision": "reject"] : nil
    }
    let contest = ContestedMemory(record: .init(memoryID: "m2", kind: "profile", content: "x"), counterparts: [])
    #expect(try await store.resolve(contest, .reject, question: "Remove this memory?") == nil)  // Pebble didn't say
    #expect(fake.calls("memory_resolve_contest").last?.elevated == true)
}

@MainActor
@Test func pebblesRefusalIsShownInItsWords() async throws {
    let (store, _) = await memoryStore { method, _ in
        if method == "memory_delete" {
            throw RemoteCallError.refused(PersonFacingError(message: "Stop the current task before forgetting memories."))
        }
        return nil
    }
    await #expect(throws: RemoteCallError.self) {
        try await store.forget(MemoryRecord(id: "m1", kind: "profile", content: "x"), words: "x")
    }
    #expect(store.notice?.message == "Stop the current task before forgetting memories.")
}

// MARK: - The demo

@MainActor
@Test func theDemoRemembersSomethingInEveryLayerAndOnePairDisagrees() async throws {
    let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.start()
    // The layers come with the first state (an empty list would satisfy allSatisfy at once).
    #expect(await eventually { !store.memoryLayers.isEmpty && store.memoryLayers.allSatisfy { ($0.count ?? 0) > 0 } })
    #expect(store.memoryLayers.map(\.id) == RemoteStore.memoryLayerNames)
    let preferences = try await store.memories(in: "profile")
    #expect(preferences.records.count == 3 && preferences.records.contains { $0.learningStatus == "contested" })
    let found = try await store.memories(in: "profile", matching: "british")
    #expect(found.records.map(\.id) == ["mem-pref-2"])
    let contests = try await store.contestedMemories()
    #expect(contests.count == 1 && contests.first?.counterparts.count == 1)
}

@MainActor
@Test func theDemoRefusesToForgetOrDecideWhileATaskRunsThenDoesBoth() async throws {
    let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.start()
    #expect(await eventually { store.pebble != nil && store.isPebbleWorking })
    let contest = try #require(try await store.contestedMemories().first)
    await #expect(throws: RemoteCallError.self) { try await store.resolve(contest, .keep, question: "Keep this memory?") }
    #expect(store.notice?.message == "Wait for the current task before resolving a memory conflict.")
    try await store.stop(chat: DemoData.loginChat)
    #expect(await eventually { !store.isPebbleWorking })
    #expect(try await store.resolve(contest, .keep, question: "Keep this memory?") == 1)
    #expect(try await store.contestedMemories().isEmpty)
    let preferences = try await store.memories(in: "profile")
    #expect(!preferences.records.contains { $0.id == "mem-pref-3" })
    let first = try #require(preferences.records.first)
    try await store.forget(first, words: "x")
    #expect(try await store.memories(in: "profile").records.count == preferences.records.count - 1)
}
