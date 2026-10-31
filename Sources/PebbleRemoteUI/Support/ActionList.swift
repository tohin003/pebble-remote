import PebbleDesign
import SwiftUI

/// A list of things Pebble keeps on the Mac, each with its one action (as a button and a swipe), confirmed first when
/// it can't be undone. Loads when shown and on pull to refresh; shows `empty` when there is nothing.
struct ActionList<Empty: View>: View {
    let title: String
    let items: [ActionItem]
    var footer: String? = nil
    /// Reads the list again from the Mac.
    let load: () async -> Void
    /// Does the item's action; returns whether the Mac took it.
    let perform: (ActionItem) async -> Bool
    @ViewBuilder let empty: Empty
    @State private var working: String?
    @State private var confirming: ActionItem?
    @State private var isConfirming = false

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    ActionRow(item: item, isWorking: working == item.id) { request(item) }
                        .swipeActions(edge: .trailing) {
                            Button(item.actionTitle, systemImage: item.actionSymbol ?? "ellipsis.circle",
                                   role: item.isDestructive ? .destructive : nil) { request(item) }
                        }
                }
            } footer: {
                if let footer {
                    Text(footer)
                }
            }
        }
        .overlay {
            if items.isEmpty {
                empty
            }
        }
        .confirmationDialog(
            confirming?.confirmation ?? "", isPresented: $isConfirming, titleVisibility: .visible,
            presenting: confirming
        ) { item in
            Button(item.actionTitle, role: item.isDestructive ? .destructive : nil) { act(item) }
        }
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
    }

    private func request(_ item: ActionItem) {
        guard working == nil else { return }
        if item.confirmation != nil {
            confirming = item
            isConfirming = true
        } else {
            act(item)
        }
    }

    private func act(_ item: ActionItem) {
        working = item.id
        Task {
            if await perform(item) { await load() }
            working = nil
        }
    }
}
