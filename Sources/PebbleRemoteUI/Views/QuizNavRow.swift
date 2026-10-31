import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Back, how many are answered, and Next or Submit answers ("Checking…" while Pebble grades), as in Pebble's window
/// (QuizRenderer.vue `quiz-nav`). When a row doesn't fit (large text), the buttons share a line and the count goes
/// under them, then each takes its own line.
struct QuizNavRow: View {
    let session: QuizSession
    let showsSubmit: Bool
    let go: (Int) -> Void
    let submit: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PebbleSpace.s2) {
                backButton
                Spacer(minLength: PebbleSpace.s2)
                answered
                Spacer(minLength: PebbleSpace.s2)
                forwardButton
            }
            VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                HStack(spacing: PebbleSpace.s2) {
                    backButton
                    Spacer(minLength: PebbleSpace.s2)
                    forwardButton
                }
                answered
            }
            VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                backButton
                forwardButton
                answered
            }
        }
    }

    private var backButton: some View {
        Button(AppCopy.Views.back, systemImage: ViewSymbol.back, action: back)
            .buttonStyle(.pebbleSecondary)
            .disabled(session.index == 0)
    }

    @ViewBuilder private var forwardButton: some View {
        if showsSubmit {
            Button(session.isBusy ? AppCopy.Views.checking : AppCopy.Views.submitAnswers, action: submit)
                .buttonStyle(.pebblePrimary)
                .disabled(session.isBusy || !session.isWritable)
        } else {
            Button(action: next) {
                HStack(spacing: PebbleSpace.s1) {
                    Text(AppCopy.Views.next)
                    Image(systemName: ViewSymbol.forward)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.pebbleSecondary)
        }
    }

    private var answered: some View {
        Text(AppCopy.Views.answeredCount(session.answeredCount, of: session.questions.count))
            .font(PebbleFont.meta)
            .foregroundStyle(PebbleColor.mutedText)
    }

    private func back() {
        go(session.index - 1)
    }

    private func next() {
        go(session.index + 1)
    }
}
