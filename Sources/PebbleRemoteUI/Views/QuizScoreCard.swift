import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The graded score, "2 / 3", with who graded it (QuizRenderer.vue `quiz-score`). VoiceOver hears it in Pebble's own
/// words for a score: "2 of 3 correct".
struct QuizScoreCard: View {
    let result: QuizAttempt.Result
    /// The attempt ran out of time (Pebble's window says it was graded then).
    let expired: Bool

    var body: some View {
        HStack(spacing: PebbleSpace.s3) {
            Image(systemName: ViewSymbol.score)
                .font(.title)
                .foregroundStyle(PebbleColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(AppCopy.Views.score(result.score, of: result.total))
                    .font(.largeTitle.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(PebbleColor.text)
                    .accessibilityLabel(AppCopy.Views.scoreSpoken(result.score, of: result.total))
                Text(expired ? AppCopy.Views.gradedWhenTimeRanOut : AppCopy.Views.gradedByPebble)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(PebbleSpace.s4)
        .background(PebbleColor.soft, in: .rect(cornerRadius: PebbleRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: PebbleRadius.lg)
                .stroke(PebbleColor.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
