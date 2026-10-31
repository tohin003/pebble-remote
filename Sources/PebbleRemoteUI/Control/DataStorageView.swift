import Accessibility
import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Settings › Data & storage › Manage Data: what the phone can do of Pebble's Data & storage page
/// (StorageSettings.vue). "Recent changes from your files" (a disclosure, as on the Mac) and Update Copies Now; then
/// the Mac's two Delete all buttons from its Recently deleted block, each asked first in the Mac's words ("Keep" is the
/// safe answer), then Face ID. What each did is said under it, and to VoiceOver. Pebble's folders, sizes, copies switch
/// and sign-in copies stay on the Mac: one "On your Mac" row.
struct DataStorageView: View {
    @Environment(RemoteStore.self) private var store
    @State private var overview: StorageOverview?
    @State private var working: Work?
    /// What the last action did (Pebble's words).
    @State private var copiesDone: String?
    @State private var deletionDone: String?
    @State private var isConfirmingTrashAll = false
    @State private var isConfirmingPurgeAll = false

    enum Work { case copies, trashAll, purgeAll }

    var body: some View {
        Form {
            if let overview, overview.checking > 0 {
                Section {
                    Text(AppCopy.DataStorage.checking(overview.checking))
                }
            }
            if let changes = overview?.changes, !changes.isEmpty {
                Section {
                    DisclosureGroup(AppCopy.DataStorage.recentChanges) {
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                            Text(verbatim: change)
                        }
                    }
                }
            }
            if store.bridgeOffers("storage_refresh") {
                Section {
                    actionButton(AppCopy.DataStorage.updateCopies, work: .copies, role: nil) { updateCopies() }
                    if let copiesDone {
                        Text(copiesDone)
                    }
                }
            }
            deleteAllSection
            Section {
                OnYourMacRow(title: AppCopy.DataStorage.onYourMac)
            } footer: {
                Text(AppCopy.DataStorage.onYourMacNote)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .navigationTitle(AppCopy.DataStorage.title)
    }

    /// The Mac's Recently deleted block: Delete All Now only while it holds conversations, then Delete All
    /// Conversations.
    @ViewBuilder
    private var deleteAllSection: some View {
        let waiting = overview?.recentlyDeleted.count ?? store.trashed.count
        if store.bridgeOffers("storage_purge_all") || store.bridgeOffers("storage_trash_all") {
            Section {
                if store.bridgeOffers("storage_purge_all"), waiting > 0 {
                    actionButton(AppCopy.DataStorage.deleteAllNow, work: .purgeAll, role: .destructive) {
                        isConfirmingPurgeAll = true
                    }
                    .confirmationDialog(
                        AppCopy.DataStorage.purgeAllQuestion(waiting), isPresented: $isConfirmingPurgeAll,
                        titleVisibility: .visible
                    ) {
                        Button(AppCopy.DataStorage.purgeAllButton, role: .destructive) { purgeAll() }
                        Button(AppCopy.DataStorage.keep, role: .cancel) {}
                    } message: {
                        Text(AppCopy.DataStorage.purgeAllNote)
                    }
                }
                if store.bridgeOffers("storage_trash_all") {
                    actionButton(AppCopy.DataStorage.deleteAllConversations, work: .trashAll, role: .destructive) {
                        isConfirmingTrashAll = true
                    }
                    .confirmationDialog(
                        AppCopy.DataStorage.trashAllQuestion, isPresented: $isConfirmingTrashAll,
                        titleVisibility: .visible
                    ) {
                        Button(AppCopy.DataStorage.trashAllButton, role: .destructive) { trashAll() }
                        Button(AppCopy.DataStorage.keep, role: .cancel) {}
                    } message: {
                        Text(AppCopy.DataStorage.trashAllNote)
                    }
                }
                if let deletionDone {
                    Text(deletionDone)
                }
            } header: {
                Text(AppCopy.DataStorage.recentlyDeleted)
            }
        }
    }

    /// A row's button with Pebble's words, a spinner while its call runs, and every button waiting while one does.
    private func actionButton(
        _ title: String, work: Work, role: ButtonRole?, action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                if working == work {
                    Spacer()
                    ProgressView()
                }
            }
            .contentShape(.rect)
        }
        .disabled(working != nil)
        .accessibilityHint(work == .copies ? "" : AppCopy.FaceID.asksFirst)
    }

    private func load() async {
        guard store.bridgeOffers("storage_summary") else { return }
        if let read = await store.attempt({ try await store.storageOverview() }) {
            overview = read
        }
    }

    private func run(_ work: Work, _ operation: @escaping () async -> Void) {
        guard working == nil else { return }
        working = work
        Task {
            await operation()
            working = nil
        }
    }

    private func say(_ words: String) {
        AccessibilityNotification.Announcement(words).post()
    }

    private func updateCopies() {
        run(.copies) {
            if let read = await store.attempt({ try await store.updateCopies() }) {
                overview = read
                copiesDone = AppCopy.DataStorage.upToDate
                say(AppCopy.DataStorage.upToDate)
            }
        }
    }

    private func trashAll() {
        run(.trashAll) {
            if let done = await store.attempt({ try await store.moveAllToRecentlyDeleted() }) {
                let words = AppCopy.DataStorage.moved(done.count, kept: done.kept)
                deletionDone = words
                say(words)
                await load()
            }
        }
    }

    private func purgeAll() {
        run(.purgeAll) {
            if let done = await store.attempt({ try await store.deleteAllForGood() }) {
                let words = AppCopy.DataStorage.purged(done.count)
                deletionDone = words
                say(words)
                await load()
            }
        }
    }
}
