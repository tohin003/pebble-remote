import Foundation
import PebbleProtocol

// Lane Q (2026-10-31): the demo's Pebble takes quizzes as Pebble does (read-only Pebble checkout:
// backend/pebble/quiz_grading.py `QuizAttempts`): it starts or resumes the one open attempt on a revision, keeps
// drafts, grades once, supersedes an attempt whose quiz changed or stopped, and expires one past its time. Refusals are
// Pebble's own words. The answer key lives here, in the demo's Pebble, never in the view the phone reads (DemoViews
// keeps only the public questions, as Pebble stores them).

struct DemoQuizzes: Sendable {
    /// One question's right choice and why.
    struct Key: Sendable {
        var answer: Int
        var explanation: String
    }

    struct Attempt: Sendable {
        var id: String
        var chatID: String
        var viewID: String
        var revision: Int
        /// open, submitted, expired or superseded.
        var status: String
        var started: Date
        var limit: Double
        var draft: [String: Int] = [:]
        var answers: [String: Int]?
        var result: JSONValue?
        var shared = false
    }

    /// The keys of the demo's quizzes, by view and question ("What's new in 2.0" in "Update the README for 2.0").
    static let keys: [String: [String: Key]] = [
        "v-readme-quiz": [
            "q1": Key(answer: 0, explanation: "The docs site runs on Vite, so npm run dev starts it."),
            "q2": Key(answer: 1, explanation: "2.0 moved every setting into a sidebar in the app."),
        ]
    ]
    /// quiz_grading.py: a submission sent as the timer ends still counts, and a revision takes at most 20 attempts.
    static let grace: Double = 2
    static let maximumAttempts = 20

    private(set) var attempts: [Attempt] = []
    private var counter = 0

    // MARK: The routes

    /// `quiz_attempt`: the open attempt on the revision, else its latest, else null. It only records time used.
    mutating func attempt(_ params: JSONValue, view row: JSONValue, now: Date) throws -> JSONValue {
        let current = row["revision"]?.int ?? 1
        guard case .int(let revision)? = params["revision"], (1...current).contains(revision),
            let chat = params["chat_id"]?.string, let id = row["id"]?.string
        else { throw Self.refused("Quiz revision not found.") }
        let mine = attempts.indices.filter {
            attempts[$0].chatID == chat && attempts[$0].viewID == id && attempts[$0].revision == revision
        }
        guard let index = mine.first(where: { attempts[$0].status == "open" }) ?? mine.last else { return .null }
        drift(index, view: row)
        return publicAttempt(attempts[index], elapsed: observe(index, now: now))
    }

    /// `quiz_start`: begins, or resumes, the one open attempt on the current revision.
    mutating func start(_ params: JSONValue, view row: JSONValue, now: Date) throws -> JSONValue {
        let current = row["revision"]?.int ?? 1
        guard case .int(let revision)? = params["revision"], revision == current else {
            throw Self.refused("This view changed to revision \(current). Open the new revision to start.")
        }
        guard row["status"]?.string == "ready" else { throw Self.refused("This quiz is no longer accepting attempts.") }
        guard let chat = params["chat_id"]?.string, let id = row["id"]?.string, Self.keys[id] != nil else {
            throw Self.refused("This quiz's answer key failed its integrity check. It cannot be graded.")
        }
        if let open = attempts.firstIndex(where: { $0.viewID == id && $0.revision == revision && $0.status == "open" }) {
            let elapsed = observe(open, now: now)
            if attempts[open].status == "open" { return publicAttempt(attempts[open], elapsed: elapsed) }
        }
        guard attempts.count(where: { $0.viewID == id && $0.revision == revision }) < Self.maximumAttempts else {
            throw Self.refused("This quiz has reached its attempt limit.")
        }
        counter += 1
        let minutes = row["data"]?["duration_minutes"]?.int ?? 1
        let made = Attempt(
            id: "demo-attempt-\(counter)", chatID: chat, viewID: id, revision: revision, status: "open", started: now,
            limit: Double(minutes * 60))
        attempts.append(made)
        return publicAttempt(made, elapsed: 0)
    }

    /// `quiz_save`: a draft in place of the phone's storage. A closed attempt refuses it.
    mutating func save(_ params: JSONValue, view row: JSONValue, now: Date) throws -> JSONValue {
        let (index, answers) = try open(params, view: row)
        switch attempts[index].status {
        case "open": break
        case "submitted": throw Self.refused("This attempt was already submitted.")
        default: throw Self.refused("Time ran out for this attempt; your earlier answers were kept.")
        }
        let elapsed = observe(index, now: now)
        if attempts[index].status == "open" { attempts[index].draft = answers }
        return publicAttempt(attempts[index], elapsed: elapsed)
    }

    /// `quiz_submit`: graded once; a repeat returns the stored outcome and changes nothing.
    mutating func submit(_ params: JSONValue, view row: JSONValue, now: Date) throws -> JSONValue {
        let (index, answers) = try open(params, view: row)
        if attempts[index].status == "open" {
            _ = observe(index, now: now)
            if attempts[index].status == "open" {
                attempts[index].status = "submitted"
                attempts[index].answers = answers
                attempts[index].result = Self.grade(row, key: Self.keys[attempts[index].viewID] ?? [:], answers: answers)
            }
            return publicAttempt(attempts[index], elapsed: nil)
        }
        if attempts[index].status == "submitted", attempts[index].answers != answers {
            throw Self.refused("This attempt was already graded. Start a new attempt to try again.")
        }
        return publicAttempt(attempts[index], elapsed: nil)
    }

    /// `quiz_share`: the run that made the quiz receives the result (in the demo it is always still there, waiting
    /// for its approval), once.
    mutating func share(_ params: JSONValue, view row: JSONValue) throws -> JSONValue {
        let index = try find(params)
        drift(index, view: row)
        guard attempts[index].status == "submitted" else {
            throw Self.refused("Only a submitted, graded attempt can be shared.")
        }
        attempts[index].shared = true
        return [
            "status": "shared", "shared": true, "input_id": .string("input-quiz-" + attempts[index].id),
            "run_id": row["owner_run_id"] ?? .null, "origin": "human",
        ]
    }

    // MARK: Pebble's checks

    private func find(_ params: JSONValue) throws -> Int {
        guard let chat = params["chat_id"]?.string, let id = params["attempt_id"]?.string,
            let index = attempts.firstIndex(where: { $0.id == id && $0.chatID == chat })
        else { throw Self.refused("Quiz attempt not found in this conversation.") }
        return index
    }

    /// `_open`: the attempt, still bound to the view's revision, and the answers it may take.
    private mutating func open(_ params: JSONValue, view row: JSONValue) throws -> (Int, [String: Int]) {
        let index = try find(params)
        drift(index, view: row)
        let current = row["revision"]?.int ?? 1
        guard attempts[index].status != "superseded", case .int(let revision)? = params["revision"],
            revision == attempts[index].revision
        else { throw Self.refused("This view changed to revision \(current). Your answers were kept and were not used.") }
        return (index, try Self.answers(params["answers"], view: row))
    }

    /// `_answers`: only this quiz's questions, each with one of its choices or nothing.
    private static func answers(_ value: JSONValue?, view row: JSONValue) throws -> [String: Int] {
        var choices: [String: Int] = [:]
        for question in row["data"]?["questions"]?.array ?? [] {
            if let id = question["id"]?.string { choices[id] = question["choices"]?.array?.count ?? 0 }
        }
        guard case .object(let given)? = value, given.keys.allSatisfy({ choices[$0] != nil }) else {
            throw refused("Answer only this quiz's questions.")
        }
        var kept: [String: Int] = [:]
        for (id, choice) in given where choice != .null {
            guard case .int(let index) = choice, (0..<(choices[id] ?? 0)).contains(index) else {
                throw refused("Choose one of the offered answers.")
            }
            kept[id] = index
        }
        return kept
    }

    /// `_drift`: an open attempt on a replaced or stopped revision is superseded.
    private mutating func drift(_ index: Int, view row: JSONValue) {
        guard attempts[index].status == "open" else { return }
        if row["revision"]?.int ?? 1 != attempts[index].revision || row["status"]?.string != "ready" {
            attempts[index].status = "superseded"
        }
    }

    /// `_observe`: the seconds used; past its time (and the grace) an open attempt expires, ungraded, its draft kept.
    private mutating func observe(_ index: Int, now: Date) -> Double? {
        guard attempts[index].status == "open" else { return nil }
        let elapsed = max(0, now.timeIntervalSince(attempts[index].started))
        if elapsed >= attempts[index].limit + Self.grace { attempts[index].status = "expired" }
        return elapsed
    }

    /// `grade`: a missing answer is wrong.
    private static func grade(_ row: JSONValue, key: [String: Key], answers: [String: Int]) -> JSONValue {
        var rows: [JSONValue] = []
        var score = 0
        for question in row["data"]?["questions"]?.array ?? [] {
            guard let id = question["id"]?.string, let item = key[id] else { continue }
            let chosen = answers[id]
            let correct = chosen == item.answer
            if correct { score += 1 }
            rows.append([
                "id": .string(id), "chosen": chosen.map(JSONValue.int) ?? .null, "correct": .bool(correct),
                "answer": .int(item.answer), "explanation": .string(item.explanation),
            ])
        }
        return ["score": .int(score), "total": .int(rows.count), "per_question": .array(rows)]
    }

    /// `_public_attempt`.
    private func publicAttempt(_ attempt: Attempt, elapsed: Double?) -> JSONValue {
        let given = attempt.answers ?? attempt.draft
        var item: [String: JSONValue] = [
            "attempt_id": .string(attempt.id), "artifact_id": .string(attempt.viewID), "revision": .int(attempt.revision),
            "origin": "human", "status": .string(attempt.status), "started": .double(attempt.started.timeIntervalSince1970),
            "deadline": .double(attempt.started.timeIntervalSince1970 + attempt.limit),
            "answers": .object(given.mapValues(JSONValue.int)), "result": .null, "shared": .bool(attempt.shared),
        ]
        switch attempt.status {
        case "open":
            if let elapsed { item["seconds_left"] = .double(max(0, ((attempt.limit - elapsed) * 10).rounded() / 10)) }
        case "submitted":
            item["result"] = attempt.result ?? .null
        case "expired":
            item["message"] = "Time ran out before this attempt was submitted, so it was not graded. Your answers were kept."
        default:
            item["message"] = "This quiz changed or stopped during the attempt, so it was not graded. Your answers were kept."
        }
        return .object(item)
    }

    private static func refused(_ words: String) -> RemoteCallError {
        .refused(PersonFacingError(message: words))
    }
}
