import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The bottom accessory above the tab bar, while Pebble works on a run: the run bar ("Editing · Fix login · 2 min 05 s")
/// with Stop, without glass of its own (the accessory draws it); its pebble and words are a button that opens the chat.
/// Shorter (no title) while the tab bar is minimized, and the status word alone at accessibility text sizes, where
/// anything more is cut off.
///
/// It shows only on the Chats, Reviews and Control roots, and only for a run Pebble is working on
/// (`Router.showsRunAccessory`, `RunControls.accessoryRun`): never for one that waits for the person. On iOS 26.0,
/// where the accessory can't hide, it shows Pebble's state and "New conversation" when nothing works, and leaves Stop
/// out where the screen already shows it (one Stop per screen, design review A1): in the Pebble tab's list of live runs
/// and in the run's own conversation.
struct RunAccessory: View {
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var stops = 0

    var body: some View {
        // One container, so the Stop haptic still plays while the run bar gives way to the idle line.
        VStack {
            if let run = shownRun {
                let isOpen = run.chatID == router.openChatID
                // The accessory's height is the system's: from the second largest standard size its second line (the
                // conversation's title) is cut off, and at accessibility sizes the time too, so they give way.
                let showsTitle = placement != .inline && typeSize < .xxLarge
                RunBar(
                    status: run.status, title: showsTitle ? run.chatTitle : "",
                    startedAt: typeSize.isAccessibilitySize ? nil : run.started, isPaused: run.state == .paused,
                    attempt: run.attempt,
                    stealth: store.pebble?.stealth ?? false, animated: isOnlyPebbleInView, chrome: .plain,
                    onStop: stopControl(for: run, isOpen: isOpen), onOpen: openControl(for: run, isOpen: isOpen))
                .accessibilityShowsLargeContentViewer()
            } else {
                HStack {
                    IdleSummary()
                    if store.bridgeOffers("new_chat") {
                        Button(AppCopy.Chats.newConversation, systemImage: PebbleSymbol.askPebble, action: newConversation)
                            .labelStyle(.iconOnly)
                            .frame(minWidth: PebbleSize.minTap, minHeight: PebbleSize.minTap)
                            .accessibilityHint(AppCopy.Sidebar.newConversationHint)
                    }
                }
                .padding(.horizontal)
            }
        }
        // A bar: its words stop growing at the largest standard size, as the tab bar's do, so the status word fits;
        // at accessibility sizes a long press shows it large (the large content viewer).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(PebbleHaptics.stopped, trigger: stops)
    }

    /// A run Pebble is working on; never one that waits for the person.
    private var shownRun: LiveRun? {
        RunControls.accessoryRun(store.liveRuns, openChat: router.openChatID)
    }

    /// The Pebble tab's own screen, whose list gives every live run its Stop.
    private var isOverviewInView: Bool {
        router.tab == .pebble && router.pebblePath.isEmpty
    }

    /// One animated pebble per window (docs/DESIGN.md §1.6): this one stays still under the Pebble tab's own pebble
    /// and under a conversation, whose run bar has its own.
    private var isOnlyPebbleInView: Bool {
        switch router.tab {
        case .pebble: false
        case .chats: router.chatsPath.isEmpty
        case .reviews: router.reviewsPath.isEmpty
        case .control: true
        }
    }

    /// Stop, unless the run waits for the person's decision or the screen already has the run's Stop.
    private func stopControl(for run: LiveRun, isOpen: Bool) -> (() -> Void)? {
        guard !isOpen, !isOverviewInView, RunControls.offersStop(run.state) else { return nil }
        return { stop(run) }
    }

    /// Opens the run's conversation, unless it is the one on screen.
    private func openControl(for run: LiveRun, isOpen: Bool) -> (() -> Void)? {
        guard !isOpen else { return nil }
        return { router.showChat(run.chatID) }
    }

    private func stop(_ run: LiveRun) {
        Task {
            if await store.attempt({ try await store.stop(chat: run.chatID) }) { stops += 1 }
        }
    }

    /// "New conversation", as the Mac's ⌘N: in Companion, on the tab the person is in.
    private func newConversation() {
        router.push(draft: store.newDraft().id)
    }
}
