import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Details › Context: how full the task's model window is, as Pebble counts it ("62% of context used", the Mac's ring),
/// what fills it, and "Compact…" with Pebble's own confirmation (inventory item 10). Read when the tab shows and on
/// pull to refresh, never on a timer (the Mac records each read from the phone).
struct ContextTab: View {
    let state: DetailsState
    @Environment(RemoteStore.self) private var store
    @State private var isConfirming = false
    @State private var isCompacting = false
    @State private var outcome: String?

    var body: some View {
        List {
            if !store.readsQuietly {
                Section { UnlockStatusRow() }
            }
            if let use = state.context {
                usage(use)
                if use.basis != "none", !use.categories.isEmpty {
                    Section(AppCopy.Details.byCategory) {
                        ForEach(use.categories.filter { $0.tokens > 0 }) { category in
                            LabeledContent(
                                AppCopy.Details.contextCategory(category.id), value: AppCopy.Details.grouped(category.tokens))
                        }
                    }
                }
                compactSection(use)
            } else if let problem = state.contextProblem {
                Section {
                    Label(problem, systemImage: PebbleSymbol.status(.error))
                        .foregroundStyle(PebbleColor.danger)
                }
            }
        }
        .overlay {
            if state.context == nil, state.contextProblem == nil, store.readsQuietly {
                ProgressView()
            }
        }
        .confirmationDialog(AppCopy.Details.compactTitle, isPresented: $isConfirming, titleVisibility: .visible) {
            Button(AppCopy.Details.compactNow, action: compact)
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppCopy.Details.compactMessage)
        }
        .sensoryFeedback(.success, trigger: outcome) { _, new in new != nil }
        .task(id: store.readsQuietly) {
            if store.readsQuietly { await state.loadContext(store) }
        }
        .refreshable {
            if store.readsQuietly { await state.loadContext(store) }
        }
    }

    private func usage(_ use: ContextUse) -> some View {
        Section {
            if let percent = use.percent {
                VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                    Text(AppCopy.Details.contextUsed(percent))
                        .font(PebbleFont.title)
                    ProgressView(value: min(1, Double(percent) / 100))
                        .tint(percent >= 90 ? PebbleColor.danger : PebbleColor.accent)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
            if use.basis != "none", let used = use.used {
                Text(AppCopy.Details.contextSummary(used: used, window: use.window, free: use.free, over: use.over))
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            Text(AppCopy.Details.contextBasis(use.basis, live: use.isLive))
                .font(PebbleFont.cardBody)
        } header: {
            Text(AppCopy.Details.contextUse)
        } footer: {
            Text(AppCopy.Details.contextNote)
        }
    }

    private func compactSection(_ use: ContextUse) -> some View {
        Section {
            Button(AppCopy.Details.compact) { isConfirming = true }
                .disabled(!use.canCompact || isCompacting || !store.bridgeOffers("context_compact"))
            if isCompacting {
                Label {
                    Text(AppCopy.Details.compacting)
                } icon: {
                    ProgressView()
                }
                .foregroundStyle(.secondary)
            } else if let outcome {
                Text(outcome)
                    .font(PebbleFont.cardBody)
            } else if !use.canCompact {
                Text(AppCopy.Details.compactUnavailable(use.compactReason))
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func compact() {
        guard !isCompacting else { return }
        isCompacting = true
        outcome = nil
        Task {
            if let result = await state.perform(store, { try await store.compactContext(in: state.chatID) }) {
                outcome = AppCopy.Details.compacted(
                    status: result.status, messages: result.archivedMessages, toolResults: result.archivedToolResults,
                    freed: result.freedTokens)
                state.show(context: result.context)
            }
            isCompacting = false
        }
    }
}
