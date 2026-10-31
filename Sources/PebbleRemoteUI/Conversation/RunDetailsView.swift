import PebbleRemoteKit
import SwiftUI

/// A run's details, opened from the conversation's ⋯ menu ("Details"), its end line or a task's controls: the
/// conversation's Details screen on its Activity tab, where "What Pebble did" now lives with the drawer's other tabs
/// (lane Y, fix 8).
struct RunDetailsView: View {
    let request: RunDetailsRequest

    var body: some View {
        DetailsScreen(chatID: request.chatID, runID: request.runID, tab: request.tab)
    }
}
