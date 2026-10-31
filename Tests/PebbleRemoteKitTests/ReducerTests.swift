import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// The reducer, event by event, with payloads as Pebble emits them.

private func messages(_ world: PebbleWorld, _ chat: ChatID = "c1") -> [MessageItem] {
    world.transcriptItems(for: chat).compactMap { if case .message(let m) = $0 { m } else { nil } }
}

@Test func stateGivesTheOverviewAndTheConversationList() throws {
    var world = PebbleWorld()
    #expect(world.overview() == nil)
    let state = try #require(
        StateDTO(
            json: Fixture.stateJSON(chats: [
                Fixture.chatRow("c1", "Fix the login redirect loop", workspace: "/Users/me/Projects/pebble-web", updated: 10),
                Fixture.chatRow("c2", "", updated: 20),
            ])))
    let change = world.load(state)
    #expect(change.overview && change.chats && change.runs && change.waiting)
    let overview = try #require(world.overview())
    #expect(overview.version == "1.9.28")
    #expect(overview.mode == .ask)
    #expect(overview.fastReplies == .longTasks)
    #expect(overview.modelName == "gpt-5.1")
    #expect(overview.effort == "medium")
    #expect(overview.modelOnline)
    #expect(!overview.stealth && !overview.screenControl)
    let chats = world.chatSummaries()
    #expect(chats.map(\.id) == ["c2", "c1"])  // newest activity first
    #expect(chats[0].title == "New conversation")  // Pebble's name for an untitled one
    #expect(chats[1].project == "pebble-web")
    #expect(chats[1].status == nil && chats[1].waitingCount == 0)
}

@Test func tokensAssembleAStreamingReplyThatCompleteEnds() throws {
    var world = Fixture.world(messages: [Fixture.message("m1", "user", "Why does sign-in loop?", at: 0)])
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "queued"], at: 1))
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "running"], at: 2))
    #expect(world.liveRuns().first?.status == .thinking)
    #expect(world.liveRuns().first?.started == Fixture.at(2))

    let first = world.apply(Fixture.event("token", ["chat_id": "c1", "id": "m2", "text": "The cookie"], at: 3))
    #expect(first.transcripts == ["c1"])
    #expect(first.runs)  // the run now shows "writing"
    let second = world.apply(Fixture.event("token", ["chat_id": "c1", "id": "m2", "text": " was Strict."], at: 3.1))
    #expect(!second.runs)  // still writing: nothing else to republish
    var reply = try #require(messages(world).last)
    #expect(reply.id == "m2" && reply.role == .assistant)
    #expect(reply.text == "The cookie was Strict.")
    #expect(reply.isStreaming)
    #expect(reply.runID == "r1")
    #expect(world.liveRuns().first?.status == .writing)
    #expect(world.chatSummaries().first?.status == .writing)

    world.apply(Fixture.event("usage", ["chat_id": "c1", "id": "m2", "usage": ["input_tokens": 1200]], at: 4))
    world.apply(Fixture.event("complete", ["chat_id": "c1", "id": "m2", "seconds": 12.3], at: 4))
    reply = try #require(messages(world).last)
    #expect(!reply.isStreaming)
    #expect(reply.text == "The cookie was Strict.")

    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "completed", "elapsed": 11.8], at: 4.1))
    #expect(world.liveRuns().isEmpty)
    #expect(world.chatSummaries().first?.status == nil)
    #expect(world.transcriptItems(for: "c1").last == .runEnd(id: "end-r1", runID: "r1", state: .completed, seconds: 11.8, note: nil))

    let idle = world.apply(Fixture.event("idle", ["chat_id": "c1", "run_id": "r1"], at: 4.2))
    #expect(idle.needsState)
    #expect(idle.needsChats == ["c1"])  // App.vue reads the conversation back on idle
}

@Test func stoppedEndsTheReplyAndTheRunEndsStopped() throws {
    var world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1")
    world.apply(Fixture.event("token", ["chat_id": "c1", "id": "m2", "text": "Half a"], at: 1))
    world.apply(Fixture.event("stopped", ["chat_id": "c1", "id": "m2"], at: 2))
    #expect(messages(world).last?.isStreaming == false)
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "stopped", "elapsed": 3], at: 2))
    #expect(world.transcriptItems(for: "c1").last == .runEnd(id: "end-r1", runID: "r1", state: .stopped, seconds: 3, note: nil))
    #expect(!world.isLive(chat: "c1"))
}

@Test func idleWithoutASettleEventEndsTheWorkWithoutClaimingAnOutcome() {
    var world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1")
    world.apply(Fixture.event("token", ["chat_id": "c1", "id": "m2", "text": "Work"], at: 1))
    world.apply(Fixture.event("idle", ["chat_id": "c1", "run_id": "r1"], at: 2))
    #expect(messages(world).last?.isStreaming == false)
    #expect(world.liveRuns().isEmpty)
    #expect(world.runs["r1"]?.row.state == .interrupted)
}

@Test func anErrorBecomesTheRunsNoteInPebblesWords() {
    var world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1")
    world.apply(Fixture.event("error", ["chat_id": "c1", "message": "The model gave no reply."], at: 1))
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "failed", "elapsed": 5], at: 2))
    let items = world.transcriptItems(for: "c1")
    #expect(
        items.dropLast().last
            == .runEnd(id: "end-r1", runID: "r1", state: .failed, seconds: 5, note: "The model gave no reply."))
    #expect(items.last?.id == "t/c1/r1")  // then Pebble's line for a failed task, with Resume (lane R)
    #expect(world.chatSummaries().first?.status == .error)
}

@Test func actionsReplaceTheConversationsCards() throws {
    var world = Fixture.world()
    let screenGrant: JSONValue = ["app": "Safari", "title": "Bank — Sign in", "why": "To read the statement", "full_access": false]
    let change = world.apply(
        Fixture.event(
            "actions",
            [
                "chat_id": "c1",
                "actions": [
                    Fixture.action("a1", kind: "edit", status: "applied", payload: ["path": "/p/src/App.vue", "baseline": "x"]),
                    Fixture.action("a2", at: 5),
                    Fixture.action("a3", kind: "screen_grant", payload: screenGrant, at: 6),
                ],
            ]))
    #expect(change.waiting && change.chats && change.transcripts == ["c1"])
    let waiting = world.waitingItems()
    #expect(waiting.count == 2)  // only pending cards wait
    guard case .review(let card) = waiting[0], case .review(let grant) = waiting[1] else {
        Issue.record("expected two cards")
        return
    }
    #expect(card.actionID == "a2" && card.kind == .command)
    #expect(card.title == "Run npm test")
    #expect(card.detail == "npm test")
    #expect(card.summary == "Runs this command in your project without changing files.")
    #expect(card.approveLabel == "Run command")
    #expect(!card.isSimple)
    #expect(card.chatTitle == "Fix the login redirect loop")
    #expect(card.created == Fixture.at(5))
    #expect(grant.isSimple)
    #expect(grant.title == "Use Safari")
    #expect(grant.approveLabel == "Allow")
    #expect(world.chatSummaries().first?.status == .review)
    #expect(world.chatSummaries().first?.waitingCount == 2)
    // The transcript ends with what waits.
    #expect(world.transcriptItems(for: "c1").suffix(2).map(\.id) == ["r/c1/a2", "r/c1/a3"])

    // Pebble's next list: the command ran, the window was allowed.
    world.apply(
        Fixture.event(
            "actions",
            ["chat_id": "c1", "actions": [Fixture.action("a2", status: "applied"), Fixture.action("a3", kind: "screen_grant", status: "applied")]]))
    #expect(world.waitingItems().isEmpty)
    #expect(world.chatSummaries().first?.status == nil)
}

@Test func questionsComeAndGoAndTheAnswerJoinsTheConversation() throws {
    var world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1")
    world.apply(
        Fixture.event(
            "question",
            ["chat_id": "c1", "run_id": "r1", "question_id": "q1", "status": "pending", "question": Fixture.question("q1", at: 3)]))
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "waiting_input"], at: 4))
    let waiting = world.waitingItems()
    guard case .question(let card) = try #require(waiting.first) else {
        Issue.record("expected a question")
        return
    }
    #expect(card.questionID == "q1" && card.runID == "r1" && card.revision == 1 && card.required)
    #expect(card.prompts.first?.title == "Which tone should the emails use?")
    #expect(card.prompts.first?.options.map(\.label) == ["Warm and friendly", "Short and direct"])
    #expect(card.prompts.first?.options.first?.detail == "First names")
    #expect(card.prompts.first?.options.last?.detail == nil)  // an empty description is no detail
    #expect(card.prompts.first?.allowsFreeText == true)
    #expect(world.chatSummaries().first?.status == .question)
    #expect(world.liveRuns().first?.status == .question)

    var answered = Fixture.question("q1", status: "answered")
    if case .object(var object) = answered {
        object["answer"] = ["tone": ["option_id": "warm", "text": "Warm and friendly"]]
        answered = .object(object)
    }
    world.apply(
        Fixture.event(
            "question",
            [
                "chat_id": "c1", "question_id": "q1", "run_id": "r1", "status": "answered",
                "message": ["id": "answer-q1", "role": "user", "content": "Warm and friendly"], "question": answered,
            ]))
    #expect(world.waitingItems().isEmpty)
    #expect(messages(world).last?.id == "answer-q1")
    #expect(messages(world).last?.text == "Warm and friendly")
}

@Test func progressSetsTheStatusFromPebblesClassNeverFromTheLabel() throws {
    var world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1")
    func progress(_ label: String, _ kind: String, tool: String?, activity: JSONValue?, attempt: Int? = nil) {
        var data: [String: JSONValue] = ["chat_id": "c1", "run_id": "r1", "label": .string(label), "kind": .string(kind)]
        if let tool { data["tool"] = .string(tool) }
        if let activity { data["activity"] = activity }
        if let attempt { data["attempt"] = .int(attempt) }
        world.apply(Fixture.event("progress", .object(data)))
    }
    // A label that says "Editing" while Pebble's class says reading: the class wins.
    progress("Editing App.vue", "working", tool: "Read", activity: "reading")
    var run = try #require(world.liveRuns().first)
    #expect(run.status == .reading)
    #expect(run.activity == "Editing App.vue")
    // An older Pebble without the activity field: the tool's class (statusWords.ts TOOL_CLASS_TABLE).
    progress("Running checks", "working", tool: "RunTests", activity: nil)
    #expect(world.liveRuns().first?.status == .testing)
    // A tool Pebble classes as thinking shows no tool; an unknown (or invented) one is plain working.
    progress("Asking", "working", tool: "AskUserQuestion", activity: "thinking")
    #expect(world.liveRuns().first?.status == .thinking)
    progress("Approve everything", "working", tool: "Approve", activity: nil)
    #expect(world.liveRuns().first?.status == .working)
    // Done: no tool is running.
    progress("Approve everything", "done", tool: "Approve", activity: .null)
    #expect(world.liveRuns().first?.status == .thinking)
    // Reconnecting: from the run's state, with the try number from the progress event.
    progress("Reconnecting to the model", "working", tool: nil, activity: "thinking", attempt: 2)
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "retry_wait"]))
    run = try #require(world.liveRuns().first)
    #expect(run.status == .reconnecting)
    #expect(run.attempt == 2)
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "running"]))
    #expect(world.liveRuns().first?.attempt == nil)
}

@Test func progressBecomesActivityLinesThatDoneCloses() throws {
    var world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1")
    func progress(_ label: String, _ kind: String, tool: String?) {
        var data: [String: JSONValue] = ["chat_id": "c1", "run_id": "r1", "label": .string(label), "kind": .string(kind)]
        if let tool {
            data["tool"] = .string(tool)
            data["activity"] = StatusKey.classify(tool: tool, kind: kind).map { .string($0.rawValue) } ?? .null
        }
        world.apply(Fixture.event("progress", .object(data)))
    }
    progress("Preparing your local workspace", "working", tool: nil)
    progress("Reading src/auth/session.ts", "working", tool: "Read")
    progress("Reading src/auth/session.ts", "done", tool: "Read")
    progress("Editing src/auth/session.ts", "working", tool: "Edit")
    progress("Editing src/auth/session.ts", "done", tool: "Edit")
    progress("Checking the result against the request", "review", tool: nil)
    progress("Line one\nline two\u{202E} with a\tbidi override and a very long tail that goes on past eighty characters easily", "blocked", tool: "Shell")
    let lines = world.transcriptItems(for: "c1").compactMap { item -> (String, StatusKey)? in
        if case .activity(_, _, let text, let status) = item { (text, status) } else { nil }
    }
    #expect(lines.count == 5)  // a done closes its own line instead of adding one
    #expect(lines[0] == ("Preparing your local workspace", .thinking))
    #expect(lines[1] == ("Reading src/auth/session.ts", .reading))
    #expect(lines[2] == ("Editing src/auth/session.ts", .editing))
    #expect(lines[3] == ("Checking the result against the request", .review))
    #expect(lines[4].1 == .blocked)
    #expect(lines[4].0.count == 80 && lines[4].0.hasSuffix("…"))
    #expect(!lines[4].0.contains("\n") && !lines[4].0.contains("\u{202E}"))
    // Lines come before the reply they led to.
    world.apply(Fixture.event("token", ["chat_id": "c1", "id": "m2", "text": "Fixed."]))
    let items = world.transcriptItems(for: "c1")
    #expect(items.last?.id == "m/m2")
    #expect(items.firstIndex { $0.id == "a/r1/0" }! < items.firstIndex { $0.id == "m/m2" }!)
}

@Test func theModelEventAndSettingsUpdateTheOverview() throws {
    var world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1")
    let change = world.apply(
        Fixture.event("model", ["state": "loading", "configured": true, "name": "Qwen 3.5 9B", "kind": "gguf", "context": 4096]))
    #expect(change.overview && change.runs)
    #expect(world.overview()?.modelName == "Qwen 3.5 9B")
    #expect(world.liveRuns().first?.status == .loading)  // a live run with nothing else to show waits on the model
    world.apply(Fixture.event("model", ["state": "error", "configured": true, "name": "Qwen 3.5 9B"]))
    #expect(world.overview()?.modelOnline == false)
    #expect(world.apply(Fixture.event("settings", [:])).needsState)
}

@Test func theReplyBannerKeepsPebblesWords() {
    var world = Fixture.world()
    let change = world.apply(
        Fixture.event("reply_banner", ["chat_id": "c1", "run_id": "r1", "title": "Pebble needs your review", "body": "Fix the login"]))
    #expect(change.banner)
    #expect(world.banner == ReplyBanner(chatID: "c1", runID: "r1", title: "Pebble needs your review", body: "Fix the login"))
}

@Test func theBridgesOwnEventsUpdateTheMac() throws {
    var world = Fixture.world()
    world.setBridge(macName: "Studio Mac", pebbleRunning: true, pebbleVersion: nil)
    world.apply(
        Fixture.event("remote.mac", ["battery_percent": 81, "charging": false, "on_power": false, "keep_awake": true]))
    let mac = try #require(world.macOverview())
    #expect(mac.name == "Studio Mac" && mac.batteryPercent == 81 && mac.onPower == false && mac.keepAwake)
    let stopped = world.apply(Fixture.event("remote.pebble", ["running": false, "version": .null]))
    #expect(stopped.mac && world.macOverview()?.pebbleRunning == false)
    #expect(world.apply(Fixture.event("remote.pebble", ["running": true, "version": "1.9.29"])).needsState)
    #expect(world.version == "1.9.29")
}

@Test func aResumedRunContinuesItsStoredReply() {
    var world = Fixture.world(
        runs: [Fixture.runRow("r1", chat: "c1", state: "waiting_approval")],
        messages: [Fixture.message("m1", "user", "Run the tests"), Fixture.message("m2", "assistant", "Before I finish, the tests.", run: "r1")])
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "queued"]))
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "running"]))
    world.apply(Fixture.event("token", ["chat_id": "c1", "id": "m2", "text": "\n\nAll 42 pass."]))
    let reply = messages(world).last
    #expect(reply?.text == "Before I finish, the tests.\n\nAll 42 pass.")
    #expect(reply?.isStreaming == true)
    #expect(messages(world).count == 2)
}

@Test func aReplyThatStreamedBeforeTheConversationOpenedIsKept() throws {
    var world = PebbleWorld()
    world.load(StateDTO(json: Fixture.stateJSON(runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1"))!)
    world.apply(Fixture.event("token", ["chat_id": "c1", "id": "m9", "text": "Streaming "]))
    world.apply(Fixture.event("token", ["chat_id": "c1", "id": "m9", "text": "before open."]))
    #expect(world.transcriptItems(for: "c1").isEmpty)  // not open yet
    world.load(ChatDetailDTO(json: Fixture.chatDetail(messages: [Fixture.message("m1", "user", "Go")]))!)
    let reply = try #require(messages(world).last)
    #expect(reply.id == "m9" && reply.text == "Streaming before open." && reply.isStreaming)
    // Pebble's stored copy replaces the stream when it arrives.
    world.apply(Fixture.event("complete", ["chat_id": "c1", "id": "m9", "seconds": 2]))
    world.load(
        ChatDetailDTO(
            json: Fixture.chatDetail(messages: [
                Fixture.message("m1", "user", "Go"), Fixture.message("m9", "assistant", "Streaming before open.", run: "r1"),
            ]))!)
    #expect(messages(world).map(\.id) == ["m1", "m9"])
    #expect(world.streams.isEmpty)
}

@Test func aCommandsReplyThatNeverStreamedIsReadBack() {
    var world = Fixture.world()
    let change = world.apply(Fixture.event("complete", ["chat_id": "c1", "id": "cmd-2", "seconds": 0]))
    #expect(change.needsChats == ["c1"])
}

@Test func thePersonsMessageShowsAtOnceAndPebblesCopyReplacesIt() {
    var world = Fixture.world(messages: [Fixture.message("m1", "user", "Hi")])
    world.addLocalMessage(chat: "c1", id: "local-1", text: "Also fix the tests", created: Fixture.at(5))
    #expect(messages(world).map(\.id) == ["m1", "local-1"])
    world.confirmLocalMessage(chat: "c1", localID: "local-1", messageID: "m7")
    #expect(messages(world).map(\.id) == ["m1", "m7"])
    world.load(
        ChatDetailDTO(json: Fixture.chatDetail(messages: [Fixture.message("m1", "user", "Hi"), Fixture.message("m7", "user", "Also fix the tests")]))!)
    #expect(messages(world).map(\.id) == ["m1", "m7"])
    #expect(world.timelines["c1"]?.local.isEmpty == true)
    world.addLocalMessage(chat: "c1", id: "local-2", text: "Refused", created: nil)
    world.removeLocalMessage(chat: "c1", id: "local-2")
    #expect(messages(world).map(\.id) == ["m1", "m7"])
}

@Test func aTailKeepsTheOlderMessagesAlreadyShownAndOlderPagesGoFirst() {
    var world = Fixture.world()
    world.load(ChatDetailDTO(json: Fixture.chatDetail(messages: [Fixture.message("m3", "user", "c"), Fixture.message("m4", "assistant", "d")], hasOlder: true))!)
    #expect(world.hasOlder(in: "c1"))
    world.loadOlder(OlderMessagesDTO(json: ["messages": [Fixture.message("m1", "user", "a"), Fixture.message("m2", "assistant", "b")], "has_older": false])!, chat: "c1")
    #expect(messages(world).map(\.id) == ["m1", "m2", "m3", "m4"])
    #expect(!world.hasOlder(in: "c1"))
    // A newer tail that overlaps keeps m1 and m2.
    world.load(ChatDetailDTO(json: Fixture.chatDetail(messages: [Fixture.message("m3", "user", "c"), Fixture.message("m4", "assistant", "d"), Fixture.message("m5", "user", "e")], hasOlder: true))!)
    #expect(messages(world).map(\.id) == ["m1", "m2", "m3", "m4", "m5"])
}

@Test func theStatusFollowsPebblesOrder() throws {
    var world = PebbleWorld()
    world.load(
        StateDTO(
            json: Fixture.stateJSON(
                chats: [
                    Fixture.chatRow("c1", "a", updated: 1), Fixture.chatRow("c2", "b", updated: 2),
                    Fixture.chatRow("c3", "c", updated: 3), Fixture.chatRow("c4", "d", updated: 4),
                    Fixture.chatRow("c5", "e", updated: 5), Fixture.chatRow("c6", "f", updated: 6),
                ],
                runs: [
                    Fixture.runRow("r1", chat: "c1", state: "needs_reconciliation"),
                    Fixture.runRow("r2", chat: "c2", state: "budget_exhausted"),
                    Fixture.runRow("r3", chat: "c3", state: "paused", created: 3),
                    Fixture.runRow("r4", chat: "c4", state: "completed"),
                    Fixture.runRow("r5a", chat: "c5", state: "completed", created: 1),
                    Fixture.runRow("r5b", chat: "c5", state: "waiting_approval", created: 0),
                    Fixture.runRow("r6", chat: "c6", state: "verification_required"),
                ]))!)
    let status = Dictionary(uniqueKeysWithValues: world.chatSummaries().map { ($0.id, $0.status) })
    #expect(status["c1"] == .uncertain)
    #expect(status["c2"] == .blocked)
    #expect(status["c3"] == .paused)
    #expect(status["c4"] == .some(nil))
    #expect(status["c5"] == .review)  // Pebble focuses the run waiting for approval over a newer finished one
    #expect(status["c6"] == .blocked)
    // Live runs: working or waiting in a way Stop can end.
    #expect(world.liveRuns().map(\.id) == ["r3", "r5b"])
    #expect(Set(RunState.pebbleStates.compactMap(\.statusKey)) == [.reconnecting, .question, .review, .blocked, .uncertain, .paused, .error])
}

@Test func stopEverythingStopsTheWorkingRunFirst() {
    var world = PebbleWorld()
    world.load(
        StateDTO(
            json: Fixture.stateJSON(
                chats: [Fixture.chatRow("c1", "a"), Fixture.chatRow("c2", "b")],
                runs: [
                    Fixture.runRow("r1", chat: "c1", state: "waiting_input", created: 5),
                    Fixture.runRow("r2", chat: "c2", state: "running", created: 1),
                    Fixture.runRow("r3", chat: "c2", state: "completed", created: 0),
                ], active: "c2", activeRun: "r2"))!)
    let targets = world.runsToStop()
    #expect(targets.map(\.run) == ["r2", "r1"])
    #expect(targets.map(\.live) == [true, false])
}

@Test func unknownEventsChangeNothing() {
    var world = Fixture.world()
    let before = world.transcriptItems(for: "c1")
    #expect(world.apply(Fixture.event("telemetry", ["x": 1])).isEmpty)
    // ("plan" was unknown here until 1.9.29's work view: ViewsKitTests covers it now.)
    #expect(world.apply(Fixture.event("forecast", ["chat_id": "c1", "run_id": "r1", "revision": 1, "steps": []])).isEmpty)
    #expect(world.apply(Fixture.event("token", ["chat_id": "c1"])).isEmpty)  // missing fields: ignored, never a crash
    #expect(world.transcriptItems(for: "c1") == before)
}

@Test func aRunsNoteKeepsOnlyTheSentencesMeantForThePerson() {
    #expect(
        PersonNote.filter("The preview didn't start. Do not claim it is live. Use ScreenAct on the Address row. Port 4173 is busy.")
            == "The preview didn't start. Port 4173 is busy.")
    #expect(PersonNote.filter("Never say it plays.") == "")
    #expect(PersonNote.filter("Shellfish are fine.") == "Shellfish are fine.")  // a tool name only as a whole word
    #expect(PersonNote.filter("Pebble's reply says the task isn't finished.") == "Pebble's reply says the task isn't finished.")
    #expect(PersonNote.filter(nil) == "")
}

@Test func aFailedRunShowsItsNoteEvenWhenItsReplyIsUntagged() {
    let world = Fixture.world(
        runs: [Fixture.runRow("r1", chat: "c1", state: "failed", elapsed: 14.6, error: "Port 4173 is in use. Do not claim the preview is live.")],
        messages: [Fixture.message("m1", "user", "Start the preview")])
    let items = world.transcriptItems(for: "c1")
    #expect(
        items.dropLast().last
            == .runEnd(id: "end-r1", runID: "r1", state: .failed, seconds: 14.6, note: "Port 4173 is in use."))
    #expect(items.last?.id == "t/c1/r1")
}

// A read's answer and the event stream can be handled in either order (the store reads on its own task).

@Test func aReadAheadOfTheEventsKeepsTheirLinesAndRepeatsNoText() {
    // `state` and the conversation already say the run finished, with its whole reply...
    var world = Fixture.world(
        runs: [Fixture.runRow("r1", chat: "c1", state: "completed", created: 5, elapsed: 9)],
        messages: [Fixture.message("m1", "user", "Fix it"), Fixture.message("m2", "assistant", "Fixed it.", run: "r1")])
    // ...then the events from before that read arrive.
    world.apply(Fixture.event("progress", ["chat_id": "c1", "run_id": "r1", "label": "Reading a.ts", "kind": "working", "tool": "Read", "activity": "reading"], at: 1))
    world.apply(Fixture.event("token", ["chat_id": "c1", "id": "m2", "text": "Fixed it."], at: 2))
    #expect(messages(world).last?.text == "Fixed it.")  // never "Fixed it.Fixed it."
    #expect(world.transcriptItems(for: "c1").contains { $0.id == "a/r1/0" })
    #expect(world.liveRuns().isEmpty)  // no status change for a settled run
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "completed", "elapsed": 9], at: 5))
    // After Pebble's own settle event, later progress is ignored, as Pebble's window does.
    world.apply(Fixture.event("progress", ["chat_id": "c1", "run_id": "r1", "label": "Run handoff needs attention", "kind": "review"], at: 6))
    #expect(!world.transcriptItems(for: "c1").contains { $0.id == "a/r1/1" })
}

@Test func aReadBehindTheEventsDoesNotRollThemBack() {
    var world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "running", created: 1)], active: "c1", activeRun: "r1")
    world.apply(Fixture.event("run", ["chat_id": "c1", "run_id": "r1", "state": "completed", "elapsed": 4], at: 6))
    // A `state` read answered before that event, handled after it.
    world.load(StateDTO(json: Fixture.stateJSON(runs: [Fixture.runRow("r1", chat: "c1", state: "running", created: 2)], active: "c1", activeRun: "r1"))!)
    #expect(world.runs["r1"]?.row.state == .completed)
    #expect(world.liveRuns().isEmpty && !world.isLive(chat: "c1"))
    // A newer read still wins.
    world.load(StateDTO(json: Fixture.stateJSON(runs: [Fixture.runRow("r1", chat: "c1", state: "paused", created: 9)]))!)
    #expect(world.runs["r1"]?.row.state == .paused)
}

@Test func pebblesOwnTimelineItemsReplaceTheProgressLines() {
    var world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1")
    world.apply(Fixture.event("progress", ["chat_id": "c1", "run_id": "r1", "label": "Reading a.ts", "kind": "working", "tool": "Read", "activity": "reading"]))
    #expect(world.transcriptItems(for: "c1").map(\.id) == ["a/r1/0"])  // the fallback, before Pebble's items
    func item(_ seq: Int, _ kind: String, _ label: String, _ status: String) -> JSONValue {
        ["chat_id": "c1", "run_id": "r1", "item": ["seq": .int(seq), "at": 1.0, "kind": .string(kind), "label": .string(label), "detail": .null, "duration": .null, "status": .string(status)]]
    }
    world.apply(Fixture.event("activity", item(64, "tool", "Reading a.ts", "running")))
    world.apply(Fixture.event("activity", item(128, "approval", "Waiting for your review", "running")))
    world.apply(Fixture.event("activity", item(64, "tool", "Reading a.ts", "done")))  // the same item, updated
    let lines = world.transcriptItems(for: "c1").compactMap { item -> (String, StatusKey)? in
        if case .activity(let id, _, _, let status) = item { (id, status) } else { nil }
    }
    #expect(lines.map(\.0) == ["r1/h64", "r1/h128"])
    #expect(lines.map(\.1) == [.reading, .review])  // a tool borrows its progress line's class; never the label's words
}
