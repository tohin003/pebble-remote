import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// Lane Z, item 1: what a long press on a conversation in Chats reads. Its preview's last line (never the transcript)
// and the conversation's project, for "New conversation in …".

@MainActor
private func menuStore(
    state: JSONValue = Fixture.stateJSON(),
    bridge: BridgeInfo = .test(),
    answer: @escaping @Sendable (String, JSONValue) throws -> JSONValue? = { _, _ in nil }
) async -> (RemoteStore, FakeClient) {
    let fake = FakeClient { method, params in
        if let answer = try answer(method, params) { return answer }
        switch method {
        case "state": return state
        case "get_chat", "remote.chat_tail": return Fixture.chatDetail()
        default: return .bool(true)
        }
    }
    let store = RemoteStore(client: fake)
    fake.push(.status(ConnectionStatus(phase: .connected, route: .lan, roundTrip: 6)))
    fake.push(.welcome(bridge))
    _ = await eventually { store.pebble != nil }
    return (store, fake)
}

struct ChatLastLineTests {
    @Test func markdownMarksAreTakenOut() {
        #expect(ChatLastLine.plain("## Done\n\nThe **redirect** loop is fixed in `session.ts`.") ==
            "Done The redirect loop is fixed in session.ts.")
        #expect(ChatLastLine.plain("- one\n- two\n3. three\n> quoted") == "one two three quoted")
        #expect(ChatLastLine.plain("See [the guide](https://example.com/guide) first.") == "See the guide first.")
        #expect(ChatLastLine.plain("```ts\nprocess.env.TZ = \"UTC\";\n```") == "process.env.TZ = \"UTC\";")
    }

    @Test func aHashTagOrNumberWithoutItsSpaceStays() {
        #expect(ChatLastLine.plain("#42 is merged") == "#42 is merged")
        #expect(ChatLastLine.plain("2024.10 release") == "2024.10 release")
    }

    @Test func nothingLeftMeansNoLine() {
        #expect(ChatLastLine.plain("") == nil)
        #expect(ChatLastLine.plain("```\n```") == nil)
        #expect(ChatLastLine.plain("   \n\n  ") == nil)
    }

    @Test func aLongMessageIsCutWithAnEllipsis() throws {
        let line = try #require(ChatLastLine.plain(String(repeating: "word ", count: 100)))
        #expect(line.count == ChatLastLine.limit)
        #expect(line.hasSuffix("\u{2026}"))
    }

    @Test func controlAndDirectionCharactersNeverReachTheLine() {
        // Each becomes a space, folded with its neighbours (PebbleWorld.clean, as activity lines are cleaned).
        #expect(ChatLastLine.plain("safe\u{202E}txt.exe\u{0007} done") == "safe txt.exe done")
    }

    @Test func theNewestMessageWithWordsWins() {
        let line = RemoteStore.newestLine([(role: .user, text: "Fix it"), (role: .assistant, text: "```\n```")])
        #expect(line == ChatLastLine(fromPerson: true, text: "Fix it"))
        #expect(RemoteStore.newestLine([]) == nil)
    }
}

@MainActor
@Test func theLastLineOfAConversationNotOpenHereIsOneSmallRead() async throws {
    let (store, fake) = await menuStore { method, _ in
        method == "remote.chat_tail"
            ? Fixture.chatDetail(messages: [
                Fixture.message("m1", "user", "Why does login loop?"),
                Fixture.message("m2", "assistant", "**Fixed.** The cookie expired too soon."),
            ]) : nil
    }
    let line = await store.lastLine(of: "c1")
    #expect(line == ChatLastLine(fromPerson: false, text: "Fixed. The cookie expired too soon."))
    let read = try #require(fake.calls("remote.chat_tail").last)
    #expect(read.params == ["id": "c1", "limit": 3])
}

@MainActor
@Test func theLastLineOfAnOpenConversationNeedsNoRead() async throws {
    let (store, fake) = await menuStore { method, _ in
        method == "remote.chat_tail" || method == "get_chat"
            ? Fixture.chatDetail(messages: [Fixture.message("m1", "user", "Run the tests")]) : nil
    }
    let transcript = store.transcript(for: "c1")
    #expect(await eventually { !transcript.isLoading && !transcript.items.isEmpty })
    let reads = fake.calls("remote.chat_tail").count
    #expect(await store.lastLine(of: "c1") == ChatLastLine(fromPerson: true, text: "Run the tests"))
    #expect(fake.calls("remote.chat_tail").count == reads)
}

@MainActor
@Test func withoutTheReadThePreviewShowsTheTitleAlone() async throws {
    let (store, fake) = await menuStore(bridge: .test(methods: ["state", "get_chat", "chat_rename"]))
    #expect(await store.lastLine(of: "c1") == nil)
    #expect(fake.calls("remote.chat_tail").isEmpty && fake.calls("get_chat").isEmpty)
}

@MainActor
@Test func aConversationsProjectIsAPlaceForANewOne() async throws {
    let state = Fixture.stateJSON(chats: [
        Fixture.chatRow("c1", "Fix the login redirect loop", workspace: "/Users/me/Projects/pebble-web"),
        Fixture.chatRow("c2", "Weather"),
    ])
    let (store, _) = await menuStore(state: state)
    #expect(store.project(of: "c1") == ProjectRef(path: "/Users/me/Projects/pebble-web", name: "pebble-web"))
    #expect(store.project(of: "c2") == nil)
    #expect(store.project(of: "unknown") == nil)
}

// Lane Z, item 2: Retry asks the question a reply answers (App.vue `questionFor`).
struct RetryQuestionTests {
    static func message(_ id: String, _ role: MessageItem.Role, _ text: String) -> TranscriptItem {
        .message(MessageItem(id: id, role: role, text: text))
    }

    @Test func theQuestionIsThePersonsNewestMessageBeforeTheReply() {
        let items: [TranscriptItem] = [
            Self.message("m1", .user, "First"), Self.message("m2", .assistant, "One"),
            .activity(id: "a1", runID: "r1", text: "Reading App.vue", status: .reading),
            Self.message("m3", .user, "Second"), Self.message("m4", .assistant, "Two"),
        ]
        #expect(RemoteStore.question(before: "m4", in: items)?.text == "Second")
        #expect(RemoteStore.question(before: "m2", in: items)?.text == "First")
        #expect(RemoteStore.question(before: "m1", in: items) == nil)
        #expect(RemoteStore.question(before: "missing", in: items) == nil)
    }
}
