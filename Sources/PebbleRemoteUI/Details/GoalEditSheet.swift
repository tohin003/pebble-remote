import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// What the goal's edit sheet does (GoalPanel.vue's criterion Edit, Add step, Block step; and the step edit Pebble's
/// window has no button for, `goal_step_edit`).
enum GoalEdit: Identifiable, Hashable {
    case criterion(GoalCriterion)
    case addStep
    case step(GoalRecord.Step)
    case block(GoalRecord.Step)

    var id: String {
        switch self {
        case .criterion(let criterion): "criterion/\(criterion.id)"
        case .addStep: "add-step"
        case .step(let step): "step/\(step.id)"
        case .block(let step): "block/\(step.id)"
        }
    }
}

/// One edit of the goal, in a sheet: the words (one line each, at most what Pebble keeps), the steps a step comes
/// after, then Save. Pebble's refusal (a stale revision, a loop between steps) stays in the sheet, and the goal is read
/// again so the next Save names the revision Pebble has. The keyboard closes with Return, a scroll or Cancel.
struct GoalEditSheet: View {
    let edit: GoalEdit
    let state: DetailsState
    /// Pebble's words for what changed, once it did.
    let done: (String) -> Void
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var text: String
    @State private var after: Set<String>
    @State private var isSaving = false
    @State private var failure: String?
    @FocusState private var isWriting: Bool

    init(edit: GoalEdit, state: DetailsState, done: @escaping (String) -> Void) {
        self.edit = edit
        self.state = state
        self.done = done
        switch edit {
        case .criterion(let criterion):
            _text = State(initialValue: criterion.text)
            _after = State(initialValue: [])
        case .step(let step):
            _text = State(initialValue: step.title)
            _after = State(initialValue: Set(step.after))
        case .addStep, .block:
            _text = State(initialValue: "")
            _after = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if case .block(let step) = edit {
                    Section {
                        LabeledContent(AppCopy.Goals.blockStep, value: AppCopy.Goals.stepChoice(step.id, step.title))
                    }
                }
                Section {
                    TextField(fieldTitle, text: $text, prompt: placeholder.map { Text($0) })
                        .focused($isWriting)
                        .submitLabel(.done)
                        .onSubmit { isWriting = false }
                } header: {
                    Text(fieldTitle)
                } footer: {
                    if text.count >= limit {
                        Text(AppCopy.Goals.atLimit(limit))
                    } else if case .criterion = edit {
                        Text(AppCopy.Goals.checkClears)
                    }
                }
                if showsAfter {
                    afterSection
                }
                if failure != nil {
                    Section { SheetFailure(message: failure) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel) { dismiss() }
                        .pebbleBarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle, action: save)
                        .disabled(!canSave)
                }
            }
            .onChange(of: text) { _, typed in
                // Pebble keeps one line of at most `limit` characters; the Mac's field stops there too.
                let line = typed.replacingOccurrences(of: "\n", with: " ")
                let kept = line.count > limit ? String(line.prefix(limit)) : line
                if kept != typed { text = kept }
            }
        }
        .formSheetDetents(typeSize)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: The steps it comes after

    private var showsAfter: Bool {
        switch edit {
        case .addStep, .step: !candidates.isEmpty
        case .criterion, .block: false
        }
    }

    private var candidates: [GoalRecord.Step] {
        let current: GoalRecord.Step? = if case .step(let step) = edit { step } else { nil }
        return (state.goal?.possibleAfter(for: current) ?? [])
    }

    private var afterSection: some View {
        Section(AppCopy.Goals.after) {
            ForEach(candidates) { step in
                let chosen = after.contains(step.id)
                Button {
                    if chosen { after.remove(step.id) } else { after.insert(step.id) }
                } label: {
                    HStack {
                        Text(verbatim: AppCopy.Goals.stepChoice(step.id, step.title))
                            .foregroundStyle(PebbleColor.text)
                        Spacer(minLength: PebbleSpace.s2)
                        if chosen {
                            Image(systemName: "checkmark")
                                .foregroundStyle(PebbleColor.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .disabled(!chosen && after.count >= GoalLimits.after)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    // MARK: Words

    private var title: String {
        switch edit {
        case .criterion(let criterion): AppCopy.Goals.editCriterion(criterion.id)
        case .addStep: AppCopy.Goals.addStep
        case .step(let step): AppCopy.Goals.editStepNamed(step.id)
        case .block: AppCopy.Goals.blockStep
        }
    }

    private var fieldTitle: String {
        switch edit {
        case .criterion: AppCopy.Goals.criterion
        case .addStep, .step: AppCopy.Goals.newStep
        case .block: AppCopy.Goals.reason
        }
    }

    private var placeholder: String? {
        switch edit {
        case .criterion: nil
        case .addStep, .step: AppCopy.Goals.stepPlaceholder
        case .block: AppCopy.Goals.reasonPlaceholder
        }
    }

    private var saveTitle: String {
        switch edit {
        case .addStep: AppCopy.Goals.addStep
        case .block: AppCopy.Goals.blockStep
        case .criterion, .step: AppCopy.Goals.save
        }
    }

    private var limit: Int {
        switch edit {
        case .criterion: GoalLimits.criterion
        case .addStep, .step: GoalLimits.stepTitle
        case .block: GoalLimits.blockReason
        }
    }

    // MARK: Saving

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard !isSaving, !trimmed.isEmpty else { return false }
        switch edit {
        case .criterion(let criterion): return trimmed != criterion.text
        case .step(let step): return trimmed != step.title || after != Set(step.after)
        case .addStep, .block: return true
        }
    }

    private func save() {
        guard canSave, let goal = state.goal else { return }
        isWriting = false
        isSaving = true
        failure = nil
        let words = trimmed
        let chosen = goal.steps.map(\.id).filter(after.contains)
        Task {
            let changed: GoalRecord? = await store.attempt {
                switch edit {
                case .criterion(let criterion):
                    return try await store.editCriterion(criterion, to: words, of: goal)
                case .addStep:
                    return try await store.addStep(words, after: chosen, to: goal)
                case .step(let step):
                    return try await store.editStep(
                        step, title: words == step.title ? nil : words,
                        after: Set(chosen) == Set(step.after) ? nil : chosen,
                        of: goal)
                case .block(let step):
                    return try await store.blockStep(step, reason: words, of: goal)
                }
            }
            if let changed {
                state.show(goal: changed)
                done(notice)
                dismiss()
            } else {
                failure = store.takeNotice()
                await state.loadGoals(store)  // a refusal may be a newer revision: the next Save names Pebble's
            }
            isSaving = false
        }
    }

    /// Pebble's notice for the change (GoalPanel.vue).
    private var notice: String {
        switch edit {
        case .criterion(let criterion): AppCopy.Goals.criterionUpdated(criterion.id)
        case .addStep: AppCopy.Goals.stepAdded
        case .step(let step): AppCopy.Goals.stepUpdated(step.id)
        case .block(let step): AppCopy.Goals.stepBlocked(step.id)
        }
    }
}
