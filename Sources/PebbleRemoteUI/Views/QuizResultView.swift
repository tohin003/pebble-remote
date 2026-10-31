import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A graded attempt (QuizRenderer.vue): the score, every question's review, Share result with Pebble, and Retake quiz.
/// Share shows only where the bridge takes it, and only while it can work or has worked: never a dead button.
struct QuizResultView: View {
    let session: QuizSession
    let share: () -> Void
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s4) {
            if let result = session.result {
                QuizScoreCard(result: result, expired: session.attempt?.status == .expired)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(session.review) { row in
                    QuizReviewRowView(row: row)
                    Divider()
                }
            }
            if let attempt = session.attempt, session.offersShare, attempt.shared || session.isWritable {
                QuizShareBox(
                    isShared: attempt.shared, isSharing: session.isSharing, canShare: session.canShare, share: share)
            }
            if session.canStart {
                Button(AppCopy.Views.retakeQuiz, action: start)
                    .buttonStyle(.pebbleSecondary)
            }
        }
    }
}
