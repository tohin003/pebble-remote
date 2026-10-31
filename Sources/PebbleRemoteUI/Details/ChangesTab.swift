import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Details › Changes: the files the latest settled task wrote, and Rewind (inventory item 6, RewindPanel.vue). Pebble
/// previews first (nothing changes), the person picks the step, reads each file's change and what is never undone,
/// then confirms in plain words and with Face ID; Pebble applies exactly the reviewed preview and reads every file back.
struct ChangesTab: View {
    let state: DetailsState
    let transcript: Transcript
    @Environment(RemoteStore.self) private var store
    @State private var step = 0
    @State private var isChecking = false
    @State private var isConfirming = false
    @State private var isRewinding = false
    @State private var result: RewindResult?

    var body: some View {
        let run = Self.settledRun(transcript)
        List {
            if !store.readsQuietly {
                Section { UnlockStatusRow() }
            }
            if let run {
                rewindSection(run)
                if let plan = state.rewind, plan.runID == run {
                    filesSection(plan)
                    effectsSection(plan)
                }
                if let result {
                    Section {
                        ForEach(result.files) { file in
                            Text(AppCopy.Details.rewindResult(path: file.path, status: file.status, detail: file.detail))
                                .font(PebbleFont.cardBody)
                        }
                    } header: {
                        Text(AppCopy.Details.restored(result.restored))
                    }
                }
            }
            Section {
                OnYourMacRow(title: AppCopy.Details.codingWorkflows)
            } footer: {
                Text(AppCopy.Details.onYourMacFootnote)
            }
        }
        .confirmationDialog(
            AppCopy.Details.rewindConfirmTitle(state.rewind?.restoring ?? 0), isPresented: $isConfirming,
            titleVisibility: .visible, presenting: state.rewind
        ) { plan in
            Button(AppCopy.Details.rewindButton(plan.restoring), role: .destructive) { apply(plan) }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: { plan in
            Text(AppCopy.Details.rewindConfirmMessage(step: plan.step))
        }
        .sensoryFeedback(.success, trigger: result) { _, new in new != nil }
        .task(id: [run ?? "", store.readsQuietly ? "quiet" : "locked"]) {
            guard let run, store.readsQuietly, state.rewind?.runID != run else { return }
            await preview(run, at: 0)
        }
        .refreshable {
            if let run, store.readsQuietly { await preview(run, at: step) }
        }
    }

    private func rewindSection(_ run: RunID) -> some View {
        Section {
            if let plan = state.rewind, plan.runID == run {
                Picker(AppCopy.Details.rewindTo, selection: $step) {
                    ForEach(plan.choices, id: \.self) { point in
                        Text(AppCopy.Details.rewindPoint(point)).tag(point)
                    }
                }
                .onChange(of: step) { _, new in
                    if new != plan.step { Task { await preview(run, at: new) } }
                }
                if plan.undoesLastRewind {
                    Text(AppCopy.Details.undoesLastRewind)
                        .font(PebbleFont.cardBody)
                }
                Text(
                    isChecking
                        ? AppCopy.Details.rewindChecking
                        : plan.restoring > 0 ? AppCopy.Details.rewindReview : AppCopy.Details.rewindNothing
                )
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
                if store.bridgeOffers("rewind_apply") {
                    Button(AppCopy.Details.rewindButton(plan.restoring), role: .destructive) { isConfirming = true }
                        .disabled(plan.restoring == 0 || isChecking || isRewinding)
                } else {
                    OnYourMacRow(title: AppCopy.Details.rewindButton(plan.restoring))
                }
                if isRewinding {
                    Label {
                        Text(AppCopy.Details.rewinding)
                    } icon: {
                        ProgressView()
                    }
                    .foregroundStyle(.secondary)
                }
                if let undo = plan.lastRewindUndoStep {
                    Button(AppCopy.Details.reviewUndoRewind) { reviewStep(undo, run: run) }
                        .disabled(isChecking || isRewinding)
                }
                Button(AppCopy.Details.reviewAgain) { reviewStep(step, run: run) }
                    .disabled(isChecking || isRewinding)
            } else if let problem = state.rewindProblem {
                Label(problem, systemImage: PebbleSymbol.status(.error))
                    .foregroundStyle(PebbleColor.danger)
            } else if store.readsQuietly {
                Label {
                    Text(AppCopy.Details.rewindChecking)
                } icon: {
                    ProgressView()
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text(AppCopy.Details.filesFromLatestTask)
        } footer: {
            Text(AppCopy.Details.rewindIntro)
        }
    }

    private func filesSection(_ plan: RewindPlan) -> some View {
        Section(AppCopy.Details.files) {
            if plan.files.isEmpty {
                Text(AppCopy.Details.noFiles)
                    .foregroundStyle(.secondary)
            }
            ForEach(plan.files) { file in
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Text(verbatim: file.path)
                        .font(PebbleFont.cardDetail)
                        .textSelection(.enabled)
                    Text(
                        [AppCopy.Details.fileStatus(file.status), AppCopy.Details.undoesSteps(file.steps)]
                            .compactMap { $0 }.joined(separator: " \u{00B7} ")
                    )
                    .font(PebbleFont.meta)
                    .foregroundStyle(file.status == "revert" ? AnyShapeStyle(PebbleColor.accent) : AnyShapeStyle(.secondary))
                    if let detail = file.detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(PebbleFont.cardBody)
                    }
                    if let diff = file.diff, !diff.isEmpty {
                        DisclosureGroup(AppCopy.Details.showChange) {
                            Text(verbatim: diff)
                                .font(PebbleFont.cardDetail)
                                .textSelection(.enabled)
                            if file.diffCut {
                                Text(AppCopy.Details.diffCut)
                                    .font(PebbleFont.meta)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func effectsSection(_ plan: RewindPlan) -> some View {
        Section(AppCopy.Details.notReverted) {
            if plan.effects.isEmpty {
                Text(AppCopy.Details.noEffects)
                    .foregroundStyle(.secondary)
            }
            ForEach(plan.effects) { effect in
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Text(verbatim: effect.label)
                        .font(PebbleFont.cardBody)
                    Text(
                        [AppCopy.Details.effectKind(effect.kind), AppCopy.Details.effectStep(effect.step), effect.outcome]
                            .compactMap { $0 }.joined(separator: " \u{00B7} ")
                    )
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                    if let note = effect.note, !note.isEmpty {
                        Text(verbatim: note)
                            .font(PebbleFont.meta)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if plan.effectsOmitted > 0 {
                Text(AppCopy.Details.moreEffects(plan.effectsOmitted))
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The conversation's newest task that isn't working (RunPanel.vue `settled`): the one a rewind can put back.
    static func settledRun(_ transcript: Transcript) -> RunID? {
        if let live = transcript.run, DetailsState.liveStates.contains(live.state.rawValue) {
            for item in transcript.items.reversed() {
                if case .runEnd(_, let runID, _, _, _) = item, runID != live.id { return runID }
            }
            return nil
        }
        return DetailsOpening.run(for: transcript)
    }

    private func reviewStep(_ point: Int, run: RunID) {
        Task { await preview(run, at: point) }
    }

    private func preview(_ run: RunID, at point: Int) async {
        isChecking = true
        await state.loadRewind(store, run: run, step: point)
        if let plan = state.rewind { step = plan.step }
        isChecking = false
    }

    private func apply(_ plan: RewindPlan) {
        guard !isRewinding else { return }
        isRewinding = true
        result = nil
        Task {
            if let done = await state.perform(store, { try await store.rewind(plan) }) {
                result = done
                await preview(plan.runID, at: plan.step)
            }
            isRewinding = false
        }
    }
}
