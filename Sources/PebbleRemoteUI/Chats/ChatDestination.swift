import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// What a tab's conversation route shows: a conversation on the Mac, or a new one before its first message.
struct ChatDestination: View {
    let route: ChatRoute
    @Environment(RemoteStore.self) private var store

    var body: some View {
        switch route.target {
        case .chat(let id):
            ConversationView(chatID: id)
        case .draft(let id):
            if let draft = store.draft(id) {
                DraftScreen(draft: draft)
            } else {
                // The store forgot the draft (another Mac, or many newer drafts); nothing of it was on the Mac.
                PebbleEmptyState(.noChats)
            }
        }
    }
}
