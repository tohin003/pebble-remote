import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's Recently Deleted conversations (Pebble deletes them for good after 30 days): Restore puts one back; Delete
/// for Good removes it from the Mac now, after a confirmation and Face ID (the store's elevated call).
struct RecentlyDeletedList: View {
    @Environment(RemoteStore.self) private var store
    @State private var working: ChatID?
    @State private var purging: TrashedChat?
    @State private var isConfirming = false

    var body: some View {
        List {
            ForEach(store.trashed) { chat in
                HStack {
                    VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                        Text(chat.title.isEmpty ? AppCopy.Chats.untitled : chat.title)
                            .font(.headline)
                        if let deleteAfter = chat.deleteAfter {
                            Text(AppCopy.Deleted.deletesOn(deleteAfter.formatted(date: .abbreviated, time: .omitted)))
                                .font(PebbleFont.meta)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if working == chat.id {
                        ProgressView()
                    } else {
                        Button(AppCopy.Deleted.restore, systemImage: "arrow.uturn.backward") { restore(chat) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .frame(minWidth: PebbleSize.minTap, minHeight: PebbleSize.minTap)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button(AppCopy.Deleted.restore, systemImage: "arrow.uturn.backward") { restore(chat) }
                        .tint(PebbleColor.accent)
                }
                .swipeActions(edge: .trailing) {
                    if store.bridgeOffers("storage_purge_chat") {
                        // Red, as a destructive action; the app's sage tint would otherwise colour it (U-18).
                        Button(AppCopy.Deleted.deleteForGood, systemImage: "trash", role: .destructive) {
                            confirmPurge(chat)
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .overlay {
            if store.trashed.isEmpty {
                ContentUnavailableView(AppCopy.Deleted.emptyTitle, systemImage: "trash")
            }
        }
        .confirmationDialog(
            AppCopy.Deleted.confirmTitle, isPresented: $isConfirming, titleVisibility: .visible, presenting: purging
        ) { chat in
            Button(AppCopy.Deleted.deleteForGood, role: .destructive) { purge(chat) }
        } message: { _ in
            Text(AppCopy.Deleted.confirmMessage)
        }
        .navigationTitle(AppCopy.Deleted.title)
        .task { await store.load(.trash) }
        .refreshable { await store.load(.trash) }
    }

    private func confirmPurge(_ chat: TrashedChat) {
        purging = chat
        isConfirming = true
    }

    private func restore(_ chat: TrashedChat) {
        run(chat) { try await store.restore(chat) }
    }

    private func purge(_ chat: TrashedChat) {
        run(chat) { try await store.purge(chat) }
    }

    private func run(_ chat: TrashedChat, _ work: @escaping () async throws -> Void) {
        guard working == nil else { return }
        working = chat.id
        Task {
            await store.attempt(work)
            working = nil
        }
    }
}
