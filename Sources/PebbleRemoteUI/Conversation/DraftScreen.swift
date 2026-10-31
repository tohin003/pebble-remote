import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// "New conversation", before its first message: the conversation's layout with Pebble's welcome, where it starts at
/// the top (Companion, a project, or Connect a project), and the model, effort and composer below. Nothing is on the Mac
/// until the first message is sent (or a terminal command, which needs the conversation); then the conversation takes
/// this screen's place.
///
/// The welcome scrolls in the space between the two bars and ends at them, so at the largest text sizes its words
/// never run under the chips, the composer or the tab bar, nor take their taps (the UX audit's U-43). At accessibility
/// text sizes the tab bar hides here, and the model and effort move into a ⋯ menu, as in a conversation.
struct DraftScreen: View {
    let draft: ConversationDraft
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var sheet: ConversationSheet?
    /// The composer has the keyboard. Owned here, so a tap on the welcome closes it, as in a conversation.
    @FocusState private var isWriting: Bool

    var body: some View {
        // Decided here, for both the bottom bar and the ⋯ menu (U-52), as in a conversation.
        let modelEffort = ModelEffortPlacement(textSize: typeSize)
        VStack(spacing: 0) {
            DraftPlaceBar(draft: draft, sheet: $sheet)
            DraftWelcome(draft: draft)
                .closesKeyboardOnTap($isWriting)
            DraftBottomBar(draft: draft, sheet: $sheet, modelEffort: modelEffort, isWriting: $isWriting, made: show)
        }
        .navigationTitle(AppCopy.Draft.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(typeSize.isAccessibilitySize ? .hidden : .automatic, for: .tabBar)
        #endif
        .toolbar {
            if modelEffort.showsInMenu, store.bridgeOffers("model_select") || store.bridgeOffers("model_effort") {
                ToolbarItem(placement: .primaryAction) {
                    Menu(AppCopy.Conversation.more, systemImage: "ellipsis") {
                        ModelEffortBar(style: .menuItems)
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(item: $sheet, onDismiss: showIfMade) { which in
            DraftSheetView(which: which, draft: draft, sheet: $sheet)
                .lockCover()
        }
    }

    /// A terminal command made the conversation from a sheet: it shows once the sheet has gone.
    private func showIfMade() {
        if draft.isSent, let chat = draft.chatID { show(chat) }
    }

    /// The conversation takes the draft's place, without a transition: the same screen, now on the Mac.
    private func show(_ chat: ChatID) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            router.replace(draft: draft.id, with: chat)
        }
        store.discardDraft(draft.id)
    }
}
