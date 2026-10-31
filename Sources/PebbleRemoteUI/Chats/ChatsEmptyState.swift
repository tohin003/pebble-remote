import PebbleDesign
import SwiftUI

/// Nothing to list: no chats yet, or no search results (the system's search state names the query itself).
struct ChatsEmptyState: View {
    let isSearching: Bool
    let isEmpty: Bool

    var body: some View {
        if isEmpty {
            if isSearching {
                ContentUnavailableView.search
            } else {
                PebbleEmptyState(.noChats)
            }
        }
    }
}
