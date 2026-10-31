import PebbleDesign
import SwiftUI

/// Share result with Pebble, or "Shared with Pebble" once it is, and what sharing does (QuizRenderer.vue `quiz-share`).
/// Sharing asks for Face ID: it gives the result to the run that made the quiz.
struct QuizShareBox: View {
    let isShared: Bool
    let isSharing: Bool
    let canShare: Bool
    let share: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            if isShared {
                Label(AppCopy.Views.sharedWithPebble, systemImage: ViewSymbol.shared)
                    .font(PebbleFont.cardTitle)
                    .foregroundStyle(PebbleColor.accent)
            } else {
                Button(action: share) {
                    Label(isSharing ? AppCopy.Views.sharing : AppCopy.Views.shareResult, systemImage: ViewSymbol.shareResult)
                }
                .buttonStyle(.pebblePrimary)
                .disabled(!canShare)
            }
            Text(AppCopy.Views.shareNote)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PebbleSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: PebbleRadius.md)
                .stroke(PebbleColor.line, lineWidth: 1)
        }
        .sensoryFeedback(PebbleHaptics.sent, trigger: isShared) { _, shared in shared }
        .onChange(of: isShared) { _, shared in
            if shared { AccessibilityNotification.Announcement(AppCopy.Views.sharedWithPebble).post() }
        }
    }
}
