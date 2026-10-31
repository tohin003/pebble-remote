import SwiftUI

/// The Pebble tab: what Pebble is doing, the Mac, live runs, what needs review, and a new conversation.
struct OverviewTab: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.pebblePath) {
            OverviewScreen()
                .navigationDestination(for: ChatRoute.self, destination: ChatDestination.init)
        }
    }
}
