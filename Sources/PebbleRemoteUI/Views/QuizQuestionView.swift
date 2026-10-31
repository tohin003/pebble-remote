import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// The open attempt, one question at a time (QuizRenderer.vue): how many are answered, "Question 3 of 12" (which lists
/// every question to move to), the draft's state, the question and its choices as one radio group, and Back with Next
/// or Submit answers. Once time is up the choices close and Submit shows on every question, so handing in needs no
/// paging to the last one (Pebble's window offers it on the last question only).
///
/// Moving to another question moves VoiceOver to it, and the question reads "Question 3 of 12" before its words, as
/// Pebble's window announces it and focuses its heading. Only the parts that change with the clock are redrawn each
/// second, so the question list stays still while it is open.
struct QuizQuestionView: View {
    let session: QuizSession
    let submit: () -> Void
    @AccessibilityFocusState private var isQuestionFocused: Bool
    @State private var chosenCount = 0

    var body: some View {
        let count = session.questions.count
        if let question {
            VStack(alignment: .leading, spacing: PebbleSpace.s3) {
                ProgressView(value: Double(session.answeredCount), total: Double(max(1, count)))
                    .tint(PebbleColor.accent)
                    .accessibilityLabel(AppCopy.Views.questionsAnswered)
                    .accessibilityValue(AppCopy.Views.answeredCount(session.answeredCount, of: count))
                HStack(spacing: PebbleSpace.s2) {
                    QuizJumpMenu(session: session, go: go)
                    Spacer(minLength: PebbleSpace.s2)
                    if let saved = QuizWords.saveState(session.saveState) {
                        Text(saved)
                            .font(PebbleFont.meta)
                            .foregroundStyle(session.saveState == .failed ? PebbleColor.danger : PebbleColor.mutedText)
                    }
                }
                Text(verbatim: question.question)
                    .font(PebbleFont.title)
                    .foregroundStyle(PebbleColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(AppCopy.Views.questionOf(session.index + 1, count))
                    .accessibilityValue(Text(verbatim: question.question))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isQuestionFocused)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let timeUp = session.isTimeUp(at: context.date)
                    VStack(alignment: .leading, spacing: PebbleSpace.s3) {
                        VStack(spacing: PebbleSpace.s2) {
                            ForEach(Array(question.choices.enumerated()), id: \.offset) { index, words in
                                QuizChoiceRow(
                                    letter: AppCopy.Views.choiceLetter(index), words: words,
                                    isChosen: session.answers[question.id] == index,
                                    isEnabled: session.isAnswering(at: context.date)
                                ) {
                                    choose(index, for: question.id)
                                }
                            }
                        }
                        .id(question.id)
                        if timeUp {
                            QuizNoteText(AppCopy.Views.timeIsUp)
                        }
                        if let failure = session.saveError {
                            Text(AppCopy.Views.draftNotSavedBecause(QuizWords.note(failure)))
                                .font(PebbleFont.cardBody)
                                .foregroundStyle(PebbleColor.danger)
                        }
                        QuizNavRow(
                            session: session, showsSubmit: timeUp || session.index == count - 1, go: go, submit: submit)
                    }
                }
            }
            .sensoryFeedback(PebbleHaptics.selection, trigger: chosenCount)
            .onChange(of: session.saveError) { _, failure in
                guard let failure else { return }
                AccessibilityNotification.Announcement(AppCopy.Views.draftNotSavedBecause(QuizWords.note(failure))).post()
            }
        }
    }

    /// The question on screen.
    private var question: NativeView.Quiz.Question? {
        session.questions.indices.contains(session.index) ? session.questions[session.index] : nil
    }

    private func choose(_ choice: Int, for question: String) {
        let before = session.answers[question]
        session.choose(choice, for: question)
        if session.answers[question] != before { chosenCount += 1 }
    }

    /// Back, Next or a question from the list: VoiceOver goes to the question.
    private func go(_ index: Int) {
        session.go(to: index)
        isQuestionFocused = true
    }
}
