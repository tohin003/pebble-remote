import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// The quiz by its attempt's state, as Pebble's window lays it out (QuizRenderer.vue's template): Pebble reading the
/// attempt, one question at a time, the graded result, or the intro, with the last action's failure under it. It owns
/// the session while the view is open and hands it the view each time the screen reads it again.
///
/// A call that needs the unlock (C1) opens the unlock sheet from here, inside the view's own full-screen cover, so it
/// shows above the quiz; once the phone is unlocked (or connected), the session reads what it couldn't.
struct QuizFlow: View {
    let artifact: PebbleArtifact
    let compose: ((String) -> Void)?
    @Environment(RemoteStore.self) private var store
    @State private var session: QuizSession
    @State private var isUnlocking = false

    init(artifact: PebbleArtifact, store: RemoteStore, compose: ((String) -> Void)?) {
        self.artifact = artifact
        self.compose = compose
        _session = State(initialValue: QuizSession(view: artifact, store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s4) {
            QuizHeader(session: session)
            if !session.isValid {
                Text(AppCopy.Views.invalidQuiz)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.danger)
            } else if session.historical {
                QuizNoteText(AppCopy.Views.historicalQuiz)
            } else if session.isLoading {
                HStack(spacing: PebbleSpace.s2) {
                    ProgressView()
                    QuizNoteText(AppCopy.Views.loadingAttempt)
                }
                .accessibilityElement(children: .combine)
            } else if session.isOpen {
                QuizQuestionView(session: session, submit: submit)
            } else if session.result != nil {
                QuizResultView(session: session, share: share, start: start)
            } else {
                QuizIntro(session: session, start: start)
            }
            if let note = session.actionError {
                Text(QuizWords.note(note))
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.danger)
            }
        }
        .onChange(of: artifact, initial: true) { session.show(artifact) }
        .onChange(of: store.unlockedUntil) { resumeIfAble() }
        .onChange(of: store.bridge == nil) { resumeIfAble() }
        .onChange(of: session.unlockRequests) { isUnlocking = true }
        .onChange(of: session.actionError) { _, note in announce(note) }
        .sheet(isPresented: $isUnlocking) {
            UnlockSheet()
                .lockCover()
        }
    }

    private func start() {
        Task { await session.start() }
    }

    private func submit() {
        Task { await session.submit() }
    }

    /// Share result with Pebble. When the run that made the quiz has finished, Pebble's words for the result go to the
    /// conversation's message box and the view closes (`compose`), for the person to send.
    private func share() {
        Task {
            if let words = await session.share(composing: compose != nil) { compose?(words) }
        }
    }

    /// Reads what the quiz couldn't read before the phone was connected and unlocked (C1).
    private func resumeIfAble() {
        guard store.bridge != nil, !store.usesUnlock || store.isUnlocked else { return }
        Task { await session.resume() }
    }

    /// Pebble's window shows its errors as alerts (`role="alert"`), which VoiceOver speaks at once.
    private func announce(_ note: QuizSession.Note?) {
        guard let note else { return }
        AccessibilityNotification.Announcement(QuizWords.note(note)).post()
    }
}
