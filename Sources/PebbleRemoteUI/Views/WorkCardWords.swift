import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit

/// A work-view card's title and state in words, as Pebble's window words them (workView.ts `cardTitle`, WorkCard.vue
/// `status`). The title may be a command or a Git sentence: display text, shown literally.
enum WorkCardWords {
    static func title(_ card: WorkCard<RunActivityItem>) -> String {
        let first = card.views.first?.content
        switch card.kind {
        case .explored:
            let counts = card.exploredCounts
            return AppCopy.Views.explored(reads: counts.reads, searches: counts.searches)
        case .web:
            return AppCopy.Views.searchedTheWeb
        case .files:
            return AppCopy.Views.changedFiles(max(1, card.fileChanges.count))
        case .command:
            if case .command(let command)? = first, let line = command.command { return line }
            return AppCopy.Views.aCommand
        case .tests:
            if case .tests(let tests)? = first { return AppCopy.Views.tests(recipe: tests.recipe) }
            return AppCopy.Views.tests(recipe: nil)
        case .git:
            if case .git(let git)? = first {
                if let summary = git.summary { return summary }
                if let branch = git.branch { return AppCopy.Views.onBranch(branch) }
            }
            return AppCopy.Views.git
        case .window:
            if case .window(let window)? = first, let name = window.app ?? window.title { return name }
            return AppCopy.Views.anAppWindow
        case .agents:
            return AppCopy.Views.agents(card.views.count)
        case .checks:
            return AppCopy.Views.whatYourRequestRequires
        }
    }

    /// The card's state chip; nil when there is nothing to say. `runIsLive`: a step left running in a run that ended
    /// is unfinished, never in progress.
    static func status(_ card: WorkCard<RunActivityItem>, runIsLive: Bool) -> (words: String, tone: WorkTone)? {
        let first = card.views.first?.content
        switch first {
        case .command(let command)?:
            let words = AppCopy.Views.commandOutcome(state: command.state, exit: command.exit, seconds: command.seconds)
            return words.isEmpty ? nil : (words, command.state?.tone ?? .neutral)
        case .tests(let tests)?:
            guard let state = tests.state else { return nil }
            return (AppCopy.Views.state(state), state.tone)
        case .checks(let checks)?:
            if (checks.unmet ?? 0) > 0 { return (AppCopy.Views.notAllMet, .open) }
            return checks.requirements.isEmpty ? nil : (AppCopy.Views.allMet, .good)
        default:
            if card.isRunning { return runIsLive ? (AppCopy.Views.inProgress, .neutral) : (AppCopy.Views.unfinished, .neutral) }
            if card.hasFailed { return (AppCopy.Views.failed, .bad) }
            return nil
        }
    }

    /// The card read out: its title and its state.
    static func spoken(_ card: WorkCard<RunActivityItem>, runIsLive: Bool) -> String {
        [title(card), status(card, runIsLive: runIsLive)?.words].compactMap { $0 }.joined(separator: ", ")
    }

    /// A single item's card (Details › Activity draws each step on its own).
    static func card(for item: RunActivityItem) -> WorkCard<RunActivityItem>? {
        guard let view = item.view, let kind = view.cardKind else { return nil }
        return WorkCard(kind: kind, items: [item], views: [view])
    }
}
