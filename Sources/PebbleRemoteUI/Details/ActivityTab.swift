import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// Details › Activity: what Pebble did, step by step, in Pebble's words (the Mac's step list, ThinkingDisclosure.vue).
/// What the person asked, the line Pebble's window shows above the steps (counted from the steps listed, so "6 steps"
/// always lists six: U-45), Pebble's note on how it ended, then the steps with their times, then Pebble's reasoning.
struct ActivityTab: View {
    let state: DetailsState
    @Environment(RemoteStore.self) private var store

    var body: some View {
        List {
            if let steps = state.steps {
                summary(steps)
                stepsSection(steps)
                // Lane G: the work view's summary once the run settled (pebble-ui-spec v1).
                if let work = steps.details.summary, !WorkSummaryChips.words(work).isEmpty {
                    Section(AppCopy.Views.summary) {
                        WorkSummaryChips(summary: work)
                    }
                }
                if let reasoning = steps.details.reasoning {
                    Section {
                        DisclosureGroup(AppCopy.Details.reasoning) {
                            Text(verbatim: reasoning)
                                .font(PebbleFont.cardBody)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .overlay {
            if state.steps == nil {
                if let problem = state.stepsProblem {
                    ContentUnavailableView(
                        AppCopy.Details.did, systemImage: PebbleSymbol.status(.error), description: Text(verbatim: problem))
                } else {
                    ProgressView()
                }
            }
        }
        .refreshable { await state.loadSteps(store) }
    }

    private func summary(_ steps: RunSteps) -> some View {
        let record = steps.details.run
        // While the task works: its status word and a time that counts on, from the run bar's start (U-58).
        let liveRun = store.liveRuns.first { $0.id == record.id }
        let since = state.runIsLive ? ActivityReceipt.liveStart(record, liveRun: liveRun) : nil
        return Section {
            if let goal = record.goal, !goal.isEmpty {
                Text(verbatim: goal)
                    .font(PebbleFont.cardTitle)
            }
            if state.runIsLive {
                TimelineView(.periodic(from: since ?? record.updated ?? .distantPast, by: 1)) { context in
                    Text(verbatim: ActivityReceipt.liveLine(steps, status: liveRun?.status, since: since, at: context.date))
                        .font(PebbleFont.meta)
                        .foregroundStyle(.secondary)
                }
            } else if let line = ActivityReceipt.line(steps) {
                Text(verbatim: line)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            } else if let key = record.state.statusKey {
                Text(verbatim: StatusCopy.word(for: key))
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            if let note = record.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(PebbleFont.cardBody)
            }
            if let count = ActivityReceipt.countNote(steps) {
                Label(count, systemImage: "info.circle")
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            // Lane G: the plan's progress and steps (the work view's header).
            if let header = steps.details.header, let plan = header.plan {
                WorkPlanHeader(
                    plan: plan, state: header.state, seconds: header.elapsed, since: since, isLive: state.runIsLive)
            }
        }
    }

    private func stepsSection(_ steps: RunSteps) -> some View {
        let entries = ActivityEntry.entries(steps.details.items)
        let live = state.runIsLive
        return Section {
            if entries.isEmpty {
                Text(verbatim: live ? AppCopy.Details.noStepYet : AppCopy.Details.noStepDetails)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                switch entry {
                case .row(let item):
                    ActivityStepRow(item: item, runIsLive: live)
                case .group(_, let items, let label):
                    ActivityGroupRow(label: label, items: items)
                }
            }
        } header: {
            Text(AppCopy.Details.steps)
                .accessibilityLabel(live ? AppCopy.Details.doing : AppCopy.Details.did)
        }
    }
}
