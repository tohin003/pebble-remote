import SwiftUI

/// The Chats tab, arranged as Pebble's sidebar: New conversation, Your space, then the recent conversations, each
/// opening its live transcript.
struct ChatsTab: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.chatsPath) {
            ChatsList()
                .navigationDestination(for: ChatRoute.self, destination: ChatDestination.init)
        }
    }
}
