import Foundation
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit

/// A run's steps as Pebble's Details › Activity lists them (activity.ts `groupRows`): two or more finished reads and
/// searches in a row fold into "Explored · read 3 files, 2 searches", and a model turn's finished plumbing (context,
/// model rows, "Checked the reply") folds under its reply. Edits, commands, tests, agents, retries, waits and failures
/// are never folded: they are the steps people check.
enum ActivityEntry: Identifiable, Hashable, Sendable {
    case row(RunActivityItem)
    case group(key: Int, items: [RunActivityItem], label: String)

    var id: String {
        switch self {
        case .row(let item): "r\(item.seq)"
        case .group(let key, _, _): "g\(key)"
        }
    }

    /// The items it stands for, in order.
    var items: [RunActivityItem] {
        switch self {
        case .row(let item): [item]
        case .group(_, let items, _): items
        }
    }

    private static let folded: Set<StatusKey> = [.reading, .searching]

    static func isFoldable(_ item: RunActivityItem) -> Bool {
        item.kind == "tool" && item.status == "done" && item.activity.map(folded.contains) == true
    }

    static func isPlumbing(_ item: RunActivityItem) -> Bool {
        item.status == "done"
            && (item.kind == "context" || item.kind == "model" || (item.kind == "check" && item.label == "Checked the reply"))
    }

    /// Pebble's `groupRows`, step for step.
    static func entries(_ list: [RunActivityItem]) -> [ActivityEntry] {
        var out: [ActivityEntry] = []
        var run: [RunActivityItem] = []
        var turn: [RunActivityItem] = []
        func flush() {
            if run.count >= 2 {
                let reads = run.filter { $0.activity == .reading }.count
                out.append(
                    .group(key: run[0].seq, items: run, label: AppCopy.Details.explored(reads: reads, searches: run.count - reads)))
            } else {
                out += run.map(ActivityEntry.row)
            }
            run = []
        }
        func flushTurn() {
            if turn.count >= 2 {
                let reply = turn.reversed().first { $0.kind == "model" && $0.label.contains(" responded") }
                out.append(.group(key: turn[0].seq, items: turn, label: AppCopy.Details.modelTurn(reply?.label, count: turn.count)))
            } else {
                out += turn.map(ActivityEntry.row)
            }
            turn = []
        }
        for item in list {
            if isPlumbing(item) {
                flush()
                turn.append(item)
            } else if isFoldable(item) {
                flushTurn()
                run.append(item)
            } else {
                flush()
                flushTurn()
                out.append(.row(item))
            }
        }
        flush()
        flushTurn()
        return out
    }
}

/// A step's state as its mark says it (ThinkingDisclosure.vue `phase` and `mark`): a step Pebble left running in a run
/// that has ended reads as unfinished, never as live.
enum StepPhase: Equatable, Sendable {
    case done, failed, running, unfinished

    init(status: String, runIsLive: Bool) {
        switch status {
        case "failed": self = .failed
        case "running": self = runIsLive ? .running : .unfinished
        default: self = .done
        }
    }

    var word: String {
        switch self {
        case .done: AppCopy.Details.stepDone
        case .failed: AppCopy.Details.stepFailed
        case .running: AppCopy.Details.stepInProgress
        case .unfinished: AppCopy.Details.stepUnfinished
        }
    }
}

/// The line above the steps (activity.ts `receipt`): counted from the steps listed when there are any, so the count
/// always equals the list (U-45); otherwise Pebble's own count; "Took" when neither is known.
enum ActivityReceipt {
    static func line(_ steps: RunSteps) -> String? {
        let record = steps.details.run
        if steps.details.items.isEmpty {
            guard let counted = steps.pebbleCount else {
                return RunCopy.endLine(state: record.state, seconds: record.elapsed, countsKnown: false)
            }
            return RunCopy.endLine(state: record.state, seconds: record.elapsed, steps: counted)
        }
        return RunCopy.endLine(
            state: record.state, seconds: record.elapsed, steps: steps.listedSteps, retries: steps.listedRetries,
            waitedSeconds: steps.listedWait)
    }

    /// The line while the task works (U-58), in place of `line`: a settled run's words ("Worked for 2 s") don't fit a
    /// live one, and the record's time stands still between Pebble's state changes. Pebble's status word, the time
    /// since `start` (`liveStart`) and the steps so far, counted as `line` counts them.
    static func liveLine(_ steps: RunSteps, status: StatusKey?, since start: Date?, at now: Date) -> String {
        let record = steps.details.run
        let count = steps.details.items.isEmpty ? steps.pebbleCount ?? 0 : steps.listedSteps
        return AppCopy.Details.liveLine(
            word: StatusCopy.word(for: status ?? record.state.statusKey ?? .working),
            elapsed: start.flatMap { StatusCopy.formatExactElapsed(now.timeIntervalSince($0)) }, steps: count)
    }

    /// Where a working task's time counts from: the run bar's start when the task is the conversation's live run
    /// (Pebble's run start, its waits for the person left out), else the record's last update less its active seconds,
    /// which is how Pebble counts a live run's time (run_activity.py `_elapsed`).
    static func liveStart(_ record: LiveRunRecord, liveRun: LiveRun?) -> Date? {
        if let liveRun, liveRun.id == record.id, let started = liveRun.started { return started }
        return record.updated.map { $0.addingTimeInterval(-(record.elapsed ?? 0)) }
    }

    /// U-45's note when Pebble counted more steps than reached the phone; nil when the list holds them all.
    static func countNote(_ steps: RunSteps) -> String? {
        guard !steps.details.items.isEmpty, let counted = steps.pebbleCount, steps.missingSteps != nil else {
            return steps.isComplete ? nil : AppCopy.Details.moreThanListed
        }
        return AppCopy.Details.countedMore(pebble: counted, listed: steps.listedSteps)
    }
}
