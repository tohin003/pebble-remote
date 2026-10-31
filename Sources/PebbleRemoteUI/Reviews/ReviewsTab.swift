import SwiftUI

/// The Reviews tab: every card and question waiting across chats, oldest first.
struct ReviewsTab: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.reviewsPath) {
            ReviewsList()
                .navigationDestination(for: ChatRoute.self, destination: ChatDestination.init)
        }
    }
}
