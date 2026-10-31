import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Settings › Memory › Learning Candidates: what Pebble's learning holds back and why, as the Mac lists it under each
/// layer (AdvancedSettings.vue), here in one list by layer. A candidate that disagrees with a saved memory offers "Use
/// This Value" and "Keep Current", which act at once, as Pebble's buttons do. "Check Waiting Memories Now" runs
/// Pebble's memory upkeep. Everything waits while a task runs (Pebble refuses then), and Use This Value and the check
/// also while memory or the layer is off, as on the Mac. The words are Pebble's data and show literally.
struct MemoryCandidatesView: View {
    /// Shared with Settings › Memory, whose row counts them.
    @Binding var candidates: [MemoryCandidate]?
    @Environment(RemoteStore.self) private var store
    @State private var deciding: String?
    @State private var isChecking = false

    var body: some View {
        List {
            if let candidates, candidates.isEmpty {
                Text(AppCopy.Learning.noneWaiting)
                    .foregroundStyle(.secondary)
            }
            ForEach(layers, id: \.self) { layer in
                Section(layerName(layer)) {
                    ForEach(rows(in: layer)) { candidate in
                        CandidateRow(
                            candidate: candidate, canUseValue: canUseValue(candidate), canKeepCurrent: canDecide,
                            isDeciding: deciding == candidate.id
                        ) { useValue in
                            decide(candidate, useValue: useValue)
                        }
                    }
                }
            }
            if store.bridgeOffers("memory_maintain") {
                Section {
                    Button(action: check) {
                        HStack {
                            Text(AppCopy.Learning.checkNow)
                            if isChecking {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .contentShape(.rect)
                    }
                    .disabled(!canCheck)
                } footer: {
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                        Text(AppCopy.Learning.note)
                        if store.isPebbleWorking {
                            Text(AppCopy.Learning.idleOnly)
                        }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationTitle(AppCopy.Learning.title)
    }

    /// The layers that hold a candidate, in Pebble's order, then any a newer Pebble adds.
    private var layers: [String] {
        let held = Set((candidates ?? []).map(\.kind))
        let known = RemoteStore.memoryLayerNames.filter(held.contains)
        return known + held.subtracting(known).sorted()
    }

    private func rows(in layer: String) -> [MemoryCandidate] { (candidates ?? []).filter { $0.kind == layer } }

    private func layerName(_ id: String) -> String {
        store.memoryLayers.first { $0.id == id }?.name ?? AppCopy.PebbleSettings.layer(id)
    }

    private var memoryOn: Bool { store.settings?.memoryEnabled ?? true }

    /// Keep Current: Pebble refuses while a task runs, and one decision goes at a time.
    private var canDecide: Bool {
        store.bridgeOffers("memory_resolve") && !store.isPebbleWorking && deciding == nil
    }

    /// Use This Value also waits while memory or the candidate's layer is off.
    private func canUseValue(_ candidate: MemoryCandidate) -> Bool {
        canDecide && memoryOn && store.settings?.memoryLayers[candidate.kind] != false
    }

    private var canCheck: Bool { !store.isPebbleWorking && memoryOn && !isChecking }

    private func load() async {
        guard store.bridgeOffers("memory_candidates") else { return }
        if let read = await store.attempt({ try await store.memoryCandidates() }) {
            candidates = read
        }
    }

    private func decide(_ candidate: MemoryCandidate, useValue: Bool) {
        guard deciding == nil else { return }
        deciding = candidate.id
        Task {
            if await store.attempt({ try await store.decide(candidate, useValue: useValue) }) {
                await load()
            }
            deciding = nil
        }
    }

    private func check() {
        guard canCheck else { return }
        isChecking = true
        Task {
            if await store.attempt({ try await store.checkWaitingMemories() }) {
                await load()
            }
            isChecking = false
        }
    }
}

/// One candidate: why it waits, its words, whose it is; for one that disagrees, Pebble's two choices.
private struct CandidateRow: View {
    let candidate: MemoryCandidate
    let canUseValue: Bool
    let canKeepCurrent: Bool
    let isDeciding: Bool
    let decide: (Bool) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(AppCopy.Learning.line(status: candidate.status, reason: candidate.reason))
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                Text(verbatim: candidate.content.isEmpty ? AppCopy.Learning.testRecipe : candidate.content)
                    .font(PebbleFont.message)
                    .foregroundStyle(PebbleColor.text)
                Text(AppCopy.Memories.scopeName(candidate.scope))
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if candidate.disagrees {
                if isDeciding {
                    ProgressView()
                } else {
                    // Side by side where they fit; one above the other at accessibility text sizes.
                    let layout =
                        typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: PebbleSpace.s1))
                        : AnyLayout(HStackLayout(spacing: PebbleSpace.s4))
                    layout {
                        Button {
                            decide(true)
                        } label: {
                            Text(AppCopy.Learning.useValue)
                                .tapTarget(alignment: .leading)
                        }
                        .disabled(!canUseValue)
                        Button {
                            decide(false)
                        } label: {
                            Text(AppCopy.Learning.keepCurrent)
                                .tapTarget(alignment: .leading)
                        }
                        .disabled(!canKeepCurrent)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, PebbleSpace.s1)
    }
}
