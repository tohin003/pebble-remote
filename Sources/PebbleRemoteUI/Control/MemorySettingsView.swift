import Accessibility
import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's memory, as its Settings › Memory has it (AdvancedSettings.vue, MemoryContests.vue): "Remember useful
/// context"; the six layers, each with how many memories it holds, opening what Pebble remembers there with the layer's
/// switch (`MemoryLayerView`), as the Mac's layer tabs do; then the contested memories as decisions, in Pebble's words.
/// They wait only here: Pebble doesn't count them among what waits for the person, so Reviews doesn't list them.
/// Lane S: the learning candidates (one row, counted, opening `MemoryCandidatesView`) and, last, "Forget All Memories",
/// asked first in the Mac's words, then Face ID; it waits while a task runs, as Pebble's button does.
struct MemorySettingsView: View {
    let settings: PebbleSettings
    @Environment(RemoteStore.self) private var store
    /// Pebble's contested memories, once read (nil before).
    @State private var contests: [ContestedMemory]?
    /// What the last decision did, in Pebble's words ("Kept this memory. 1 memory was forgotten.").
    @State private var outcome: String?
    /// The decision waiting for the person's confirmation.
    @State private var pending: PendingDecision?
    @State private var isConfirming = false
    @State private var isDeciding = false
    /// Pebble's learning candidates, once read (nil before).
    @State private var candidates: [MemoryCandidate]?
    @State private var isConfirmingForgetAll = false
    @State private var isForgettingAll = false
    /// Said once Forget all is done (Pebble's words).
    @State private var forgotAll: String?

    var body: some View {
        Form {
            Section {
                RemoteToggle(
                    AppCopy.PebbleSettings.rememberContext,
                    subtitle: AppCopy.PebbleSettings.rememberContextDetail, value: settings.memoryEnabled,
                    faceID: store.faceIDRule(forSetting: "memory_enabled")
                ) { on in
                    await store.attempt { try await store.setMemoryEnabled(on) }
                }
            }
            if !store.memoryLayers.isEmpty {
                Section {
                    ForEach(store.memoryLayers) { layer in
                        NavigationLink {
                            MemoryLayerView(layerID: layer.id)
                        } label: {
                            LabeledContent(
                                layer.name, value: AppCopy.Memories.layerValue(count: layer.count, isOn: layer.isOn))
                        }
                    }
                } header: {
                    Text(AppCopy.Memories.layers)
                } footer: {
                    Text(AppCopy.PebbleSettings.memoryNote)
                }
            }
            if store.bridgeOffers("memory_candidates") {
                Section {
                    NavigationLink {
                        MemoryCandidatesView(candidates: $candidates)
                    } label: {
                        LabeledContent(AppCopy.Learning.title, value: candidatesCount)
                    }
                } footer: {
                    Text(AppCopy.Learning.note)
                }
            }
            if store.bridgeOffers("memory_contests"), let contests {
                Section {
                    if let outcome {
                        Text(outcome)
                    }
                    if contests.isEmpty {
                        Text(AppCopy.Memories.noneContested)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(AppCopy.Memories.contested)
                } footer: {
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                        Text(AppCopy.Memories.contestNote)
                        if store.isPebbleWorking {
                            Text(AppCopy.Memories.decideLater)
                        }
                    }
                }
                ForEach(contests) { contest in
                    ContestSection(contest: contest, canDecide: canDecide, ask: ask)
                }
            }
            if store.bridgeOffers("memory_clear") {
                forgetAllSection
            }
        }
        .confirmationDialog(
            pending.map { AppCopy.Memories.question($0.decision.rawValue) } ?? "", isPresented: $isConfirming,
            titleVisibility: .visible, presenting: pending
        ) { pending in
            Button(pending.confirmLabel, role: pending.forgets ? .destructive : nil) { decide(pending) }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: { pending in
            Text(pending.confirmation)
        }
        .task {
            await loadContests()
            await loadCandidates()
        }
        .refreshable {
            await loadContests()
            await loadCandidates()
        }
        .navigationTitle(AppCopy.PebbleSettings.memory)
    }

    /// "Forget All Memories", last and in red: asked first in the Mac's words ("Keep Them" is the safe answer), then
    /// Face ID. What it did is said under it, and to VoiceOver.
    private var forgetAllSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingForgetAll = true
            } label: {
                HStack {
                    Text(AppCopy.Learning.forgetAll)
                    if isForgettingAll {
                        Spacer()
                        ProgressView()
                    }
                }
                .contentShape(.rect)
            }
            .disabled(store.isPebbleWorking || isForgettingAll)
            .accessibilityHint(AppCopy.FaceID.asksFirst)
            .confirmationDialog(
                AppCopy.Learning.forgetAllQuestion, isPresented: $isConfirmingForgetAll, titleVisibility: .visible
            ) {
                Button(AppCopy.Learning.forgetPermanently, role: .destructive) { forgetAll() }
                Button(AppCopy.Learning.keepThem, role: .cancel) {}
            } message: {
                Text(AppCopy.Learning.forgetAllNote)
            }
            if let forgotAll {
                Text(forgotAll)
            }
        } footer: {
            if store.isPebbleWorking {
                Text(AppCopy.Learning.idleOnly)
            }
        }
    }

    /// The Learning Candidates row's value: how many wait, once read.
    private var candidatesCount: String { candidates.map { AppCopy.Learning.count($0.count) } ?? "" }

    private func loadCandidates() async {
        guard store.bridgeOffers("memory_candidates") else { return }
        let earlier = store.notice
        if let read = try? await store.memoryCandidates() {
            candidates = read
        } else {
            store.notice = earlier  // the count stays as it was; the list itself says why when opened
        }
    }

    private func forgetAll() {
        guard !isForgettingAll else { return }
        isForgettingAll = true
        Task {
            if await store.attempt({ try await store.forgetAllMemories() }) {
                forgotAll = AppCopy.Learning.forgotAll
                AccessibilityNotification.Announcement(AppCopy.Learning.forgotAll).post()
                candidates = []
                await loadContests()
            }
            isForgettingAll = false
        }
    }

    /// Pebble refuses decisions while a task runs; the buttons wait, and the footer says so (Pebble's words).
    private var canDecide: Bool {
        store.bridgeOffers("memory_resolve_contest") && !store.isPebbleWorking && !isDeciding
    }

    private func loadContests() async {
        guard store.bridgeOffers("memory_contests") else { return }
        let earlier = store.notice
        if let read = try? await store.contestedMemories() {
            contests = read
        } else {
            store.notice = earlier  // a list that couldn't be read stays as it was; pull to read it again
        }
    }

    private func ask(_ contest: ContestedMemory, _ decision: ContestDecision) {
        pending = PendingDecision(contest: contest, decision: decision)
        isConfirming = true
    }

    private func decide(_ pending: PendingDecision) {
        isDeciding = true
        Task {
            let question = AppCopy.Memories.question(pending.decision.rawValue)
            let forgotten: Int?? = await store.attempt {
                try await store.resolve(pending.contest, pending.decision, question: question)
            }
            if case .some(let count) = forgotten {
                let said = AppCopy.Memories.outcome(pending.decision.rawValue, forgotten: count)
                outcome = said
                AccessibilityNotification.Announcement(said).post()
            }
            await loadContests()
            isDeciding = false
        }
    }
}

/// A decision on a contest, waiting for the person's confirmation: what it forgets, in Pebble's words.
struct PendingDecision: Identifiable {
    let contest: ContestedMemory
    let decision: ContestDecision
    var id: String { contest.id + "/" + decision.rawValue }

    /// It forgets something: its button has the destructive role.
    var forgets: Bool { !decision.forgets(in: contest).isEmpty }

    var confirmLabel: String {
        AppCopy.Memories.confirm(decision.rawValue, forgetting: decision.forgets(in: contest).count)
    }

    var confirmation: String {
        AppCopy.Memories.confirmation(
            decision.rawValue,
            summary: AppCopy.Memories.summary(kind: contest.record.kind, content: contest.record.content),
            forgets: decision.forgets(in: contest).map { (kind: $0.kind, content: $0.content) },
            counterparts: contest.counterparts.count)
    }
}
