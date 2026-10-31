import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The quiz's head (QuizRenderer.vue `quiz-head`): "Quiz · checked by Pebble", how many questions and minutes, and the
/// open attempt's clock. The view's title and version are the screen's own header.
struct QuizHeader: View {
    let session: QuizSession

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            Text(AppCopy.Views.quizLead)
                .font(PebbleFont.chip)
                .foregroundStyle(PebbleColor.secondaryText)
            if session.isValid, let quiz = session.quiz {
                HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
                    Text(AppCopy.Views.quizSize(questions: quiz.questions.count, minutes: quiz.durationMinutes))
                        .font(PebbleFont.cardBody)
                        .foregroundStyle(PebbleColor.text)
                    Spacer(minLength: PebbleSpace.s2)
                    if session.isOpen {
                        QuizClockText(session: session)
                    }
                }
            }
        }
    }
}
