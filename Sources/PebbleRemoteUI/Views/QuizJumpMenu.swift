import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// "Question 3 of 12", which opens the list of every question with whether each is answered, the one on screen checked
/// (QuizRenderer.vue's "Jump to question" row of numbered buttons, folded into one native control, so up to 50 numbers
/// never crowd the screen).
struct QuizJumpMenu: View {
    let session: QuizSession
    let go: (Int) -> Void

    var body: some View {
        Menu {
            Picker(AppCopy.Views.jumpToQuestion, selection: current) {
                ForEach(Array(session.questions.enumerated()), id: \.element.id) { index, question in
                    let answered = session.answers[question.id] != nil
                    Label(
                        AppCopy.Views.questionInList(index + 1, answered: answered),
                        systemImage: answered ? ViewSymbol.answered : ViewSymbol.unanswered
                    )
                    .tag(index)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: PebbleSpace.s1) {
                Text(AppCopy.Views.questionOf(session.index + 1, session.questions.count))
                Image(systemName: ViewSymbol.questionList)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(PebbleFont.chip)
            .frame(minHeight: PebbleSize.minTap)
            .contentShape(.rect)
        }
        .accessibilityHint(AppCopy.Views.jumpToQuestion)
    }

    /// The question on screen; choosing another goes there as Back and Next do.
    private var current: Binding<Int> {
        Binding(get: { session.index }, set: { go($0) })
    }
}
