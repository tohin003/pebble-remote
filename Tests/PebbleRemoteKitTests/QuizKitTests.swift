import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

/// Lane Q: taking a quiz on the phone, as Pebble's window does (QuizRenderer.vue and its tests). Replies are read as
/// `parseAttempt` and `parseResult` read them; the calls carry Pebble's own params; one save runs at a time and the
/// latest answers go last; a refused submission keeps the answers and isn't sent again; the countdown starts from
/// `seconds_left`; and the demo's quiz can be taken end to end.
@MainActor
struct QuizKitTests {
    nonisolated static let t0 = Fixture.t0.timeIntervalSince1970

    nonisolated static func row(revision: Int = 1, status: String = "ready") -> JSONValue {
        [
            "id": "quiz-1", "chat_id": "chat-a", "title": "Science", "kind": "quiz", "revision": .int(revision),
            "status": .string(status), "owner_run_id": "run-1", "created": 1,
            "data": [
                "duration_minutes": 10,
                "questions": [
                    ["id": "q1", "question": "Which gas do plants absorb?", "choices": ["Oxygen", "Carbon dioxide"]],
                    ["id": "q2", "question": "Water boils at sea level at?", "choices": ["90 °C", "100 °C", "110 °C"]],
                ],
            ],
        ]
    }

    static func view(revision: Int = 1, status: String = "ready") throws -> PebbleArtifact {
        try #require(PebbleArtifact(json: row(revision: revision, status: status)))
    }

    static func parse(_ reply: JSONValue, revision: Int = 1) throws -> QuizAttempt {
        let view = try view(revision: revision)
        return try QuizAttempt(reply: reply, view: view, quiz: try #require(view.quiz))
    }

    static func problem(_ reply: JSONValue, revision: Int = 1) throws -> QuizReplyProblem? {
        do {
            _ = try parse(reply, revision: revision)
            return nil
        } catch let problem as QuizReplyProblem {
            return problem
        }
    }

    // MARK: - Reading Pebble's replies

    @Test func anAttemptReadsAsPebbleSendsIt() throws {
        // quiz_grading.py `_public_attempt` for a fresh start.
        let attempt = try Self.parse([
            "attempt_id": "3f2a9c0d1e4b4a7f9c2d8e6f1a0b3c5d", "artifact_id": "quiz-1", "revision": 1, "origin": "human",
            "status": "open", "started": .double(Self.t0), "deadline": .double(Self.t0 + 600), "answers": ["q2": 1],
            "result": .null, "shared": false, "seconds_left": 600.0,
        ])
        #expect(attempt.id == "3f2a9c0d1e4b4a7f9c2d8e6f1a0b3c5d" && attempt.status == .open && attempt.revision == 1)
        #expect(attempt.deadline == Self.t0 + 600 && attempt.secondsLeft == 600 && attempt.answers == ["q2": 1])
        #expect(attempt.result == nil && !attempt.shared)
        // An absent or null status is an open attempt (`row.status ?? "open"`).
        #expect(try Self.parse(["attempt_id": "a", "deadline": 5, "status": .null]).status == .open)
    }

    /// QuizRenderer.test.mjs case 5: forged or mismatched replies are refused, in Pebble's window's words.
    @Test func forgedRepliesAreRefusedAsPebblesWindowRefusesThem() throws {
        let deadline = JSONValue.double(Self.t0 + 60)
        let forged: [(JSONValue, QuizReplyProblem)] = [
            (["attempt_id": "x", "deadline": deadline, "status": "open", "artifact_id": "other-view"], .otherView),
            (["attempt_id": "x", "deadline": deadline, "status": "open", "chat_id": "chat-b"], .otherConversation),
            (["attempt_id": "x", "deadline": deadline, "status": "open", "answers": ["q1": 7]], .invalid),
            (["attempt_id": "x", "deadline": deadline, "status": "approved"], .invalid),
            (
                [
                    "attempt_id": "x", "deadline": deadline, "status": "submitted",
                    "result": ["score": 1, "total": 2, "per_question": [["id": "__proto__", "correct": true]]],
                ], .invalid
            ),
            (
                [
                    "attempt_id": "x", "deadline": deadline, "status": "submitted",
                    "result": ["score": 3, "total": 2, "per_question": []],
                ], .invalid
            ),
            (["attempt_id": "<img>", "deadline": 1], .invalid),
            // And a few more of `parseAttempt`'s checks.
            (["attempt_id": "x", "deadline": 0], .invalid),
            (["attempt_id": "x", "deadline": deadline, "answers": .null], .invalid),
            (["attempt_id": "x", "deadline": deadline, "answers": ["q1": 1.5]], .invalid),
            (["attempt_id": "x", "deadline": deadline, "revision": .null], .invalid),
            (["attempt_id": "x", "deadline": deadline, "revision": "1"], .invalid),
            (["attempt_id": .string(String(repeating: "a", count: 129)), "deadline": deadline], .invalid),
            ("not an attempt", .invalid),
        ]
        for (reply, expected) in forged {
            #expect(try Self.problem(reply) == expected, "\(reply)")
        }
        // A chat_id or artifact_id that matches is fine; an unknown question's answer is left out.
        let matching = try Self.parse([
            "attempt_id": "x", "deadline": deadline, "chat_id": "chat-a", "artifact_id": "quiz-1",
            "answers": ["q1": 1, "q9": 4, "q2": .null],
        ])
        #expect(matching.answers == ["q1": 1])
    }

    @Test func anOpenAttemptBoundToAnotherRevisionIsSuperseded() throws {
        let moved = try Self.parse(["attempt_id": "old", "deadline": .double(Self.t0 + 60), "status": "open", "revision": 1], revision: 2)
        #expect(moved.status == .superseded && moved.revision == 1)
        // Submitted stays submitted: only an open attempt is closed for this view.
        let graded = try Self.parse(["attempt_id": "old", "deadline": 5, "status": "submitted", "revision": 1], revision: 2)
        #expect(graded.status == .submitted)
    }

    @Test func aResultMustGradeThisQuiz() throws {
        func result(_ value: JSONValue) throws -> QuizReplyProblem? {
            try Self.problem(["attempt_id": "x", "deadline": 5, "status": "submitted", "result": value])
        }
        let row: JSONValue = ["id": "q1", "correct": true, "chosen": 1, "answer": 1, "explanation": "Yes."]
        #expect(try result(["score": 1, "total": 2, "per_question": [row]]) == nil)
        #expect(try result(["score": 1, "total": 3, "per_question": [row]]) == .invalid)  // total is the question count
        #expect(try result(["score": 1.5, "total": 2, "per_question": [row]]) == .invalid)
        #expect(try result(["score": -1, "total": 2, "per_question": [row]]) == .invalid)
        #expect(try result(["score": 1, "total": 2, "per_question": [row, row]]) == .invalid)  // the same question twice
        #expect(try result(["score": 1, "total": 2, "per_question": [row, row, row]]) == .invalid)  // more rows than questions
        #expect(try result(["score": 1, "total": 2, "per_question": [["id": "q1", "correct": "yes"]]]) == .invalid)
        #expect(try result(["score": 1, "total": 2, "per_question": [["id": "q1", "correct": true, "answer": .null]]]) == .invalid)
        #expect(try result(["score": 1, "total": 2, "per_question": [["id": "q1", "correct": true, "chosen": 2]]]) == .invalid)
        #expect(try result(["score": 1, "total": 2, "per_question": [["id": "q1", "correct": true, "explanation": "  "]]]) == .invalid)
        // An explanation is at most 1,500 characters (JavaScript's length).
        let longest = String(repeating: "e", count: 1500)
        #expect(try result(["score": 1, "total": 2, "per_question": [["id": "q1", "correct": true, "explanation": .string(longest)]]]) == nil)
        #expect(try result(["score": 1, "total": 2, "per_question": [["id": "q1", "correct": true, "explanation": .string(longest + "e")]]]) == .invalid)
        // A chosen null is "unanswered"; an absent one leaves the review to the answers on screen.
        let graded = try Self.parse([
            "attempt_id": "x", "deadline": 5, "status": "submitted",
            "result": ["score": 0, "total": 2, "per_question": [["id": "q1", "correct": false, "chosen": .null, "answer": 1], ["id": "q2", "correct": false]]],
        ])
        #expect(graded.result?.grade(of: "q1")?.chosen == .unanswered && graded.result?.grade(of: "q2")?.chosen == nil)
    }

    @Test func aShareIsConfirmedOrComposedAndNothingElse() throws {
        #expect(try QuizShareReply(reply: ["status": "shared", "shared": true, "input_id": "i1", "run_id": "run-1"]) == .shared)
        let text = "My result for the quiz \"Science\" (revision 1): 2 of 2 correct.\nQ1: correct (chose B)\nQ2: correct (chose B)"
        let composed = try QuizShareReply(reply: [
            "status": "compose", "shared": false, "reason": "The run that made this quiz has finished.", "text": .string(text),
        ])
        #expect(composed == .compose(text))
        #expect(throws: QuizReplyProblem.notConfirmed) { try QuizShareReply(reply: ["status": "shared", "shared": false]) }
        #expect(throws: QuizReplyProblem.notConfirmed) { try QuizShareReply(reply: ["status": "compose", "text": "  "]) }
        #expect(throws: QuizReplyProblem.invalid) { try QuizShareReply(reply: .null) }
    }

    // MARK: - The countdown

    @Test func theCountdownStartsFromSecondsLeftAsReceived() throws {
        // The Mac's clock is an hour ahead of the phone's: its deadline says 3,900 s, but 300 s were left.
        let attempt = try Self.parse([
            "attempt_id": "x", "status": "open", "deadline": .double(Self.t0 + 3600 + 300), "seconds_left": 300,
        ])
        let clock = attempt.clock(receivedAt: Fixture.t0, limit: 600)
        #expect(clock.remaining(at: Fixture.t0) == 300)
        #expect(clock.remaining(at: Fixture.at(10)) == 290)
        #expect(clock.remaining(at: Fixture.at(10.2)) == 290)  // rounded up, as Math.ceil does
        #expect(clock.remaining(at: Fixture.at(400)) == 0)
        // Without seconds_left, the deadline.
        let older = try Self.parse(["attempt_id": "x", "status": "open", "deadline": .double(Self.t0 + 120)])
        #expect(older.clock(receivedAt: Fixture.t0, limit: 600).remaining(at: Fixture.at(20)) == 100)
        // Never more than the quiz's length, whatever a reply says; a negative seconds_left is ignored.
        let wild = try Self.parse(["attempt_id": "x", "status": "open", "deadline": 1e300, "seconds_left": -4])
        #expect(wild.secondsLeft == nil && wild.clock(receivedAt: Fixture.t0, limit: 600).remaining(at: Fixture.t0) == 600)
    }

    // MARK: - The review

    @Test func theReviewSaysWhatPebblesWindowSays() throws {
        let view = try Self.view()
        let quiz = try #require(view.quiz)
        let result = QuizAttempt.Result(
            score: 1, total: 2,
            grades: [
                .init(id: "q1", correct: true, chosen: .choice(1), answer: 1, explanation: "Plants take in carbon dioxide.")
            ])
        let rows = QuizReviewRow.rows(quiz.questions, result: result, answers: ["q1": 1, "q2": 2])
        #expect(rows.map(\.state) == [.correct, .notGraded])
        #expect(rows[0].chosen == "Carbon dioxide" && rows[0].correctAnswer == nil)
        #expect(rows[1].chosen == "110 °C" && rows[1].number == 2)  // not graded: the answer on screen
        let wrong = QuizAttempt.Result(
            score: 0, total: 2,
            grades: [.init(id: "q1", correct: false, chosen: .choice(0), answer: 1), .init(id: "q2", correct: false, chosen: .unanswered, answer: 1)])
        let marked = QuizReviewRow.rows(quiz.questions, result: wrong, answers: [:])
        #expect(marked.map(\.state) == [.incorrect, .unanswered])
        #expect(marked[0].chosen == "Oxygen" && marked[0].correctAnswer == "Carbon dioxide")
        #expect(marked[1].chosen == nil && marked[1].correctAnswer == "100 °C")
    }

    // MARK: - The calls

    @Test func theCallsSendPebblesParamsAndOnlyShareAsksForFaceID() async throws {
        let fake = FakeClient { method, _ in
            switch method {
            case "quiz_share": return ["status": "shared", "shared": true]
            case "quiz_attempt": return .null
            default: return ["attempt_id": "att-1", "deadline": .double(Self.t0 + 600), "status": "open", "revision": 1]
            }
        }
        let store = RemoteStore(client: fake)
        let view = try Self.view()
        let quiz = try #require(view.quiz)
        #expect(try await store.quizAttempt(for: view, quiz: quiz) == nil)
        _ = try await store.startQuiz(view, quiz: quiz)
        try await store.saveQuiz(["q1": 1], attempt: "att-1", view: view, quiz: quiz)
        _ = try await store.submitQuiz(["q1": 1, "q2": 0], attempt: "att-1", view: view, quiz: quiz)
        #expect(try await store.shareQuiz(attempt: "att-1", view: view) == .shared)
        let identity: JSONValue = ["chat_id": "chat-a", "id": "quiz-1", "revision": 1]
        #expect(fake.calls("quiz_attempt").first?.params == identity)
        #expect(fake.calls("quiz_start").first?.params == identity)
        #expect(
            fake.calls("quiz_save").first?.params == [
                "chat_id": "chat-a", "attempt_id": "att-1", "revision": 1, "answers": ["q1": 1, "q2": .null],
            ])
        #expect(
            fake.calls("quiz_submit").first?.params == [
                "chat_id": "chat-a", "attempt_id": "att-1", "revision": 1, "answers": ["q1": 1, "q2": 0],
            ])
        let share = try #require(fake.calls("quiz_share").first)
        #expect(share.params == ["chat_id": "chat-a", "attempt_id": "att-1"])
        // Without the bridge's welcome, a plain call; the bridge's `proof_required` would elevate it (`act`).
        #expect(fake.calls.filter { $0.method != "quiz_share" }.allSatisfy { !$0.elevated })
    }

    @Test func shareGoesWithFaceIDWhenTheBridgeListsIt() async throws {
        let bridge = QuizBridge(host: QuizHost())
        let store = await Self.connect(bridge)
        let session = QuizSession(view: try Self.view(), store: store)
        await session.load()
        await session.start()
        await session.submit()
        _ = await session.share(composing: true)
        let share = try #require(bridge.calls("quiz_share").first)
        #expect(share.elevated && share.reason == ViewsWords.shareQuizReason)
        #expect(bridge.quizCalls.filter { $0.method != "quiz_share" }.allSatisfy { !$0.elevated })
    }

    // MARK: - Taking a quiz (QuizRenderer.test.mjs case 1)

    @Test func readStartAnswerSubmitAndShare() async throws {
        let host = QuizHost()
        let bridge = QuizBridge(host: host)
        let store = await Self.connect(bridge)
        let session = QuizSession(view: try Self.view(), store: store)
        await session.load()
        #expect(bridge.quizCalls.map(\.method) == ["quiz_attempt"])
        #expect(session.attempt == nil && session.canStart && session.result == nil)

        await session.start()
        #expect(session.isOpen && session.index == 0 && session.remaining(at: Fixture.t0) == 600)
        session.choose(1, for: "q1")
        #expect(session.answers == ["q1": 1] && session.answeredCount == 1)
        _ = await eventually { session.saveState == .saved }
        #expect(bridge.calls("quiz_save").last?.params["answers"] == ["q1": 1, "q2": .null])
        session.go(to: 1)
        session.choose(1, for: "q2")
        _ = await eventually { session.saveState == .saved && bridge.calls("quiz_save").count == 2 }

        await session.submit()
        #expect(bridge.calls("quiz_submit").last?.params["answers"] == ["q1": 1, "q2": 1])
        let result = try #require(session.result)
        #expect(result.score == 2 && result.total == 2 && session.review.map(\.state) == [.correct, .correct])
        #expect(session.review[0].explanation == "Plants take in carbon dioxide.")
        #expect(bridge.calls("quiz_share").isEmpty, "no share without the person's tap")
        #expect(session.canShare)

        #expect(await session.share(composing: true) == nil)
        #expect(session.attempt?.shared == true && !session.canShare)
        _ = await session.share(composing: true)
        #expect(bridge.calls("quiz_share").count == 1, "a shared result is not shared again")
        #expect(store.notice == nil)
        // Retake: a new attempt.
        #expect(session.canStart)
        await session.start()
        #expect(session.isOpen && session.answers.isEmpty && session.attempt?.id == "att-2")
    }

    /// One save at a time; choices made meanwhile go together, after it, with the latest answers.
    @Test func savesRunOneAtATimeAndTheLatestAnswersGoLast() async throws {
        let bridge = QuizBridge(host: QuizHost())
        let store = await Self.connect(bridge)
        let session = QuizSession(view: try Self.view(), store: store)
        await session.load()
        await session.start()
        bridge.holdSaves()
        session.choose(0, for: "q1")
        _ = await eventually { bridge.calls("quiz_save").count == 1 }
        session.choose(1, for: "q1")
        session.choose(2, for: "q2")
        for _ in 0..<10 { await Task.yield() }
        #expect(bridge.calls("quiz_save").count == 1)
        #expect(session.saveState == .saving)
        bridge.release()
        _ = await eventually { session.saveState == .saved }
        #expect(bridge.calls("quiz_save").map { $0.params["answers"] } == [["q1": 0, "q2": .null], ["q1": 1, "q2": 2]])
        #expect(bridge.host.answers("att-1") == ["q1": 1, "q2": 2])
    }

    /// QuizRenderer.test.mjs case 3: a stale submission is refused; the error shows, the answers stay, nothing is
    /// sent again; and the refusal isn't also the app-wide alert.
    @Test func aRefusedSubmissionKeepsTheAnswersAndIsNotSentAgain() async throws {
        let host = QuizHost(revision: 2)
        let bridge = QuizBridge(host: host)
        let store = await Self.connect(bridge)
        let session = QuizSession(view: try Self.view(), store: store)
        await session.load()
        await session.start()
        session.choose(0, for: "q1")
        _ = await eventually { session.saveState == .saved }
        await session.submit()
        #expect(session.actionError == .said("This view changed to revision 2."))
        #expect(session.isOpen && session.answers == ["q1": 0] && !session.isBusy)
        for _ in 0..<10 { await Task.yield() }
        #expect(bridge.calls("quiz_submit").count == 1)
        #expect(store.notice == nil)
    }

    /// QuizRenderer.test.mjs case 6: once time is up, a choice changes nothing and Submit still goes.
    @Test func timeUpClosesTheChoicesButNotSubmit() async throws {
        let bridge = QuizBridge(host: QuizHost(seconds: -5))
        let store = await Self.connect(bridge)
        let session = QuizSession(view: try Self.view(), store: store)
        await session.load()
        await session.start()
        #expect(session.isOpen && session.isTimeUp(at: Fixture.t0) && !session.isAnswering(at: Fixture.t0))
        session.choose(1, for: "q1")
        for _ in 0..<10 { await Task.yield() }
        #expect(session.answers.isEmpty && bridge.calls("quiz_save").isEmpty)
        await session.submit()
        #expect(bridge.calls("quiz_submit").count == 1)
    }

    /// QuizRenderer.test.mjs case 4: an update mid-attempt closes the attempt without a grade, and says so once.
    @Test func anUpdatedQuizClosesTheOpenAttemptAndSaysSo() async throws {
        let host = QuizHost()
        let bridge = QuizBridge(host: host)
        let store = await Self.connect(bridge)
        let session = QuizSession(view: try Self.view(), store: store)
        await session.load()
        await session.start()
        #expect(session.isOpen)
        host.setRevision(2)
        session.show(try Self.view(revision: 2))
        #expect(session.attempt == nil && session.replaced == 1)  // at once, before the read comes back
        _ = await eventually { !session.isLoading }
        #expect(bridge.calls("quiz_attempt").last?.params == ["chat_id": "chat-a", "id": "quiz-1", "revision": 2])
        #expect(session.attempt == nil && session.replaced == 1 && session.canStart)
        // The same view again (a reread that changed nothing that matters) reads nothing.
        let reads = bridge.calls("quiz_attempt").count
        session.show(try Self.view(revision: 2))
        #expect(bridge.calls("quiz_attempt").count == reads)
        // A reply for the revision the screen left behind is dropped.
        host.setRevision(3)
        bridge.holdStarts()
        let starts = bridge.calls("quiz_start").count
        let starting = Task { await session.start() }
        _ = await eventually { bridge.calls("quiz_start").count == starts + 1 }
        session.show(try Self.view(revision: 3))
        bridge.release()
        await starting.value
        _ = await eventually { !session.isLoading }
        #expect(session.attempt == nil && !session.isBusy)
    }

    // MARK: - The unlock (C1)

    @Test func openingTheQuizWhileLockedReadsNothingUntilTheUnlock() async throws {
        let bridge = QuizBridge(host: QuizHost())
        let store = await Self.connect(bridge, unlockSeconds: 900)
        let session = QuizSession(view: try Self.view(), store: store)
        await session.load()
        #expect(bridge.quizCalls.isEmpty && session.attempt == nil && session.canStart && !session.isLoading)
        bridge.push(.unlocked(until: Fixture.at(900)))
        _ = await eventually { store.isUnlocked }
        await session.resume()
        #expect(bridge.quizCalls.map(\.method) == ["quiz_attempt"])
    }

    /// Opening a view never asks for Face ID: a bridge that would want it for the read gets no read (Start, which
    /// resumes an open attempt, still works).
    @Test func aReadTheBridgeWouldWantFaceIDForIsNotMadeOnOpening() async throws {
        let bridge = QuizBridge(host: QuizHost())
        let store = await Self.connect(bridge, elevated: ["quiz_share", "quiz_attempt"])
        let session = QuizSession(view: try Self.view(), store: store)
        await session.load()
        #expect(bridge.quizCalls.isEmpty && session.canStart)
        await session.start()
        #expect(session.isOpen && bridge.quizCalls.map(\.method) == ["quiz_start"])
    }

    @Test func aCallThatNeedsTheUnlockAsksForItInsteadOfSayingSo() async throws {
        let host = QuizHost()
        host.requireUnlock(true)
        let bridge = QuizBridge(host: host)
        let store = await Self.connect(bridge)
        let session = QuizSession(view: try Self.view(), store: store)
        // The quiet read: the intro, no sheet.
        await session.load()
        #expect(session.unlockRequests == 0 && session.actionError == nil && !session.isLoading)
        // Start: the unlock sheet, and nothing said under the quiz or in the app-wide alert.
        await session.start()
        #expect(session.unlockRequests == 1 && session.actionError == nil && store.notice == nil && !session.isBusy)
        host.requireUnlock(false)
        await session.resume()
        await session.start()
        #expect(session.isOpen)
        // A draft the unlock refused is saved again once unlocked.
        host.requireUnlock(true)
        session.choose(1, for: "q1")
        _ = await eventually { session.saveState == .failed }
        #expect(session.unlockRequests == 2 && session.saveError == nil)
        host.requireUnlock(false)
        await session.resume()
        #expect(session.saveState == .saved && host.answers("att-1") == ["q1": 1, "q2": .null])
    }

    // MARK: - Share's compose reply

    @Test func aComposeReplyGivesPebblesWordsForTheMessageBox() async throws {
        let host = QuizHost()
        host.composeShares()
        let bridge = QuizBridge(host: host)
        let store = await Self.connect(bridge)
        let session = QuizSession(view: try Self.view(), store: store)
        await session.load()
        await session.start()
        session.choose(1, for: "q1")
        _ = await eventually { session.saveState == .saved }
        await session.submit()
        let words = await session.share(composing: true)
        #expect(words == QuizHost.composed && session.attempt?.shared == false && session.actionError == nil)
        // A screen that can't put words in the message box says what Pebble's window says.
        #expect(await session.share(composing: false) == nil)
        #expect(session.actionError == .reply(.notConfirmed))
    }

    // MARK: - What can be done

    /// QuizRenderer.test.mjs case 7, and an inactive quiz: a stopped quiz's attempt is still read (its result shows) but
    /// it can't be started; a historical revision and a bridge without the quiz calls read nothing.
    @Test func aStoppedQuizOrAnOlderBridgeCantBeTaken() async throws {
        let bridge = QuizBridge(host: QuizHost())
        let store = await Self.connect(bridge)
        let stopped = QuizSession(view: try Self.view(status: "stopped"), store: store)
        await stopped.load()
        #expect(stopped.isInactive && !stopped.canStart && bridge.quizCalls.map(\.method) == ["quiz_attempt"])
        await stopped.start()
        #expect(bridge.quizCalls.map(\.method) == ["quiz_attempt"])
        let historical = QuizSession(view: try Self.view(), store: store, historical: true)
        await historical.load()
        await historical.start()
        #expect(!historical.canStart && bridge.quizCalls.count == 1)

        let older = QuizBridge(host: QuizHost())
        let olderStore = await Self.connect(older, methods: ["state", "get_chat"])
        let unoffered = QuizSession(view: try Self.view(), store: olderStore)
        await unoffered.load()
        #expect(!unoffered.offersTaking && !unoffered.canStart && older.quizCalls.isEmpty)
    }

    @Test func questionIDsThatRepeatMakeTheQuizInvalid() async throws {
        let bridge = QuizBridge(host: QuizHost())
        let store = await Self.connect(bridge)
        let twice = try #require(
            PebbleArtifact(json: [
                "id": "quiz-1", "chat_id": "chat-a", "kind": "quiz", "revision": 1, "status": "ready",
                "data": [
                    "duration_minutes": 5,
                    "questions": [["id": "q1", "question": "A?", "choices": ["x", "y"]], ["id": "q1", "question": "B?", "choices": ["x", "y"]]],
                ],
            ]))
        let session = QuizSession(view: twice, store: store)
        await session.load()
        #expect(!session.isValid && !session.canStart && bridge.quizCalls.isEmpty)
    }

    // MARK: - The demo

    @Test func theDemosQuizCanBeTakenEndToEnd() async throws {
        let store = await DetailsKitTests.demo()
        let view = try await store.readView("v-readme-quiz", in: DemoData.readmeChat)
        let quiz = try #require(view.quiz)
        // The key stays with the demo's Pebble: the view carries only the public questions.
        #expect(quiz.questions.map(\.id) == ["q1", "q2"])
        let stored = DemoViews(now: Fixture.t0).row("v-readme-quiz", in: DemoData.readmeChat)
        #expect(stored?["data"]?["questions"]?.array?.allSatisfy { $0["answer"] == nil && $0["explanation"] == nil } == true)

        let session = QuizSession(view: view, store: store)
        await session.load()  // the demo starts locked: the intro, nothing read
        #expect(session.attempt == nil && session.canStart)
        await session.start()
        #expect(session.isOpen && session.remaining(at: Fixture.t0) == 300 && session.actionError == nil)
        session.choose(0, for: "q1")
        _ = await eventually { session.saveState == .saved }
        session.go(to: 1)
        session.choose(2, for: "q2")
        _ = await eventually { session.saveState == .saved && session.answers.count == 2 }
        await session.submit()
        let result = try #require(session.result)
        #expect(result.score == 1 && result.total == 2)
        #expect(session.review.map(\.state) == [.correct, .incorrect])
        #expect(session.review[1].chosen == "Environment variables" && session.review[1].correctAnswer == "A sidebar in the app")
        #expect(session.review.allSatisfy { $0.explanation?.isEmpty == false })
        #expect(await session.share(composing: true) == nil)
        #expect(session.attempt?.shared == true && session.actionError == nil)

        // Opened again (now unlocked): Pebble's record of the attempt, graded and shared.
        _ = await eventually { store.isUnlocked }
        let again = QuizSession(view: view, store: store)
        await again.load()
        #expect(again.result?.score == 1 && again.attempt?.shared == true)
        #expect(store.notice == nil)
    }

    // MARK: - Helpers

    /// A store connected to `bridge`, whose welcome lists `methods` (every quiz call, by default) and `elevated` (only
    /// `quiz_share` by default, as Pebble's bridge lists it).
    static func connect(
        _ bridge: QuizBridge, unlockSeconds: Int? = nil,
        methods: Set<String> = ["state", "get_chat", "quiz_attempt", "quiz_start", "quiz_save", "quiz_submit", "quiz_share"],
        elevated: Set<String> = ["quiz_share"]
    ) async -> RemoteStore {
        let store = RemoteStore(client: bridge)
        store.clock = { Fixture.t0 }
        bridge.push(.status(ConnectionStatus(phase: .connected, route: .lan, roundTrip: 6)))
        bridge.push(
            .welcome(
                BridgeInfo(
                    bridgeVersion: "1.9.29", macName: "Studio Mac", pebbleRunning: true, pebbleVersion: "1.9.29",
                    methods: methods, elevated: elevated, resumed: false, unlockSeconds: unlockSeconds)))
        _ = await eventually { store.bridge != nil && store.pebble != nil }
        return store
    }
}

/// Pebble's side of the quiz for the tests (QuizRenderer.test.mjs `fakeHost`): it keeps the key, binds attempts to
/// their conversation, view and revision, keeps drafts and grades on submit.
final class QuizHost: Sendable {
    struct State {
        var attempts: [String: [String: JSONValue]] = [:]
        var order: [String] = []
        var sequence = 0
        var revision: Int
        var seconds: Double
        var composes = false
        var locked = false
    }

    static let key: [String: (answer: Int, explanation: String)] = [
        "q1": (1, "Plants take in carbon dioxide."), "q2": (1, "At one atmosphere."),
    ]
    static let composed = "My result for the quiz \"Science\" (revision 1): 2 of 2 correct.\nQ1: correct (chose B)"

    private let state: Mutex<State>

    init(revision: Int = 1, seconds: Double = 600) {
        state = Mutex(State(revision: revision, seconds: seconds))
    }

    func setRevision(_ revision: Int) { state.withLock { $0.revision = revision } }
    func composeShares() { state.withLock { $0.composes = true } }
    /// Every quiz call is refused `unlock_required`, as the bridge refuses one before the unlock.
    func requireUnlock(_ locked: Bool) { state.withLock { $0.locked = locked } }
    func answers(_ attempt: String) -> JSONValue? { state.withLock { $0.attempts[attempt]?["answers"] } }

    func answer(_ method: String, _ params: JSONValue) throws -> JSONValue {
        switch method {
        case "state": return Fixture.stateJSON()
        case "get_chat", "remote.chat_tail": return Fixture.chatDetail()
        default: break
        }
        return try state.withLock { host in
            if host.locked {
                throw RemoteCallError.refused(PersonFacingError(message: "Unlock with Face ID first.", code: "unlock_required"))
            }
            func find() throws -> String {
                guard let id = params["attempt_id"]?.string, host.attempts[id]?["chat_id"] == params["chat_id"] else {
                    throw RemoteCallError.refused(PersonFacingError(message: "Unknown quiz attempt."))
                }
                return id
            }
            func copy(_ id: String) -> JSONValue {
                var attempt = host.attempts[id] ?? [:]
                attempt["chat_id"] = nil
                return .object(attempt)
            }
            switch method {
            case "quiz_attempt":
                let found = host.order.last {
                    host.attempts[$0]?["chat_id"] == params["chat_id"] && host.attempts[$0]?["artifact_id"] == params["id"]
                        && host.attempts[$0]?["revision"] == params["revision"]
                }
                return found.map(copy) ?? .null
            case "quiz_start":
                host.sequence += 1
                let id = "att-\(host.sequence)"
                host.attempts[id] = [
                    "attempt_id": .string(id), "chat_id": params["chat_id"] ?? .null, "artifact_id": params["id"] ?? .null,
                    "revision": params["revision"] ?? .null, "status": "open",
                    "deadline": .double(Fixture.t0.timeIntervalSince1970 + host.seconds),
                    "seconds_left": .double(max(0, host.seconds)), "answers": [:],
                ]
                host.order.append(id)
                return copy(id)
            case "quiz_save":
                let id = try find()
                guard host.attempts[id]?["status"] == "open" else {
                    throw RemoteCallError.refused(PersonFacingError(message: "This attempt is closed."))
                }
                host.attempts[id]?["answers"] = params["answers"]
                return copy(id)
            case "quiz_submit":
                let id = try find()
                guard params["revision"]?.int == host.revision else {
                    throw RemoteCallError.refused(PersonFacingError(message: "This view changed to revision \(host.revision)."))
                }
                var rows: [JSONValue] = []
                var score = 0
                for (question, item) in Self.key.sorted(by: { $0.key < $1.key }) {
                    let chosen = params["answers"]?[question] ?? .null
                    let correct = chosen == .int(item.answer)
                    if correct { score += 1 }
                    rows.append([
                        "id": .string(question), "correct": .bool(correct), "chosen": chosen, "answer": .int(item.answer),
                        "explanation": .string(item.explanation),
                    ])
                }
                host.attempts[id]?["status"] = "submitted"
                host.attempts[id]?["answers"] = params["answers"]
                host.attempts[id]?["seconds_left"] = nil
                host.attempts[id]?["result"] = ["score": .int(score), "total": 2, "per_question": .array(rows)]
                return copy(id)
            case "quiz_share":
                let id = try find()
                if host.composes {
                    return [
                        "status": "compose", "shared": false, "reason": "The run that made this quiz has finished.",
                        "text": .string(Self.composed),
                    ]
                }
                host.attempts[id]?["shared"] = true
                return ["status": "shared", "shared": true, "input_id": "input-1", "run_id": "run-1", "origin": "human"]
            default:
                throw RemoteCallError.refused(PersonFacingError(message: "Unexpected call: \(method)"))
            }
        }
    }
}

/// A bridge for the quiz's tests: `host` answers each call, and while held, `quiz_save` (or `quiz_start`) waits until
/// the test lets it go, so a test can act while a call is out.
final class QuizBridge: RemoteClient {
    struct Call: Sendable, Hashable {
        var method: String
        var params: JSONValue
        var elevated: Bool
        var reason: String?
    }

    private struct Gate {
        var held: Set<String> = []
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    let updates: AsyncStream<ClientUpdate>
    let host: QuizHost
    private let continuation: AsyncStream<ClientUpdate>.Continuation
    private let recorded = Mutex<[Call]>([])
    private let gate = Mutex(Gate())

    init(host: QuizHost) {
        self.host = host
        (updates, continuation) = AsyncStream.makeStream(of: ClientUpdate.self)
    }

    var calls: [Call] { recorded.withLock { $0 } }
    func calls(_ method: String) -> [Call] { calls.filter { $0.method == method } }
    /// The quiz's calls, without the store's own reads (`state` on connecting).
    var quizCalls: [Call] { calls.filter { $0.method.hasPrefix("quiz_") } }
    func push(_ update: ClientUpdate) { continuation.yield(update) }

    func holdSaves() { gate.withLock { _ = $0.held.insert("quiz_save") } }
    func holdStarts() { gate.withLock { _ = $0.held.insert("quiz_start") } }

    /// Lets every held call go, and holds nothing more.
    func release() {
        let waiting = gate.withLock { gate in
            gate.held = []
            defer { gate.waiting = [] }
            return gate.waiting
        }
        for waiter in waiting { waiter.resume() }
    }

    func connect(to mac: PairedMac) async {}
    func disconnect() async {}

    func call(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        try await answer(Call(method: method, params: params, elevated: false, reason: nil))
    }

    func callElevated(_ method: String, _ params: JSONValue, reason: String) async throws -> JSONValue {
        try await answer(Call(method: method, params: params, elevated: true, reason: reason))
    }

    private func answer(_ call: Call) async throws -> JSONValue {
        recorded.withLock { $0.append(call) }
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let goesNow = gate.withLock { gate in
                guard gate.held.contains(call.method) else { return true }
                gate.waiting.append(waiter)
                return false
            }
            if goesNow { waiter.resume() }
        }
        return try host.answer(call.method, call.params)
    }

    func pair(_ link: PairingLink, deviceName: String) async throws -> PairedMac {
        PairedMac(
            bridgeID: link.bridgeID, name: link.macName, deviceID: "d1", pin: link.pin, endpoints: link.endpoints,
            pairedAt: Fixture.t0)
    }
}
