import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

/// Lane G: Pebble's views on the phone (contract 3.12). The conversation's views come with get_chat and `artifact`
/// events; a waiting form shows as its question; activity items with views group into the transcript's cards; the
/// calls send exactly Pebble's params; the demo shows every kind and asks with a form.
@MainActor
struct ViewsKitTests {
    nonisolated static let formData: JSONValue = [
        "fields": [
            [
                "id": "port", "label": "Which port?", "type": "choice", "required": true,
                "options": [["id": "a", "label": "4174"], ["id": "b", "label": "5173"]],
            ]
        ]
    ]

    nonisolated static func formRow(question status: String) -> JSONValue {
        [
            "id": "a1", "chat_id": "c1", "title": "Choose a port", "kind": "form", "revision": 1, "status": "ready",
            "created": 1, "data": formData,
            "form_question": ["id": "q1", "revision": 1, "status": .string(status), "answer": .null],
        ]
    }

    nonisolated static let question: JSONValue = [
        "id": "q1", "run_id": "r1", "chat_id": "c1", "revision": 1, "required": true, "status": "pending", "created": 2,
        "items": [["id": "port", "title": "Which port?", "options": [["id": "a", "label": "4174"], ["id": "b", "label": "5173"]]]],
    ]

    static func item(_ seq: Int, _ view: JSONValue, status: String = "done") -> JSONValue {
        [
            "chat_id": "c1", "run_id": "r1",
            "item": [
                "seq": .int(seq), "at": .double(Double(seq)), "kind": "tool", "label": .string("Step \(seq)"), "detail": .null,
                "duration": 1, "status": .string(status), "view": view,
            ],
        ]
    }

    static func demo() async -> RemoteStore {
        let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
        let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
        store.clock = { Fixture.t0 }
        store.start()
        _ = await eventually { store.pebble != nil && store.chats.count == DemoData.seededChats }
        return store
    }

    // MARK: - The world

    @Test func aWaitingFormShowsAsItsQuestion() throws {
        var world = PebbleWorld()
        let detail = try #require(
            ChatDetailDTO(json: [
                "id": "c1", "title": "Deploy", "updated": 1, "messages": [], "actions": [], "runs": [],
                "questions": [Self.question], "artifacts": [Self.formRow(question: "pending")],
            ]))
        #expect(detail.artifacts.count == 1)
        world.load(detail)
        guard case .question(let card)? = world.waitingItems().first else {
            Issue.record("the form's question should wait")
            return
        }
        #expect(card.form?.id == "a1" && card.form?.waitsForAnswer == true)
        #expect(world.views(in: "c1").map(\.id) == ["a1"])
    }

    @Test func artifactEventsKeepTheConversationsViews() {
        var world = PebbleWorld()
        // Published: the whole row, with its question's id (app.py UIRender).
        var published = Self.formRow(question: "pending")
        if case .object(var row) = published {
            row["form_question"] = nil
            row["question_id"] = "q1"
            row["status"] = "awaiting_user_input"
            published = .object(row)
        }
        world.apply(Fixture.event("artifact", published))
        #expect(world.views(in: "c1").first?.formQuestion?.id == "q1")
        #expect(world.views(in: "c1").first?.waitsForAnswer == true)
        // Answered (artifact_submit's event): only the id, the revision and the status.
        world.apply(Fixture.event("artifact", ["chat_id": "c1", "id": "a1", "revision": 1, "status": "answered"], seq: 2))
        #expect(world.views(in: "c1").first?.waitsForAnswer == false)
        #expect(world.views(in: "c1").first?.formQuestion?.status == "answered")
        // Stopped: the row again, a revision on; the question it had is kept.
        world.apply(
            Fixture.event(
                "artifact",
                ["chat_id": "c1", "id": "a1", "kind": "form", "title": "Choose a port", "revision": 2, "status": "stopped",
                 "data": Self.formData], seq: 3))
        #expect(world.views(in: "c1").first?.status == .stopped && world.views(in: "c1").first?.formQuestion?.id == "q1")
        #expect(world.views(in: "c1").count == 1)
    }

    @Test func activityViewsGroupIntoTranscriptCards() {
        var world = PebbleWorld()
        world.apply(Fixture.event("activity", Self.item(64, ["v": 1, "type": "read", "path": "a.py", "total": 10])))
        world.apply(Fixture.event("activity", Self.item(128, ["v": 1, "type": "search", "query": "x", "hits": 2]), seq: 2))
        world.apply(
            Fixture.event("activity", Self.item(192, ["v": 1, "type": "edit", "path": "a.py", "added": 3, "removed": 1]), seq: 3))
        world.apply(Fixture.event("activity", Self.item(256, ["v": 1, "type": "hologram"]), seq: 4))
        world.apply(Fixture.event("activity", Self.item(320, .null), seq: 5))
        let lines = world.workLines(for: "c1")
        guard case .card(let explored)? = lines["r1/h64"], case .card(let files)? = lines["r1/h192"] else {
            Issue.record("the reads and the edit should be cards")
            return
        }
        #expect(explored.kind == .explored && explored.items.count == 2)
        #expect(files.kind == .files && files.diff.added == 3)
        #expect(lines["r1/h128"] == .folded)
        #expect(lines["r1/h256"] == .unreadable)  // a type this version doesn't know (spec rule 1)
        #expect(lines["r1/h320"] == nil)  // no view: today's line

        world.apply(
            Fixture.event(
                "plan",
                ["chat_id": "c1", "run_id": "r1", "revision": 1,
                 "steps": [["title": "Read", "status": "completed"], ["title": "Fix", "status": "in_progress"]]], seq: 6))
        #expect(world.plans["r1"]?.done == 1 && world.plans["r1"]?.total == 2)
    }

    // MARK: - The calls

    @Test func submittingAFormSendsPebblesParamsWithoutFaceID() async throws {
        let fake = FakeClient { _, _ in ["question_id": "q1", "status": "answered"] }
        let store = RemoteStore(client: fake)
        let form = try #require(PebbleArtifact(json: Self.formRow(question: "pending")))
        try await store.submit(["port": .option("b")], to: form)
        let call = try #require(fake.calls("artifact_submit").first)
        #expect(call.params == ["chat_id": "c1", "id": "a1", "revision": 1, "answers": ["port": ["option_id": "b"]]])
        #expect(!call.elevated)  // contract 3.6 doesn't list it: the unlock and an idem
    }

    @Test func readingAViewSendsItsConversationAndID() async throws {
        let fake = FakeClient { _, _ in Self.formRow(question: "answered") }
        let store = RemoteStore(client: fake)
        let view = try await store.readView("a1", in: "c1")
        #expect(view.formQuestion?.status == "answered")
        #expect(fake.calls("artifact_get").first?.params == ["chat_id": "c1", "id": "a1"])
    }

    // MARK: - The demo

    @Test func theDemoShowsEveryKind() async throws {
        let store = await Self.demo()
        let commits = store.transcript(for: DemoData.commitsChat)
        #expect(await eventually { commits.views.count == 5 })
        var kinds = Set(commits.views.map(\.kind))
        for chat in [DemoData.loginChat, DemoData.deployChat, DemoData.readmeChat, DemoData.emailsChat, DemoData.weatherChat, DemoData.siteChat] {
            kinds.formUnion(store.views(in: chat).map(\.kind))
            let transcript = store.transcript(for: chat)
            _ = await eventually { !transcript.views.isEmpty }
            kinds.formUnion(transcript.views.map(\.kind))
        }
        #expect(kinds.isSuperset(of: Set(NativeView.kinds)))
        let steps = try await store.runSteps("r-commits", in: DemoData.commitsChat)
        #expect(steps.details.items.contains { $0.view != nil })
        #expect(steps.details.summary?.commands?.count == 1 && steps.details.summary?.commands?.failed == 0)
    }

    @Test func theDemoAsksWithAFormAndTakesItsAnswers() async throws {
        let store = await Self.demo()
        try await store.stop(chat: DemoData.loginChat)
        #expect(await eventually { !store.liveRuns.contains { $0.id == DemoData.loginRun } })
        try await store.send("Deploy it again", in: DemoData.deployChat)
        func waitingForm() -> QuestionCard? {
            store.waiting.lazy.compactMap { item -> QuestionCard? in
                if case .question(let card) = item, card.form != nil { card } else { nil }
            }.first
        }
        #expect(await eventually { waitingForm() != nil })
        let form = try #require(waitingForm()?.form)
        #expect(form.waitsForAnswer && form.form?.fields.count == 2)
        try await store.submit(["port": .option("p5173"), "share": .text("The web team")], to: form)
        #expect(await eventually { waitingForm() == nil })
    }
}
