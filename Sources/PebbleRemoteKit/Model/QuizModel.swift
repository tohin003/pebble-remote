import Foundation
import PebbleProtocol

// Lane Q (2026-10-31): taking one of Pebble's quizzes on the phone, as Pebble's window does (read-only Pebble checkout:
// src/components/QuizRenderer.vue, and backend/pebble/quiz_grading.py `QuizAttempts` for the replies). Pebble times the
// attempt, keeps its draft and grades it on the Mac; the answer key reaches the phone only inside a graded result.

/// One attempt at a quiz, as Pebble keeps it (quiz_grading.py `_public_attempt`).
///
/// Read as Pebble's window reads it (QuizRenderer.vue `parseAttempt` and `parseResult`), trusting nothing in the reply:
/// an answer must be one of its question's choices, an attempt for another view or conversation is refused, an open
/// attempt bound to another revision is closed for this view (superseded, never resumed), a result must grade this
/// quiz's questions (its `total` is their count), and an explanation is at most 1,500 characters.
public struct QuizAttempt: Sendable, Equatable {
    public enum Status: String, Sendable {
        case open, submitted, expired, superseded
    }

    /// One question's grade (quiz_grading.py `grade`: id, chosen, correct, answer, explanation).
    public struct Grade: Sendable, Equatable {
        /// What the person chose, as Pebble graded it.
        public enum Pick: Sendable, Equatable {
            case unanswered
            case choice(Int)
        }

        public var id: String
        public var correct: Bool
        /// Nil when Pebble's row doesn't say: the review then uses the answers on screen, as Pebble's window does.
        public var chosen: Pick?
        /// The right choice, when Pebble's row gives it.
        public var answer: Int?
        public var explanation: String?
    }

    /// Pebble's grade: the score out of the quiz's questions, and a row for each question it graded.
    public struct Result: Sendable, Equatable {
        public var score: Int
        public var total: Int
        public var grades: [Grade]

        public func grade(of question: String) -> Grade? { grades.first { $0.id == question } }
    }

    public var id: String
    public var status: Status
    /// The view revision Pebble bound the attempt to; nil when the reply doesn't say.
    public var revision: Int?
    /// When the attempt ends, in seconds since 1970 by the Mac's clock.
    public var deadline: Double
    /// The seconds left when Pebble answered (open attempts). The Mac's clock and the phone's may differ, so the
    /// countdown starts from this when a reply carries it (`QuizClock`).
    public var secondsLeft: Double?
    /// The answers Pebble keeps (the draft, or what was submitted), by question id; an unanswered question is absent.
    public var answers: [String: Int]
    public var result: Result?
    /// The run that made the quiz has the result.
    public var shared: Bool
}

/// Why the phone won't use a reply to a quiz call. Each has Pebble's window's words (`AppCopy.Views`).
public enum QuizReplyProblem: Error, Sendable, Hashable {
    /// "The app returned an invalid quiz attempt."
    case invalid
    /// "The app returned an attempt for another view."
    case otherView
    /// "The app returned an attempt for another conversation."
    case otherConversation
    /// "The app did not confirm the share."
    case notConfirmed
}

/// What a share did (quiz_grading.py `share`): the run that made the quiz has the result, or that run has finished and
/// Pebble wrote words the person may send instead.
public enum QuizShareReply: Sendable, Equatable {
    case shared
    case compose(String)
}

/// Where an open attempt's countdown stands. Pebble's window counts down to `deadline` on the Mac's own clock; the
/// phone's clock may differ from the Mac's, so the phone counts down from `seconds_left` as it received it, and from the
/// deadline only when a reply doesn't carry it.
public struct QuizClock: Sendable, Equatable {
    public var secondsLeft: Double?
    /// When the phone received the reply, by its own clock.
    public var receivedAt: Date
    public var deadline: Double
    /// The quiz's length in seconds: no countdown shows more, whatever a reply says.
    public var limit: Int

    public init(secondsLeft: Double?, receivedAt: Date, deadline: Double, limit: Int) {
        self.secondsLeft = secondsLeft
        self.receivedAt = receivedAt
        self.deadline = deadline
        self.limit = max(0, limit)
    }

    /// Whole seconds left at `now`, rounded up as Pebble's window rounds them (`Math.ceil`), never below zero.
    public func remaining(at now: Date) -> Int {
        let left = secondsLeft.map { $0 - now.timeIntervalSince(receivedAt) } ?? (deadline - now.timeIntervalSince1970)
        guard left.isFinite, left > 0 else { return 0 }
        return Int(min(left, Double(limit)).rounded(.up))
    }
}

/// One question in a graded attempt's review (QuizRenderer.vue `review`).
public struct QuizReviewRow: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        case correct, incorrect, unanswered, notGraded
    }

    /// The question's id.
    public var id: String
    /// Its place in the quiz, from 1.
    public var number: Int
    public var question: String
    public var state: State
    /// The person's choice, in its words ("Your answer: …").
    public var chosen: String?
    /// The right choice, in its words, only when the answer wasn't right ("Correct answer: …").
    public var correctAnswer: String?
    public var explanation: String?

    /// The review of `result`: every question in order. A question Pebble didn't grade is "Not graded" and shows the
    /// answer on screen; a grade that doesn't say what was chosen uses the answer on screen too.
    public static func rows(
        _ questions: [NativeView.Quiz.Question], result: QuizAttempt.Result, answers: [String: Int]
    ) -> [QuizReviewRow] {
        questions.enumerated().map { offset, question in
            let grade = result.grade(of: question.id)
            let pick: Int?
            switch grade?.chosen {
            case .choice(let index)?: pick = index
            case .unanswered?: pick = nil
            case nil: pick = answers[question.id]
            }
            let state: State
            if let grade {
                state = pick == nil ? .unanswered : grade.correct ? .correct : .incorrect
            } else {
                state = .notGraded
            }
            let right = grade?.answer.flatMap { question.choices.indices.contains($0) ? question.choices[$0] : nil }
            return QuizReviewRow(
                id: question.id, number: offset + 1, question: question.question, state: state,
                chosen: pick.flatMap { question.choices.indices.contains($0) ? question.choices[$0] : nil },
                correctAnswer: grade?.correct == true ? nil : right, explanation: grade?.explanation)
        }
    }
}

// MARK: - Reading Pebble's replies

extension QuizAttempt {
    /// Pebble's reply about an attempt at `quiz`, which `view` shows, checked as QuizRenderer.vue's `parseAttempt`
    /// checks it. Throws `QuizReplyProblem` where Pebble's window would refuse it, in the same order, so the same reply
    /// gets the same words.
    public init(reply: JSONValue, view: PebbleArtifact, quiz: NativeView.Quiz) throws {
        guard case .object(let row) = reply else { throw QuizReplyProblem.invalid }
        guard let id = row["attempt_id"]?.string, Self.isAttemptID(id) else { throw QuizReplyProblem.invalid }
        guard let deadline = row["deadline"]?.double, deadline.isFinite, deadline > 0 else {
            throw QuizReplyProblem.invalid
        }
        // `row.status ?? "open"`: an absent or null status is an open attempt.
        let word: String
        switch row["status"] {
        case nil, .null?: word = Status.open.rawValue
        case .string(let value)?: word = value
        default: throw QuizReplyProblem.invalid
        }
        guard var status = Status(rawValue: word) else { throw QuizReplyProblem.invalid }
        if let other = row["artifact_id"], other != .string(view.id) { throw QuizReplyProblem.otherView }
        if let other = row["chat_id"], other != .string(view.chatID) { throw QuizReplyProblem.otherConversation }

        var answers: [String: Int] = [:]
        switch row["answers"] {
        case nil: break
        case .object(let saved)?:
            for question in quiz.questions {
                guard let value = saved[question.id], value != .null else { continue }
                answers[question.id] = try Self.choice(value, of: question)
            }
        default: throw QuizReplyProblem.invalid
        }
        var result: Result?
        if let graded = row["result"], graded != .null { result = try Result(graded, quiz: quiz) }

        var revision: Int?
        if let bound = row["revision"] {
            guard let number = bound.int else { throw QuizReplyProblem.invalid }
            revision = number
            // An attempt bound to another revision is closed for this view, never resumed.
            if number != view.revision, status == .open { status = .superseded }
        }
        // Not read by Pebble's window, which has the Mac's clock: a number that can't be seconds left is left out.
        var secondsLeft: Double?
        if let left = row["seconds_left"]?.double, left.isFinite, left >= 0 { secondsLeft = left }

        self.init(
            id: id, status: status, revision: revision, deadline: deadline, secondsLeft: secondsLeft, answers: answers,
            result: result, shared: row["shared"] == .bool(true))
    }

    /// `choiceIndex`: a whole number naming one of the question's choices.
    static func choice(_ value: JSONValue, of question: NativeView.Quiz.Question) throws -> Int {
        guard let index = value.int, question.choices.indices.contains(index) else { throw QuizReplyProblem.invalid }
        return index
    }

    /// `/^[A-Za-z0-9_.:-]{1,128}$/`.
    static func isAttemptID(_ value: String) -> Bool {
        (1...128).contains(value.utf8.count)
            && value.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2E, 0x3A, 0x2D: true
                default: false
                }
            }
    }

    /// QuizRenderer.vue `text`: something besides white space, and at most `limit` UTF-16 units (JavaScript's length).
    static func isText(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= limit
    }

    /// The seconds a countdown starts from: Pebble's, as received now.
    public func clock(receivedAt now: Date, limit: Int) -> QuizClock {
        QuizClock(secondsLeft: secondsLeft, receivedAt: now, deadline: deadline, limit: limit)
    }
}

extension QuizAttempt.Result {
    /// QuizRenderer.vue `parseResult`.
    init(_ value: JSONValue, quiz: NativeView.Quiz) throws {
        let count = quiz.questions.count
        guard case .object(let row) = value, let total = row["total"]?.double, total == Double(count),
            let score = row["score"]?.int, (0...count).contains(score), case .array(let rows)? = row["per_question"],
            rows.count <= count
        else { throw QuizReplyProblem.invalid }
        var seen = Set<String>()
        var grades: [QuizAttempt.Grade] = []
        for entry in rows {
            guard case .object(let item) = entry, let id = item["id"]?.string, !seen.contains(id),
                let question = quiz.questions.first(where: { $0.id == id }), let correct = item["correct"]?.bool
            else { throw QuizReplyProblem.invalid }
            seen.insert(id)
            var grade = QuizAttempt.Grade(id: id, correct: correct)
            if let chosen = item["chosen"] {
                grade.chosen = chosen == .null ? .unanswered : .choice(try QuizAttempt.choice(chosen, of: question))
            }
            if let answer = item["answer"] { grade.answer = try QuizAttempt.choice(answer, of: question) }
            if let explanation = item["explanation"] {
                guard let words = explanation.string, QuizAttempt.isText(words, limit: 1500) else {
                    throw QuizReplyProblem.invalid
                }
                // Shown literally, as the view's other text is (control characters become spaces).
                grade.explanation = ViewText.clamp(words, 1500, multiline: true)
            }
            grades.append(grade)
        }
        self.init(score: score, total: count, grades: grades)
    }
}

extension QuizShareReply {
    /// quiz_grading.py `share`: `{shared: true}` when the run that made the quiz has the result; `{status: "compose",
    /// text}` when that run has finished. Anything else is refused as Pebble's window refuses it (`shared` must be
    /// true there).
    public init(reply: JSONValue) throws {
        guard reply.object != nil else { throw QuizReplyProblem.invalid }
        if reply["shared"] == .bool(true) {
            self = .shared
        } else if reply["status"] == "compose", let text = reply["text"]?.string,
            let words = ViewText.clamp(text, 2000, multiline: true)
        {
            self = .compose(words)
        } else {
            throw QuizReplyProblem.notConfirmed
        }
    }
}

extension PebbleArtifact {
    /// The quiz, when this view is one.
    public var quiz: NativeView.Quiz? {
        if case .quiz(let quiz) = view { quiz } else { nil }
    }
}
