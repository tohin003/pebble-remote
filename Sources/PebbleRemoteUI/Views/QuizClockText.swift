import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The open attempt's clock, "04:31 left", in the danger colour for its last two minutes (QuizRenderer.vue
/// `quiz-clock`, urgent under 120 s). It counts from what Pebble said was left when the phone received it.
struct QuizClockText: View {
    let session: QuizSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = session.remaining(at: context.date)
            Text(AppCopy.Views.timeLeft(seconds))
                .font(PebbleFont.elapsed.weight(.semibold))
                .foregroundStyle(seconds < 120 ? PebbleColor.danger : PebbleColor.text)
                .accessibilityLabel(AppCopy.Views.timeLeftSpoken(seconds))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
