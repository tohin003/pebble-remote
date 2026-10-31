import Foundation
import PebbleProtocol

// Lane Q (2026-10-31): the demo answers a quiz's five calls as app.py does (DemoQuizzes), so "What's new in 2.0" can be
// taken in the demo. `quiz_share` wants Face ID, as from Pebble's bridge (remote_policy.py `OPEN_ON_MAC`); the demo
// lists it in `elevated`, and Face ID always agrees in the demo.

extension DemoClient {
    /// The quiz calls; nil for any other method.
    func quizAnswer(_ method: String, _ params: JSONValue, proven: Bool) throws -> JSONValue? {
        switch method {
        case "quiz_attempt":
            return try quizzes.attempt(params, view: try quizView(params, key: "id"), now: now())
        case "quiz_start":
            return try quizzes.start(params, view: try quizView(params, key: "id"), now: now())
        case "quiz_save":
            return try quizzes.save(params, view: try quizView(params, key: nil), now: now())
        case "quiz_submit":
            return try quizzes.submit(params, view: try quizView(params, key: nil), now: now())
        case "quiz_share":
            guard proven else {
                throw refusal("Confirm with Face ID to do this.", code: BridgeErrorCode.proofRequired.rawValue)
            }
            return try quizzes.share(params, view: try quizView(params, key: nil))
        default:
            return nil
        }
    }

    /// The quiz a call names: by the view's id (`key`), or by its attempt's. A view that isn't one of the demo's quizzes
    /// is refused (Pebble's words name its grading on the Mac; the demo's say the same plainly).
    private func quizView(_ params: JSONValue, key: String?) throws -> JSONValue {
        guard let chat = params["chat_id"]?.string, chatIndex(chat) != nil else { throw refusal("Artifact not found.") }
        let id: String?
        if let key {
            id = params[key]?.string
        } else {
            let attemptID = params["attempt_id"]?.string
            id = quizzes.attempts.first { $0.id == attemptID && $0.chatID == chat }?.viewID
        }
        guard let id else {
            throw refusal(key == nil ? "Quiz attempt not found in this conversation." : "Artifact not found.")
        }
        guard let row = views.row(id, in: chat) else { throw refusal("Artifact not found.") }
        guard row["kind"]?.string == "quiz", DemoQuizzes.keys[id] != nil else {
            throw refusal("This view is not a quiz Pebble grades.")
        }
        return row
    }
}
