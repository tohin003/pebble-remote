import PebbleRemoteKit
import SwiftUI

/// The iPhone-only parts of the tab bar: it never minimizes, and the bottom accessory above it shows the run Pebble is
/// working on. Both are iOS API; the macOS type-check builds the plain TabView.
///
/// The four tabs are the app's map (IA rule 2), and the person asked twice to always reach them: a bar that shrank to one
/// button on a scroll looked gone after the keyboard had covered it (the re-check's U-55), so it stays whole.
///
/// The accessory shows only while Pebble works on a task, and only on the Chats, Reviews and Control roots
/// (`Router.showsRunAccessory`, the lead's decision after the re-check's U-04). Not for a run that waits for the
/// person: Reviews and the Chats rows show those. Not on the Pebble tab, whose hero and Working Now show the run; not in
/// a conversation, whose run bar holds its run; and not on a pushed page, where it lay over rows and took their taps.
/// Hiding it needs iOS 26.1. On iOS 26.0 the accessory cannot be hidden without rebuilding the TabView (which would reset
/// every tab's navigation), so it stays: it shows only a working run, else Pebble's state, and leaves its Stop out where
/// the screen already has one (`RunAccessory`).
struct TabShellChrome: ViewModifier {
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        #if os(iOS)
        let minimizing = content.tabBarMinimizeBehavior(.never)
        if #available(iOS 26.1, *) {
            minimizing.tabViewBottomAccessory(isEnabled: router.showsRunAccessory(in: store)) {
                RunAccessory()
            }
        } else {
            minimizing.tabViewBottomAccessory {
                RunAccessory()
            }
        }
        #else
        content
        #endif
    }
}

extension Router {
    /// Whether the tab bar's bottom accessory shows: only while Pebble works on a run (`runIsWorking`), and only on the
    /// root of Chats, Reviews or Control. Never on the Pebble tab (its hero and Working Now show the run), never inside a
    /// conversation or a new one (its own run bar holds the run and the screen's one Stop), never on another pushed page
    /// (Control's pages, Recently Deleted).
    func showsRunAccessory(runIsWorking: Bool) -> Bool {
        guard runIsWorking else { return false }
        return switch tab {
        case .pebble: false
        case .chats: chatsPath.isEmpty && !isShowingRecentlyDeleted
        case .reviews: reviewsPath.isEmpty
        case .control: controlPath.isEmpty
        }
    }

    /// The same, for the store's runs: whether the screen in front has the accessory under it now.
    func showsRunAccessory(in store: RemoteStore) -> Bool {
        showsRunAccessory(runIsWorking: RunControls.accessoryRun(store.liveRuns, openChat: openChatID) != nil)
    }

    /// Pebble's reply banner ("Pebble finished") shows everywhere but in the conversation it announces, where the run's
    /// end line or card already says it and the banner would only cover the title and the ⋯ menu.
    func showsBanner(for chat: ChatID) -> Bool {
        openChatID != chat
    }

    /// Whether the conversation on screen has a live run: its run bar then holds the run's one Stop.
    func isShowingLiveChat(in store: RemoteStore) -> Bool {
        guard let open = openChatID else { return false }
        return store.liveRuns.contains { $0.chatID == open }
    }
}
