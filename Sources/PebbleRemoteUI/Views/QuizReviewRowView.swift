import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One question in a graded attempt's review (QuizRenderer.vue `quiz-review`): "Question 2 · Incorrect", the question,
/// "Your answer: …", "Correct answer: …" when the answer was wrong, and Pebble's explanation. Text from the quiz shows
/// literally.
struct QuizReviewRowView: View {
    let row: QuizReviewRow

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Label {
                Text(AppCopy.Views.reviewHeading(row.number, QuizWords.review(row.state)))
            } icon: {
                Image(systemName: QuizWords.reviewSymbol(row.state))
                    .accessibilityHidden(true)
            }
            .font(PebbleFont.chip)
            .foregroundStyle(QuizWords.reviewColor(row.state))
            Text(verbatim: row.question)
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.text)
            if let chosen = row.chosen {
                Text(AppCopy.Views.yourAnswer(chosen))
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.text)
            }
            if let answer = row.correctAnswer {
                Text(AppCopy.Views.correctAnswer(answer))
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.text)
            }
            if let explanation = row.explanation {
                Text(verbatim: explanation)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, PebbleSpace.s3)
        .accessibilityElement(children: .combine)
    }
}
