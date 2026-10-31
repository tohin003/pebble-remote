import Foundation
import PebbleProtocol

// Lane Q (2026-10-31): the five calls behind a quiz, with Pebble's own params (read-only Pebble checkout, app.py):
// `quiz_attempt(chat_id, id, revision)`, `quiz_start(chat_id, id, revision)`, `quiz_save` and
// `quiz_submit(chat_id, attempt_id, revision, answers)` with answers `{question_id: choice index or null}`, and
// `quiz_share(chat_id, attempt_id)`.
//
// The bridge's rules for the phone (remote_policy.py): none of the five is a read, so each needs the unlock (C1) and
// carries an idem, `quiz_attempt` too. `quiz_share` opens something on the Mac, so it always needs Face ID; the bridge
// writes `surface: "main"` on it, so a share from the phone goes to the run that made the quiz, as the main window's
// does. Failures are never shown as `notice`: the quiz says them in place, as Pebble's window does (`QuizSession`).

extension RemoteStore {
    /// The open attempt on the view's revision, else its latest attempt, else nil (Pebble's `null`).
    public func quizAttempt(for view: PebbleArtifact, quiz: NativeView.Quiz) async throws -> QuizAttempt? {
        let reply = try await act(
            "quiz_attempt", Self.quizIdentity(view), reason: ViewsWords.takeQuizReason(view.title), reports: false)
        if reply == .null { return nil }
        return try QuizAttempt(reply: reply, view: view, quiz: quiz)
    }

    /// Begins an attempt on the view's revision, or resumes its open one.
    public func startQuiz(_ view: PebbleArtifact, quiz: NativeView.Quiz) async throws -> QuizAttempt {
        let reply = try await act(
            "quiz_start", Self.quizIdentity(view), reason: ViewsWords.takeQuizReason(view.title), reports: false)
        return try QuizAttempt(reply: reply, view: view, quiz: quiz)
    }

    /// Keeps the draft on the Mac, in place of the phone's storage. Pebble's answer is the attempt, unused here, as in
    /// Pebble's window.
    public func saveQuiz(
        _ answers: [String: Int], attempt: String, view: PebbleArtifact, quiz: NativeView.Quiz
    ) async throws {
        _ = try await act(
            "quiz_save", Self.quizAnswers(answers, attempt: attempt, view: view, quiz: quiz),
            reason: ViewsWords.takeQuizReason(view.title), reports: false)
    }

    /// Hands the answers in. Pebble grades them once; a repeat gets the stored outcome.
    public func submitQuiz(
        _ answers: [String: Int], attempt: String, view: PebbleArtifact, quiz: NativeView.Quiz
    ) async throws -> QuizAttempt {
        let reply = try await act(
            "quiz_submit", Self.quizAnswers(answers, attempt: attempt, view: view, quiz: quiz),
            reason: ViewsWords.takeQuizReason(view.title), reports: false)
        return try QuizAttempt(reply: reply, view: view, quiz: quiz)
    }

    /// "Share result with Pebble": the person's own tap, with Face ID at once (the bridge lists `quiz_share` in
    /// `welcome.elevated`; `act` still asks for it on `proof_required` from a bridge that doesn't).
    public func shareQuiz(attempt: String, view: PebbleArtifact) async throws -> QuizShareReply {
        let params: JSONValue = ["chat_id": .string(view.chatID), "attempt_id": .string(attempt)]
        let reply = try await act("quiz_share", params, reason: ViewsWords.shareQuizReason, reports: false)
        return try QuizShareReply(reply: reply)
    }

    static func quizIdentity(_ view: PebbleArtifact) -> JSONValue {
        ["chat_id": .string(view.chatID), "id": .string(view.id), "revision": .int(view.revision)]
    }

    /// Every question, with its choice or null, as Pebble's window sends them (QuizRenderer.vue `snapshot`).
    static func quizAnswers(
        _ answers: [String: Int], attempt: String, view: PebbleArtifact, quiz: NativeView.Quiz
    ) -> JSONValue {
        var given: [String: JSONValue] = [:]
        for question in quiz.questions {
            given[question.id] = answers[question.id].map(JSONValue.int) ?? .null
        }
        return [
            "chat_id": .string(view.chatID), "attempt_id": .string(attempt), "revision": .int(view.revision),
            "answers": .object(given),
        ]
    }
}
