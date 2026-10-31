import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The goal's steps (GoalPanel.vue's steps table, DT-11 and DT-12): each step with its state, the steps it comes after
/// and what blocks it. While the goal is current, a step opens its menu (Edit step, Block step, Unblock) and Add step
/// ends the list: the rarer controls one tap away, each in one place.
struct GoalStepsSection: View {
    let goal: GoalRecord
    let busy: Bool
    /// Opens an edit's sheet.
    let edit: (GoalEdit) -> Void
    /// Unblock, which needs no words: Pebble's notice when it took.
    let unblock: (GoalRecord.Step) -> Void
    @Environment(RemoteStore.self) private var store

    var body: some View {
        Section {
            if goal.steps.isEmpty {
                Text(AppCopy.Goals.noSteps)
                    .foregroundStyle(.secondary)
            }
            ForEach(goal.steps) { step in
                if goal.isCurrent, hasActions(step) {
                    Menu {
                        actions(step)
                    } label: {
                        row(step, opens: true)
                    }
                    .disabled(busy)
                    .accessibilityLabel(AppCopy.Goals.stepActions(step.id, step.title))
                    .accessibilityValue(meta(step) ?? "")
                } else {
                    row(step, opens: false)
                }
            }
            if goal.isCurrent, store.bridgeOffers("goal_step_add") {
                Button(AppCopy.Goals.addStep, systemImage: "plus") { edit(.addStep) }
                    .disabled(busy || goal.steps.count >= GoalLimits.steps)
            }
        } header: {
            Text(AppCopy.Details.stepsCaption(done: goal.progress.stepsDone, total: goal.progress.stepsTotal))
        } footer: {
            if goal.isCurrent, goal.steps.count >= GoalLimits.steps {
                Text(AppCopy.Goals.stepsFull(GoalLimits.steps))
            }
        }
    }

    private func row(_ step: GoalRecord.Step, opens: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(verbatim: AppCopy.Goals.stepChoice(step.id, step.title))
                    .foregroundStyle(PebbleColor.text)
                if let meta = meta(step) {
                    Text(verbatim: meta)
                        .font(PebbleFont.meta)
                        .foregroundStyle(step.isBlocked ? PebbleColor.danger : PebbleColor.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if opens {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(PebbleColor.accent)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    /// "pending · After s1 · ready", or "blocked · Your note: waiting for the design".
    private func meta(_ step: GoalRecord.Step) -> String? {
        let blocker = AppCopy.Goals.stepBlocker(
            kind: step.blocker?.kind, ref: step.blocker?.ref, active: step.blocker?.isActive ?? true,
            ready: step.isReady)
        let parts = [AppCopy.Details.stepStatus(step.status), AppCopy.Goals.afterSteps(step.after), blocker]
        return parts.compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    private func hasActions(_ step: GoalRecord.Step) -> Bool {
        store.bridgeOffers("goal_step_edit") || store.bridgeOffers("goal_step_block")
    }

    @ViewBuilder
    private func actions(_ step: GoalRecord.Step) -> some View {
        if store.bridgeOffers("goal_step_edit") {
            Button(AppCopy.Goals.editStep, systemImage: "pencil") { edit(.step(step)) }
        }
        if store.bridgeOffers("goal_step_block") {
            if step.isBlocked {
                Button(AppCopy.Goals.unblock, systemImage: "lock.open") { unblock(step) }
                    .accessibilityLabel(AppCopy.Goals.unblockStep(step.id))
            } else if step.status != "completed" {
                Button(AppCopy.Goals.blockStep, systemImage: "hand.raised") { edit(.block(step)) }
            }
        }
    }
}
