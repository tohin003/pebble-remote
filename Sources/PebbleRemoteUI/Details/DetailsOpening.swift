import PebbleRemoteKit

/// Which task the conversation's Details opens on: the one working now, else the one waiting for the person, else the
/// newest one the transcript shows (Pebble's drawer follows the latest task: App.vue `latestRun`). Nil only for a
/// conversation that has never run a task.
enum DetailsOpening {
    static func run(live: RunID?, task: RunID?, items: [TranscriptItem]) -> RunID? {
        if let live { return live }
        if let task { return task }
        for item in items.reversed() {
            switch item {
            case .runEnd(_, let runID, _, _, _): return runID
            case .message(let message):
                if let runID = message.runID { return runID }
            case .activity(_, let runID?, _, _): return runID
            default: continue
            }
        }
        return nil
    }

    @MainActor
    static func run(for transcript: Transcript) -> RunID? {
        run(live: transcript.run?.id, task: transcript.task?.runID, items: transcript.items)
    }
}

/// A conversation's Details, opened on one tab from elsewhere in the app.
struct DetailsTarget: Hashable, Sendable {
    let chatID: ChatID
    let tab: DetailsTab
}

extension DetailsOpening {
    /// Settings › Across Conversations (the lead's IA decision, 2026-10-31 02:30): a schedule, a schedule's notice or a
    /// shared window opens its own conversation's Details on Tools, the one home for its controls.
    static func tools(of chat: ChatID) -> DetailsTarget {
        DetailsTarget(chatID: chat, tab: .tools)
    }
}
