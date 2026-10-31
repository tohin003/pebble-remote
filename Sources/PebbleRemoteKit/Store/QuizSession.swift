import Foundation
import Observation
import PebbleProtocol

/// Taking one of Pebble's quizzes on the phone, as Pebble's window does (QuizRenderer.vue). The attempt is read when the
/// view opens; Start begins one or resumes the open one; each choice goes to the Mac as a draft, one save at a time,
/// the latest answers winning; Submit has Pebble grade it; Share gives the result to the run that made the quiz.
/// Replies for a view the screen has moved on from are dropped (`generation`, `drafts`, as in Pebble's window), and
/// nothing in a reply is trusted (`QuizAttempt`).
///
/// Where the phone differs from Pebble's window, and why:
/// - **The unlock (C1).** Every quiz call needs it, reading the attempt too. Opening the view never raises the unlock
///   sheet: the attempt is read at once only when no unlock is needed now, and otherwise once the phone is unlocked
///   (`resume()`). Start goes through the unlock as any action does; a call that needs it asks the screen to open the
///   unlock sheet (`unlockRequests`) instead of showing the bridge's refusal under the quiz.
/// - **The clock.** The countdown starts from Pebble's `seconds_left` as received, since the phone's clock and the
///   Mac's may differ (`QuizClock`).
/// - **Drafts.** A save that a newer start or submission overtook leaves no "Saving…" behind, and a choice made in the
///   meantime still goes (Pebble's window drops it until the next choice).
/// - **Share.** When the run that made the quiz has finished, Pebble answers with words the person may send; they come
///   back from `share(composing:)` for the conversation's message box, where Pebble's window says "The app did not
///   confirm the share."
@MainActor
@Observable
public final class QuizSession {
    public enum SaveState: Sendable, Equatable {
        case idle, saving, saved, failed
    }

    /// What to say under the quiz about a call that failed: Pebble's or the bridge's words, or the phone's about a reply
    /// it won't use.
    public enum Note: Sendable, Equatable {
        case said(String)
        case reply(QuizReplyProblem)
    }

    /// The view as the screen has it now.
    public private(set) var view: PebbleArtifact
    /// An earlier revision, shown for reference (Pebble's window's history): never read, started or answered. The
    /// phone shows only the current revision so far.
    public let historical: Bool
    public private(set) var attempt: QuizAttempt?
    /// The choices on screen, by question id.
    public private(set) var answers: [String: Int] = [:]
    /// The question on screen, from 0.
    public private(set) var index = 0
    public private(set) var isLoading = false
    /// Starting or submitting.
    public private(set) var isBusy = false
    public private(set) var isSharing = false
    public private(set) var actionError: Note?
    /// Why the last draft wasn't saved ("Draft not saved: …").
    public private(set) var saveError: Note?
    public private(set) var saveState: SaveState = .idle
    /// The revision whose open attempt an update of the quiz closed, to say so once.
    public private(set) var replaced: Int?
    /// Goes up each time a call needs the unlock: the screen opens the unlock sheet.
    public private(set) var unlockRequests = 0
    /// The open attempt's countdown.
    public private(set) var clock: QuizClock?

    @ObservationIgnored private let store: RemoteStore
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var drafts = 0
    @ObservationIgnored private var saving = false
    @ObservationIgnored private var dirty = false
    /// The view ("chat:id") and revision whose attempt was last open here.
    @ObservationIgnored private var owner = ""
    @ObservationIgnored private var ownerRevision = 0
    @ObservationIgnored private var hasShown = false

    public init(view: PebbleArtifact, store: RemoteStore, historical: Bool = false) {
        self.view = view
        self.store = store
        self.historical = historical
    }

    // MARK: What the screen shows

    public var quiz: NativeView.Quiz? { view.quiz }
    public var questions: [NativeView.Quiz.Question] { quiz?.questions ?? [] }

    /// The checks of Pebble's window's `validate` that the phone's reading of the view leaves to make: answers go by
    /// question id, so the ids must be unique ("This quiz contains invalid display data.").
    public var isValid: Bool {
        guard let quiz else { return false }
        return Set(quiz.questions.map(\.id)).count == quiz.questions.count
    }

    /// A stopped or expired quiz ("This quiz is stopped.").
    public var isInactive: Bool { !view.isLive }

    /// The bridge takes quizzes from this phone (Pebble's window's `native`). Before the first welcome nothing is known,
    /// so the controls show.
    public var offersTaking: Bool {
        ["quiz_attempt", "quiz_start", "quiz_save", "quiz_submit"].allSatisfy(offered)
    }

    public var offersShare: Bool { offered("quiz_share") }

    /// Pebble's window's `writable`.
    public var isWritable: Bool { offersTaking && !historical && isValid && !isInactive }
    public var isOpen: Bool { attempt?.status == .open }
    public var canStart: Bool { isWritable && !isLoading && !isBusy && !isOpen }

    /// The graded result; a superseded attempt shows none.
    public var result: QuizAttempt.Result? { attempt?.status == .superseded ? nil : attempt?.result }

    public var canShare: Bool {
        guard let attempt, result != nil else { return false }
        return !attempt.shared && !isSharing && isWritable && offersShare
    }

    public var answeredCount: Int { questions.count(where: { answers[$0.id] != nil }) }

    public var review: [QuizReviewRow] {
        guard let result else { return [] }
        return QuizReviewRow.rows(questions, result: result, answers: answers)
    }

    /// Whole seconds left on the open attempt at `now`.
    public func remaining(at now: Date) -> Int { clock?.remaining(at: now) ?? 0 }

    /// "Time is up. Submit to see how you did.": the choices are closed, Submit isn't.
    public func isTimeUp(at now: Date) -> Bool { isOpen && remaining(at: now) == 0 }

    /// The choices take a tap.
    public func isAnswering(at now: Date) -> Bool { isWritable && isOpen && !isTimeUp(at: now) && !isBusy }

    // MARK: Reading

    /// The view as the screen has it now. Another view, conversation or revision reads its attempt from the start
    /// (Pebble's window watches the same three); a changed status or title only changes what can be done.
    public func show(_ fresh: PebbleArtifact) {
        let changed = !hasShown || Self.key(fresh) != Self.key(view) || fresh.revision != view.revision
        view = fresh
        hasShown = true
        if changed, let current = restart() {
            Task { await read(current) }
        }
    }

    /// Reads the attempt again from the start (QuizRenderer.vue `load`).
    public func load() async {
        hasShown = true
        guard let current = restart() else { return }
        await read(current)
    }

    /// The phone can act now (it was unlocked, or it connected): an attempt not read for want of that is read, and a
    /// draft the unlock refused is saved again.
    public func resume() async {
        if attempt == nil, !isLoading, !isBusy {
            await load()
        } else if isOpen, saveState == .failed, !saving {
            await save()
        }
    }

    /// The synchronous half of `load`: everything shown is reset at once, so an old attempt never shows with a new
    /// revision's questions. Returns the generation to read for, or nil when nothing is to be read.
    private func restart() -> Int? {
        generation += 1
        drafts += 1
        let key = Self.key(view)
        // An open attempt on an earlier revision was closed by the update: say so once.
        if isOpen, owner == key, ownerRevision < view.revision {
            replaced = ownerRevision
        } else if owner != key {
            replaced = nil
        }
        if owner != key { owner = "" }
        answers = [:]
        attempt = nil
        clock = nil
        index = 0
        actionError = nil
        saveError = nil
        saveState = .idle
        isBusy = false
        isSharing = false
        isLoading = false
        guard isValid, !historical, offersTaking, readsQuietly else { return nil }
        isLoading = true
        return generation
    }

    private func read(_ current: Int) async {
        guard let quiz else {
            isLoading = false
            return
        }
        do {
            let found = try await store.quizAttempt(for: view, quiz: quiz)
            guard current == generation else { return }
            adopt(found)
        } catch {
            // Quiet: a read the unlock refused leaves the intro, and the unlock reads again (`resume`).
            if current == generation, !Self.needsUnlock(error) { actionError = note(for: error) }
        }
        if current == generation { isLoading = false }
    }

    /// Reading needs no unlock now (C1): acting is unlocked, or the bridge doesn't ask for the unlock (no `remote.unlock`
    /// and no unlock time in its welcome). Nothing is read before the bridge's welcome says it offers the read, nor
    /// where the bridge would want Face ID for it: opening a view never asks for Face ID.
    private var readsQuietly: Bool {
        guard let bridge = store.bridge, bridge.methods.contains("quiz_attempt"), !bridge.elevated.contains("quiz_attempt")
        else { return false }
        let asksForUnlock = bridge.offersUnlock || bridge.unlockSeconds != nil
        return !asksForUnlock || store.isUnlocked
    }

    private func adopt(_ next: QuizAttempt?) {
        attempt = next
        clock = next.map { $0.clock(receivedAt: store.clock(), limit: (quiz?.durationMinutes ?? 0) * 60) }
        answers = next?.answers ?? [:]
        if next?.status == .open {
            owner = Self.key(view)
            ownerRevision = view.revision
        }
    }

    // MARK: Acting

    /// Start quiz, Start again or Retake quiz: begins an attempt, or resumes the open one.
    public func start() async {
        guard canStart, let quiz else { return }
        let current = generation
        isBusy = true
        actionError = nil
        do {
            let reply = try await store.startQuiz(view, quiz: quiz)
            guard current == generation else { return }
            guard reply.status == .open || reply.result != nil else { throw QuizReplyProblem.invalid }
            drafts += 1
            adopt(reply)
            index = 0
            replaced = nil
            saveState = .idle
        } catch {
            if current == generation { actionError = note(for: error) }
        }
        if current == generation { isBusy = false }
    }

    /// A choice for a question: shown at once, then saved as the draft. Nothing changes once time is up or while
    /// Pebble checks the answers.
    public func choose(_ choice: Int, for questionID: String) {
        guard isAnswering(at: store.clock()), let question = questions.first(where: { $0.id == questionID }),
            question.choices.indices.contains(choice)
        else { return }
        answers[questionID] = choice
        Task { await save() }
    }

    /// Back, Next or a question from the list.
    public func go(to question: Int) {
        guard questions.indices.contains(question) else { return }
        index = question
    }

    /// The draft goes to the Mac, never to the phone's storage: one save at a time, and the latest answers win
    /// (QuizRenderer.vue `save`).
    func save() async {
        guard let current = attempt, current.status == .open, let quiz else { return }
        if saving {
            dirty = true
            return
        }
        saving = true
        let draft = drafts
        saveState = .saving
        do {
            repeat {
                dirty = false
                try await store.saveQuiz(answers, attempt: current.id, view: view, quiz: quiz)
            } while dirty && draft == drafts
            if draft == drafts {
                saveState = .saved
                saveError = nil
            }
        } catch {
            if draft == drafts {
                saveState = .failed
                saveError = note(for: error)
            }
        }
        saving = false
        guard draft != drafts else { return }
        // A newer start or a submission overtook this save: it says nothing, and a choice made since for the attempt
        // open now goes.
        if saveState == .saving { saveState = .idle }
        if dirty, isOpen { await save() }
    }

    /// Submit answers. A refused submission keeps the answers on screen and is never sent again by itself.
    public func submit() async {
        guard let current = attempt, current.status == .open, !isBusy, isWritable, let quiz else { return }
        let started = generation
        isBusy = true
        actionError = nil
        drafts += 1
        do {
            let reply = try await store.submitQuiz(answers, attempt: current.id, view: view, quiz: quiz)
            guard started == generation else { return }
            guard reply.id == current.id else { throw QuizReplyProblem.invalid }
            let local = answers
            adopt(reply)
            if reply.status != .superseded {
                for (question, choice) in local where answers[question] == nil { answers[question] = choice }
            }
            saveState = .idle
        } catch {
            if started == generation { actionError = note(for: error) }
        }
        if started == generation { isBusy = false }
    }

    /// Share result with Pebble: only on the person's tap, and only once. The run that made the quiz receives the
    /// result. When that run has finished, Pebble answers with words the person may send instead: they are returned,
    /// for the conversation's message box, when the screen can put them there (`composing`); otherwise the share is
    /// unconfirmed, as in Pebble's window.
    public func share(composing: Bool) async -> String? {
        guard canShare, let current = attempt else { return nil }
        let started = generation
        isSharing = true
        actionError = nil
        defer {
            if started == generation { isSharing = false }
        }
        do {
            switch try await store.shareQuiz(attempt: current.id, view: view) {
            case .shared:
                if started == generation, var latest = attempt, latest.id == current.id {
                    latest.shared = true
                    attempt = latest
                }
                return nil
            case .compose(let words):
                guard composing else { throw QuizReplyProblem.notConfirmed }
                return words
            }
        } catch {
            if started == generation { actionError = note(for: error) }
            return nil
        }
    }

    // MARK: Helpers

    /// What to say about a failed call. A cancelled Face ID says nothing, and a call that needs the unlock opens the
    /// unlock sheet instead.
    private func note(for error: any Error) -> Note? {
        if let problem = error as? QuizReplyProblem { return .reply(problem) }
        if error is CancellationError { return nil }
        if case .cancelledByPerson? = error as? RemoteCallError { return nil }
        if Self.needsUnlock(error) {
            unlockRequests += 1
            return nil
        }
        return RemoteStore.personFacing(error).map { .said($0.message) }
    }

    /// The bridge refused until the person unlocks (C1).
    static func needsUnlock(_ error: any Error) -> Bool {
        guard case .refused(let refusal)? = error as? RemoteCallError else { return false }
        return refusal.code == "unlock_required"
    }

    private func offered(_ method: String) -> Bool { store.bridge?.methods.contains(method) ?? true }

    private static func key(_ view: PebbleArtifact) -> String { view.chatID + ":" + view.id }
}
