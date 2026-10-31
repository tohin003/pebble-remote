import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Details › Task: the conversation's goal (GoalPanel.vue, inventory item 11) and the task's helper agents (AgentPanel.vue,
/// item 14). Settling a goal — Mark done, Abandon, checking or deciding a criterion — is the person's decision where its
/// criteria show (Findings F5): here, with Face ID. Lane T: a criterion's Edit, the steps' menus and Add step open
/// sheets (DT-08, DT-11, DT-12), the Blockers' Review opens the waiting card (DT-13), and an agent opens its own screen
/// (DT-21), where its Send input and Cancel now live, as on the Mac.
struct TaskTab: View {
    let state: DetailsState
    /// A task works in this conversation now ("Continue goal" waits for it).
    let isWorking: Bool
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var newGoal = ""
    @State private var isSettingGoal = false
    @State private var newCriterion = ""
    @State private var checkedByEvidence = false
    @State private var isConfirmingAbandon = false
    @State private var busy = false
    @State private var done: String?
    /// Lane T: the goal edit whose sheet shows, and the waiting card a blocker's Review opened.
    @State private var editing: GoalEdit?
    @State private var reviewing: ReviewItem?
    @FocusState private var goalFieldFocused: Bool

    var body: some View {
        List {
            if !store.readsQuietly {
                Section { UnlockStatusRow() }
            }
            if let done {
                Section {
                    Label(done, systemImage: "checkmark.circle")
                        .font(PebbleFont.cardBody)
                }
            }
            if let goal = state.goal {
                goalSection(goal)
                criteriaSections(goal)
                GoalStepsSection(goal: goal, busy: busy, edit: { editing = $0 }, unblock: { unblock($0, of: goal) })
                GoalBlockersSection(goal: goal, review: review)
            } else if store.bridgeOffers("goal_list") {
                noGoalSection
            }
            if !earlier.isEmpty {
                Section(AppCopy.Details.earlierGoals) {
                    ForEach(earlier) { summary in
                        LabeledContent(summary.title) {
                            Text(verbatim: "\(summary.state) \u{00B7} \(summary.progress.criteriaMet)/\(summary.progress.criteriaTotal)")
                        }
                    }
                }
            }
            if store.bridgeOffers("agent_list") {
                agentsSection
            }
            // Lane T (DT-26 to DT-31): Pebble's last Task section, "Export a view", one tap away.
            if store.bridgeOffers("export_preview"), store.views(in: state.chatID).contains(where: \.isExportable) {
                Section {
                    NavigationLink {
                        ExportScreen(chatID: state.chatID, viewID: nil)
                    } label: {
                        Label(AppCopy.Exports.title, systemImage: "doc.text")
                    }
                    .accessibilityHint(AppCopy.Exports.opensHint)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog(
            AppCopy.Details.abandonTitle, isPresented: $isConfirmingAbandon, titleVisibility: .visible, presenting: state.goal
        ) { goal in
            Button(AppCopy.Details.abandonConfirm, role: .destructive) {
                change(AppCopy.Details.goalAbandoned) { state.show(goal: try await store.settleGoal(goal, done: false)) }
            }
            Button(AppCopy.Details.keepGoal, role: .cancel) {}
        } message: { _ in
            Text(AppCopy.Details.goalAbandoned)
        }
        .sheet(item: $editing) { edit in
            GoalEditSheet(edit: edit, state: state) { words in done = words }
                .lockCover()
        }
        .sheet(item: $reviewing) { item in
            ReviewCardSheet(item: item)
                .lockCover()
        }
        .task(id: store.readsQuietly) {
            guard store.readsQuietly else { return }
            if !state.goalsRead { await state.loadGoals(store) }
            if !state.agentsRead { await state.loadAgents(store) }
        }
        .refreshable {
            guard store.readsQuietly else { return }
            await state.loadGoals(store)
            await state.loadAgents(store)
        }
    }

    private var earlier: [GoalSummary] { state.goals.filter { !$0.isCurrent } }

    // MARK: The goal

    private func goalSection(_ goal: GoalRecord) -> some View {
        Section {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(AppCopy.Details.goalTitle(goal.title))
                    .font(PebbleFont.cardTitle)
                Text(
                    AppCopy.Details.goalLine(
                        state: goal.state, met: goal.progress.criteriaMet, total: goal.progress.criteriaTotal,
                        done: goal.progress.stepsDone, steps: goal.progress.stepsTotal, blocker: goal.blockers.first)
                )
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if !goal.isPaused, store.bridgeOffers("goal_continue") {
                Button(AppCopy.Details.continueGoal, systemImage: "play") {
                    change(AppCopy.Details.goalContinued) { try await store.continueGoal(goal) }
                }
                .disabled(busy || isWorking)
            }
            if store.bridgeOffers("goal_state") {
                Button(
                    goal.isPaused ? AppCopy.Details.resumeGoal : AppCopy.Details.pauseGoal,
                    systemImage: goal.isPaused ? "play.circle" : "pause.circle"
                ) {
                    let paused = !goal.isPaused
                    change(paused ? AppCopy.Details.goalPaused : AppCopy.Details.goalResumed) {
                        state.show(goal: try await store.setGoalPaused(goal, paused))
                    }
                }
                .disabled(busy)
                Button(AppCopy.Details.markDone, systemImage: "checkmark.seal") {
                    change(AppCopy.Details.goalDone) { state.show(goal: try await store.settleGoal(goal, done: true)) }
                }
                .disabled(busy)
                Button(AppCopy.Details.abandon, systemImage: "xmark.circle", role: .destructive) {
                    isConfirmingAbandon = true
                }
                .disabled(busy)
            }
        } header: {
            Text(AppCopy.Details.goal)
        } footer: {
            Text(goal.note.map { $0 + " " + AppCopy.Details.settleNote } ?? AppCopy.Details.settleNote)
        }
    }

    @ViewBuilder
    private func criteriaSections(_ goal: GoalRecord) -> some View {
        let accepted = goal.criteria.filter { !$0.isProposed && $0.status != "rejected" }
        let proposed = goal.criteria.filter(\.isProposed)
        Section {
            if accepted.isEmpty {
                Text(AppCopy.Details.noCriteria)
                    .foregroundStyle(.secondary)
            }
            ForEach(accepted) { criterion in
                criterionRow(criterion, of: goal)
            }
            if store.bridgeOffers("goal_criterion_add") {
                TextField(AppCopy.Details.newCriterion, text: $newCriterion, prompt: Text(AppCopy.Details.criterionPlaceholder))
                    .submitLabel(.done)
                Picker(AppCopy.Details.checkedByTitle, selection: $checkedByEvidence) {
                    Text(AppCopy.Details.criterionKind("human_check")).tag(false)
                    Text(AppCopy.Details.criterionKind("evidence")).tag(true)
                }
                Button(AppCopy.Details.addCriterion, systemImage: "plus") {
                    let text = newCriterion.trimmingCharacters(in: .whitespacesAndNewlines)
                    let evidence = checkedByEvidence
                    change(AppCopy.Details.criterionAdded) {
                        state.show(goal: try await store.addCriterion(text, evidence: evidence, to: goal))
                        newCriterion = ""
                    }
                }
                .disabled(busy || newCriterion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text(AppCopy.Details.criteriaCaption(met: goal.progress.criteriaMet, total: goal.progress.criteriaTotal))
        }
        if !proposed.isEmpty {
            Section(AppCopy.Details.proposals) {
                ForEach(proposed) { criterion in
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                        Text(verbatim: criterion.text)
                        Text(AppCopy.Details.criterionKind(criterion.kind))
                            .font(PebbleFont.meta)
                            .foregroundStyle(.secondary)
                        HStack(spacing: PebbleSpace.s4) {
                            Button(AppCopy.Details.accept) { decide(criterion, accept: true, of: goal) }
                            Button(AppCopy.Details.reject, role: .destructive) { decide(criterion, accept: false, of: goal) }
                        }
                        .buttonStyle(.borderless)
                        .disabled(busy || !goal.isCurrent)
                    }
                }
            }
        }
    }

    private func criterionRow(_ criterion: GoalCriterion, of goal: GoalRecord) -> some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            Text(verbatim: criterion.text)
            if criterion.origin == "agent" {
                Text(AppCopy.Details.proposedAccepted)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            Text(
                [
                    AppCopy.Details.criterionKind(criterion.kind), AppCopy.Details.criterionStatus(criterion.status),
                    AppCopy.Details.checkedBy(criterion.checkedBy),
                ].compactMap { $0 }.joined(separator: " \u{00B7} ")
            )
            .font(PebbleFont.meta)
            .foregroundStyle(criterion.status == "met" ? AnyShapeStyle(PebbleColor.accent) : AnyShapeStyle(.secondary))
            if let detail = criterion.detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            if goal.isCurrent {
                // Lane T: side by side, or stacked where the largest text sizes leave no room.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PebbleSpace.s4) { criterionButtons(criterion, of: goal) }
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) { criterionButtons(criterion, of: goal) }
                }
                .buttonStyle(.borderless)
                .disabled(busy)
            }
        }
    }

    @ViewBuilder
    private func criterionButtons(_ criterion: GoalCriterion, of goal: GoalRecord) -> some View {
        if store.bridgeOffers("goal_criterion_check") {
            if criterion.status == "met" {
                Button(AppCopy.Details.markNotMet) { check(criterion, met: false, of: goal) }
            } else {
                Button(criterion.isEvidence ? AppCopy.Details.verifyEvidence : AppCopy.Details.markMet) {
                    check(criterion, met: true, of: goal)
                }
            }
        }
        // Lane T (DT-08): Edit beside the check, as in Pebble's row; Pebble clears the check on Save.
        if store.bridgeOffers("goal_criterion_edit") {
            Button(AppCopy.Goals.edit) { editing = .criterion(criterion) }
                .accessibilityLabel(AppCopy.Goals.editCriterion(criterion.id))
        }
    }

    private var noGoalSection: some View {
        Section {
            if isSettingGoal {
                TextField(AppCopy.Details.goal, text: $newGoal, prompt: Text(AppCopy.Details.goalPlaceholder), axis: .vertical)
                    .focused($goalFieldFocused)
                    .submitLabel(.done)
                    .closesKeyboardOnEmptyReturn($newGoal, focus: $goalFieldFocused)
                HStack(spacing: PebbleSpace.s4) {
                    Button(AppCopy.Details.startGoal) { startGoal() }
                        .disabled(busy || newGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(AppCopy.Common.cancel, role: .cancel) {
                        isSettingGoal = false
                        newGoal = ""
                        goalFieldFocused = false
                    }
                }
                .buttonStyle(.borderless)
            } else {
                Text(AppCopy.Details.noGoal)
                    .foregroundStyle(.secondary)
                if store.bridgeOffers("goal_create") {
                    Button(AppCopy.Details.setGoal, systemImage: "flag") {
                        isSettingGoal = true
                        goalFieldFocused = true
                    }
                    .disabled(busy)
                }
            }
        } header: {
            Text(AppCopy.Details.goal)
        } footer: {
            Text(AppCopy.Details.goalNote)
        }
    }

    // MARK: Agents

    private var agentsSection: some View {
        Section(AppCopy.Details.agents) {
            if state.agentsRead, state.agents.isEmpty {
                Text(AppCopy.Details.noAgents)
                    .foregroundStyle(.secondary)
            }
            ForEach(state.agents) { agent in
                // Lane T (DT-21): choosing an agent opens it (`agent_get`); the tree's row is AgentPanel.vue's: the
                // name, its state, then the task (cut at 120 characters) and its use.
                NavigationLink {
                    AgentScreen(agent: agent, state: state)
                } label: {
                    VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                        Text(verbatim: agent.name ?? agent.id)
                            .font(PebbleFont.cardTitle)
                        Text(AppCopy.Goals.agentStatus(agent.status))
                            .font(PebbleFont.meta)
                            .foregroundStyle(.secondary)
                        let used = AppCopy.Goals.used(calls: nil, tokens: agent.tokens, seconds: agent.seconds)
                        if let line = AppCopy.Goals.rowLine(task: agent.task, used: used) {
                            Text(verbatim: line)
                                .font(PebbleFont.meta)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, CGFloat(max(0, agent.depth - 1)) * PebbleSpace.s4)
                }
                .accessibilityHint(AppCopy.Goals.opensAgentHint)
            }
        }
    }

    // MARK: Changing

    private func startGoal() {
        let title = newGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        change(AppCopy.Details.goalStarted) {
            state.show(goal: try await store.createGoal(title, in: state.chatID))
            newGoal = ""
            isSettingGoal = false
            goalFieldFocused = false
            await state.loadGoals(store)
        }
    }

    private func check(_ criterion: GoalCriterion, met: Bool, of goal: GoalRecord) {
        let words =
            !met
            ? AppCopy.Details.criterionNotMet(criterion.id)
            : criterion.isEvidence ? AppCopy.Details.criterionByEvidence(criterion.id) : AppCopy.Details.criterionByYou(criterion.id)
        change(words) { state.show(goal: try await store.checkCriterion(criterion, met: met, of: goal)) }
    }

    private func decide(_ criterion: GoalCriterion, accept: Bool, of goal: GoalRecord) {
        change(AppCopy.Details.proposalDecided(criterion.id, accepted: accept)) {
            state.show(goal: try await store.reviewCriterion(criterion, accept: accept, of: goal))
        }
    }

    /// Lane T (DT-12): Unblock needs no words, so it goes at once, with Pebble's notice.
    private func unblock(_ step: GoalRecord.Step, of goal: GoalRecord) {
        change(AppCopy.Goals.stepUnblocked(step.id)) {
            state.show(goal: try await store.unblockStep(step, of: state.goal ?? goal))
        }
    }

    /// Lane T (DT-13): the waiting card itself when it waits on this iPhone; otherwise Reviews, as the Mac's Review
    /// opens its reviews.
    private func review(_ blocker: GoalBlocker) {
        if let item = store.waitingReview(for: blocker, in: state.chatID) {
            reviewing = item
        } else {
            dismiss()
            router.open(.reviews)
        }
    }

    /// One change at a time; Pebble's notice when it took, its refusal in this sheet when it didn't. A refused change
    /// reads the goal again, as Pebble's panel does.
    private func change(_ words: String, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        done = nil
        Task {
            if await state.perform(store, work) != nil {
                done = words
            } else {
                await state.loadGoals(store)
            }
            busy = false
        }
    }
}
