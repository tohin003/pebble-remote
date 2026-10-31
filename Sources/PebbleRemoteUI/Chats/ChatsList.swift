import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The Chats tab as Pebble's sidebar, in the Mac's order and words: New conversation (the toolbar's button, ⌘N), Your
/// Space (Companion, the projects, Connect a project), then Recent Conversations, newest activity first. Search covers
/// the conversations, as the Mac's search box does: it filters them on the phone at once and adds Pebble's own matches
/// (titles and messages) a moment later. Swipe a conversation for Stop, Delete (to Recently Deleted) and Rename;
/// Recently Deleted is at the end of the list.
///
/// While the person touches or scrolls the list, Recent Conversations keep their order (`HeldOrder`), and Pebble's
/// newer activity re-sorts them a moment after the list comes to rest, so a row never moves under a finger.
///
/// Search's keyboard never stays stuck (the person, 2026-10-31; the 12:15 device run's photos 033-034 show it up after a
/// swipe): scrolling the list closes it at once, as in Mail's search, and so does a tap on the list; the search and its
/// words stay until its Close.
struct ChatsList: View {
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    /// Search's field has the keyboard.
    @FocusState private var isSearching: Bool
    @State private var found: [ChatSummary] = []
    @State private var renaming: ChatSummary?
    @State private var isRenaming = false
    @State private var newTitle = ""
    @State private var isConnecting = false
    /// The conversation a long press's Delete asks about.
    @State private var deleting: ChatSummary?
    @State private var isConfirmingDelete = false
    /// The conversations' order while the list is touched or scrolled; nil when it follows Pebble's.
    @State private var heldOrder: [ChatID]?
    @State private var release: Task<Void, Never>?

    var body: some View {
        @Bindable var router = router
        List {
            if query.isEmpty, canStart {
                YourSpaceSection(open: openNewConversation, connectProject: connectProject)
            }
            Section {
                ForEach(shown) { chat in
                    NavigationLink(value: ChatRoute(chatID: chat.id)) {
                        ChatRow(chat: chat)
                    }
                    .swipeActions(edge: .trailing) {
                        // Both remove something: the system's red, not the app's sage tint (U-18).
                        if chat.status?.isLive == true, store.bridgeOffers("cancel") {
                            Button(AppCopy.Conversation.stop, systemImage: "stop.fill", role: .destructive) {
                                stop(chat)
                            }
                            .tint(.red)
                        } else if store.bridgeOffers("storage_trash_chat") {
                            Button(AppCopy.Deleted.delete, systemImage: "trash", role: .destructive) {
                                trash(chat)
                            }
                            .tint(.red)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if store.bridgeOffers("chat_rename") {
                            Button(AppCopy.Chats.rename, systemImage: "pencil") {
                                startRenaming(chat)
                            }
                            .tint(.indigo)
                        }
                    }
                    // A long press (U-19): the same actions in the Mac's words, with the title and last line as the
                    // preview, never the transcript.
                    .contextMenu {
                        ChatContextMenu(items: menuItems(for: chat)) { item in act(item, on: chat) }
                    } preview: {
                        ChatPreview(chat: chat) { await store.lastLine(of: chat.id) }
                    }
                }
                if query.isEmpty, store.chats.isEmpty {
                    Text(AppCopy.Sidebar.noConversations)
                        .foregroundStyle(.secondary)
                }
            } header: {
                if query.isEmpty {
                    Text(AppCopy.Sidebar.recentConversations)
                }
            }
            if query.isEmpty, store.bridgeOffers("storage_trash_chat") {
                Section {
                    Button(AppCopy.Deleted.title, systemImage: "trash") { router.isShowingRecentlyDeleted = true }
                }
            }
        }
        .overlay {
            if !query.isEmpty {
                ChatsEmptyState(isSearching: true, isEmpty: shown.isEmpty)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .closesKeyboardOnTap($isSearching)
        .onScrollPhaseChange { _, phase in
            if phase == .idle {
                releaseOrder()
            } else {
                holdOrder()
            }
        }
        // While the run accessory shows, rows that scroll under it and the tab bar are hidden behind a solid edge
        // rather than showing through the glass, where they read garbled and look tappable (U-04).
        .scrollEdgeEffectStyle(router.showsRunAccessory(in: store) ? .hard : nil, for: .bottom)
        // Recently Deleted is a page of its own: the router knows it is there, so the accessory leaves it (U-04).
        .navigationDestination(isPresented: $router.isShowingRecentlyDeleted) {
            RecentlyDeletedList()
        }
        .searchable(text: $query, prompt: AppCopy.Chats.searchPrompt)
        .searchFocused($isSearching)
        .task(id: query) { await search() }
        .refreshable { await store.refresh() }
        .navigationTitle(AppCopy.Chats.title)
        .toolbar {
            if canStart {
                ToolbarItem(placement: .primaryAction) {
                    Button(AppCopy.Chats.newConversation, systemImage: PebbleSymbol.askPebble, action: openCompanion)
                        .keyboardShortcut("n")
                        .accessibilityHint(AppCopy.Sidebar.newConversationHint)
                }
            }
        }
        .alert(
            AppCopy.Chats.renameTitle, isPresented: $isRenaming, presenting: renaming
        ) { chat in
            TextField(AppCopy.Chats.renameField, text: $newTitle)
            Button(AppCopy.Chats.save) { rename(chat) }
            Button(AppCopy.Chats.cancel, role: .cancel) {}
        }
        .sheet(isPresented: $isConnecting) {
            ConnectProjectSheet(choose: connectChosen)
                .lockCover()
        }
        // Delete from a long press asks first, in the Mac's words (its delete dialog); the swipe stays as it was.
        .confirmationDialog(
            AppCopy.ChatMenu.deleteTitle(deleting?.title ?? ""), isPresented: $isConfirmingDelete,
            titleVisibility: .visible, presenting: deleting
        ) { chat in
            Button(AppCopy.ChatMenu.moveToRecentlyDeleted, role: .destructive) { trash(chat) }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: { chat in
            Text(AppCopy.ChatMenu.deleteMessage(chat.title.isEmpty ? AppCopy.Chats.untitled : chat.title))
        }
    }

    /// What a long press on this conversation offers now.
    private func menuItems(for chat: ChatSummary) -> [ChatMenuItem] {
        ChatMenuItem.items(for: chat, project: store.project(of: chat.id)) { store.bridgeOffers($0) }
    }

    private func act(_ item: ChatMenuItem, on chat: ChatSummary) {
        switch item {
        case .rename: startRenaming(chat)
        case .newConversation(let project): openNewConversation(in: project)
        case .stop: stop(chat)
        case .delete:
            deleting = chat
            isConfirmingDelete = true
        }
    }

    /// The bridge lets the phone start conversations.
    private var canStart: Bool { store.bridgeOffers("new_chat") }

    /// The store's chats (in the held order while the list is touched or scrolled), or those matching the search, then
    /// Pebble's further matches.
    private var shown: [ChatSummary] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return HeldOrder.apply(heldOrder, to: store.chats) }
        let local = store.chats.filter { chat in
            chat.title.localizedStandardContains(text) || (chat.project?.localizedStandardContains(text) ?? false)
        }
        let localIDs = Set(local.map(\.id))
        return local + found.filter { !localIDs.contains($0.id) }
    }

    /// Pebble's search, after the person pauses typing.
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, store.bridgeOffers("chat_search") else {
            found = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return  // the next keystroke started a new search
        }
        let earlier = store.notice
        do {
            found = try await store.search(text)
        } catch {
            // The local matches still show; a failed search while typing isn't worth an alert.
            store.notice = earlier
        }
    }

    /// A finger is on the list, or it scrolls: the rows keep their places.
    private func holdOrder() {
        release?.cancel()
        release = nil
        if heldOrder == nil { heldOrder = store.chats.map(\.id) }
    }

    /// The list came to rest: Pebble's order comes back a moment later, calmly.
    private func releaseOrder() {
        guard heldOrder != nil else { return }
        release?.cancel()
        release = Task {
            try? await Task.sleep(for: HeldOrder.release)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .default) { heldOrder = nil }
        }
    }

    /// "New conversation" (⌘N): Companion, as on the Mac.
    private func openCompanion() {
        openNewConversation(in: nil)
    }

    /// A new conversation there, made on the Mac with its first message.
    private func openNewConversation(in place: ProjectRef?) {
        router.push(draft: store.newDraft(in: place).id)
    }

    private func connectProject() {
        isConnecting = true
    }

    /// "Connect a project" from the sidebar starts a new conversation in the folder chosen.
    private func connectChosen(_ project: ProjectRef) async -> Bool {
        openNewConversation(in: project)
        return true
    }

    private func stop(_ chat: ChatSummary) {
        Task { await store.attempt { try await store.stop(chat: chat.id) } }
    }

    private func trash(_ chat: ChatSummary) {
        Task { await store.attempt { try await store.trash(chat: chat.id) } }
    }

    private func startRenaming(_ chat: ChatSummary) {
        newTitle = chat.title
        renaming = chat
        isRenaming = true
    }

    private func rename(_ chat: ChatSummary) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != chat.title else { return }
        Task { await store.attempt { try await store.rename(chat: chat.id, to: title) } }
    }
}
