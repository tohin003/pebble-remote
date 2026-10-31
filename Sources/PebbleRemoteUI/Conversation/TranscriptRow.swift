import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One transcript line: a message, an activity line, a card, a question, a run's end, a card Pebble acted on with its
/// Undo, the task's state and decisions, the handoff offer, or a command. Always one VStack, so every row has the same
/// shape for the lazy stack.
struct TranscriptRow: View {
    let item: TranscriptItem
    /// Pebble's counts for finished runs, for their end lines.
    let recaps: [RunID: RunRecap]
    /// Opens a run's details from its end line; nil when the bridge doesn't offer them.
    var showDetails: ((RunID) -> Void)? = nil
    /// Opens a recovery sheet (uncertain outcomes, new limits, a card's details, a command's typing) on the screen.
    var present: RecoveryPresenter? = nil

    var body: some View {
        VStack(alignment: .leading) {
            switch item {
            case .message(let message):
                MessageBubble(
                    role: message.role == .user ? .person : .pebble, text: message.text,
                    isStreaming: message.isStreaming)
            case .activity(_, _, let text, let status):
                ActivityLine(text: text, status: status)
            case .review(let review):
                ReviewItemCard(item: review, present: present)
            case .question(let card):
                QuestionCardForm(card: card)
            case .runEnd(_, let runID, let state, let seconds, let note):
                if let showDetails {
                    Button {
                        showDetails(runID)
                    } label: {
                        // A 44 pt row to tap, not the line's own 17 pt (the re-check's U-22).
                        RunEndLine(state: state, seconds: seconds, note: note, recap: recaps[runID])
                            .tapTarget(alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(AppCopy.Conversation.whatPebbleDid)
                } else {
                    RunEndLine(state: state, seconds: seconds, note: note, recap: recaps[runID])
                }
            case .action(let record):
                ActionRecordRow(record: record)
            case .task(let task):
                TaskCard(task: task, showDetails: showDetails, present: present)
            case .handoff(let offer):
                HandoffCard(offer: offer)
            case .command(let job):
                CommandCard(job: job, present: present)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
