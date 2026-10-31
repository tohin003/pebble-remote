import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's Toolbox: tools Pebble asks the person about (Keep or Don't Keep), the tools it keeps (Remove, confirmed),
/// and tools removed in the last ten minutes (Put Back).
struct ToolboxView: View {
    @Environment(RemoteStore.self) private var store
    @State private var removing: ToolboxEntry?
    @State private var isConfirming = false

    var body: some View {
        List {
            if !store.toolboxDecisions.isEmpty {
                Section(AppCopy.Toolbox.asks) {
                    ForEach(store.toolboxDecisions) { decision in
                        ToolDecisionRow(decision: decision)
                    }
                }
            }
            Section {
                ForEach(store.toolbox) { tool in
                    VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                        Text(tool.name)
                            .font(.headline)
                        Text(tool.purpose)
                            .font(PebbleFont.meta)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        if store.bridgeOffers("toolbox_remove") {
                            Button(AppCopy.Control.remove, systemImage: "trash", role: .destructive) {
                                confirmRemoval(tool)
                            }
                        }
                    }
                }
            }
            if !store.removedTools.isEmpty {
                Section(AppCopy.Toolbox.removed) {
                    ForEach(store.removedTools) { tool in
                        HStack {
                            Text(tool.name)
                            Spacer()
                            Button {
                                putBack(tool)
                            } label: {
                                Text(AppCopy.Toolbox.putBack)
                                    .tapTarget()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .overlay {
            if store.toolbox.isEmpty && store.toolboxDecisions.isEmpty && store.removedTools.isEmpty {
                PebbleEmptyState(.noTools)
            }
        }
        .confirmationDialog(
            AppCopy.Toolbox.removeConfirm, isPresented: $isConfirming, titleVisibility: .visible,
            presenting: removing
        ) { tool in
            Button(AppCopy.Control.remove, role: .destructive) { remove(tool) }
        }
        .navigationTitle(AppCopy.Control.toolbox)
        .task { await store.load(.toolbox) }
        .refreshable { await store.load(.toolbox) }
    }

    private func confirmRemoval(_ tool: ToolboxEntry) {
        removing = tool
        isConfirming = true
    }

    private func remove(_ tool: ToolboxEntry) {
        Task { await store.attempt { try await store.removeTool(tool) } }
    }

    private func putBack(_ tool: RemovedTool) {
        Task { await store.attempt { try await store.putBack(tool) } }
    }
}
