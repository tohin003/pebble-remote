import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Before an attempt, or after one that was closed (QuizRenderer.vue `quiz-intro`): what happened to the last attempt,
/// how the quiz works, and Start quiz (Start again after a closed one). A quiz that can't be taken here says why, with
/// no Start at all: the phone never shows a button that can't work (IA rule 6), where Pebble's window dims it.
struct QuizIntro: View {
    let session: QuizSession
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            if let replaced = session.replaced {
                QuizNoteText(AppCopy.Views.quizChanged(after: replaced))
            } else if session.attempt?.status == .superseded {
                QuizNoteText(AppCopy.Views.quizChangedWhileAnswering)
            } else if session.attempt?.status == .expired {
                QuizNoteText(AppCopy.Views.timeRanOut)
            }
            Text(AppCopy.Views.quizIntro)
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if session.isInactive, let status = session.view.status {
                QuizNoteText(AppCopy.Views.quizIs(status.rawValue))
            } else if !session.offersTaking {
                QuizNoteText(AppCopy.Views.openDesktopApp)
            }
            if session.isWritable {
                Button(action: start) {
                    Label(startTitle, systemImage: ViewSymbol.startQuiz)
                }
                .buttonStyle(.pebblePrimary)
                .disabled(!session.canStart)
            }
            Text(AppCopy.Views.generatedByAI)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.mutedText)
        }
    }

    private var startTitle: String {
        if session.isBusy { return AppCopy.Views.starting }
        return session.attempt == nil ? AppCopy.Views.startQuiz : AppCopy.Views.startAgain
    }
}
