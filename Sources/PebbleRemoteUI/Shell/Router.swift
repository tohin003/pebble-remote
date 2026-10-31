import Foundation
import Observation
import PebbleRemoteKit

/// Where the person is: the selected tab, each tab's navigation path, and the sheets the shell presents.
/// Kept above the tabs so deep links and the bottom accessory can move between them.
@Observable
final class Router {
    var tab: AppTab = .pebble
    var pebblePath: [ChatRoute] = []
    var chatsPath: [ChatRoute] = []
    var reviewsPath: [ChatRoute] = []
    var controlPath: [ControlRoute] = []
    /// Recently Deleted, pushed on the Chats tab over its list (not a conversation, so not in `chatsPath`).
    var isShowingRecentlyDeleted = false
    /// A pairing link opened from outside the app (the Camera app, a tapped link), waiting for the person to confirm.
    var pairingToConfirm: PendingPairing?
    /// The permission-mode sheet, opened from the mode chip.
    var isChoosingMode = false
    /// The unlock sheet (C1), opened when a call came back `unlock_required`.
    var isAskingToUnlock = false
    /// A conversation's Details to open once the conversation shows (lane Y: Settings › Across Conversations opens a
    /// schedule's or a shared window's conversation on Details › Tools). Its conversation takes it once.
    var detailsToOpen: DetailsTarget?
    /// Words for a conversation's composer to add to what it holds (an app demo's Send Feedback, App.vue
    /// `demoFeedback`). Its composer on the tab on screen takes them once.
    var composerWords: ComposerWords?

    func open(_ link: DeepLink) {
        switch link {
        case .pair(let pairing):
            pairingToConfirm = PendingPairing(link: pairing)
        case .chat(let id):
            showChat(id)
        case .reviews:
            tab = .reviews
            reviewsPath = []
        }
    }

    /// The conversation on screen: the top of the selected tab's stack (Control pushes none). A new conversation that
    /// isn't on the Mac yet has none.
    var openChatID: ChatID? {
        switch tab {
        case .pebble: pebblePath.last?.chatID
        case .chats: chatsPath.last?.chatID
        case .reviews: reviewsPath.last?.chatID
        case .control: nil
        }
    }

    /// Shows a conversation on the Chats tab, from anywhere (a link, the bottom accessory).
    func showChat(_ id: ChatID) {
        tab = .chats
        isShowingRecentlyDeleted = false
        chatsPath = [ChatRoute(chatID: id)]
    }

    /// Shows a conversation on the Chats tab, as `showChat` does, then its Details on the target's tab.
    func showDetails(_ target: DetailsTarget) {
        showChat(target.chatID)
        detailsToOpen = target
    }

    /// The Details waiting for this conversation, taken once (nil for another conversation's) by its screen on the tab
    /// on screen: the same conversation open on a hidden tab never takes it.
    func takeDetails(for chat: ChatID, on screenTab: AppTab?) -> DetailsTarget? {
        guard let target = detailsToOpen, target.chatID == chat, screenTab == tab else { return nil }
        detailsToOpen = nil
        return target
    }

    /// Puts words in a conversation's composer, showing the conversation first when another one is on screen.
    func write(_ words: String, in chat: ChatID) {
        if openChatID != chat { showChat(chat) }
        composerWords = ComposerWords(chatID: chat, words: words)
    }

    /// The words waiting for this conversation's composer, taken once by its composer on the tab on screen.
    func takeComposerWords(for chat: ChatID, on screenTab: AppTab?) -> String? {
        guard let waiting = composerWords, waiting.chatID == chat, screenTab == tab else { return nil }
        composerWords = nil
        return waiting.words
    }

    /// Pushes a conversation on the tab the person is in.
    func push(_ id: ChatID) {
        push(ChatRoute(chatID: id))
    }

    /// Opens a new conversation (`RemoteStore.newDraft(in:)`) on the tab the person is in, as "New conversation" does.
    func push(draft id: String) {
        push(ChatRoute(draftID: id))
    }

    /// The draft became a conversation on the Mac (its first message went): the conversation takes the draft's place,
    /// on whichever tab holds it, so Back still leads where it led.
    func replace(draft id: String, with chat: ChatID) {
        let draft = ChatRoute(draftID: id)
        let made = ChatRoute(chatID: chat)
        for index in pebblePath.indices where pebblePath[index] == draft { pebblePath[index] = made }
        for index in chatsPath.indices where chatsPath[index] == draft { chatsPath[index] = made }
        for index in reviewsPath.indices where reviewsPath[index] == draft { reviewsPath[index] = made }
    }

    /// Back to the start: used when the store changes (the demo starts or ends, the Mac is forgotten).
    func reset() {
        tab = .pebble
        pebblePath = []
        chatsPath = []
        reviewsPath = []
        controlPath = []
        isShowingRecentlyDeleted = false
        isChoosingMode = false
        isAskingToUnlock = false
        detailsToOpen = nil
        composerWords = nil
    }

    /// A route on the tab the person is in; Control holds no conversations, so it opens them on Chats.
    private func push(_ route: ChatRoute) {
        switch tab {
        case .pebble: pebblePath.append(route)
        case .chats: chatsPath.append(route)
        case .reviews: reviewsPath.append(route)
        case .control:
            tab = .chats
            isShowingRecentlyDeleted = false
            chatsPath = [route]
        }
    }
}

/// Words on their way to a conversation's composer. Each hand-off is its own, so the same words twice still arrive.
struct ComposerWords: Equatable {
    let id = UUID()
    let chatID: ChatID
    let words: String

    /// The composer's text with `words` added: after what it holds, on a line of their own, as Pebble's window does.
    static func merged(_ draft: String, _ words: String) -> String {
        var kept = draft
        while let last = kept.last, last.isWhitespace { kept.removeLast() }
        return kept.isEmpty ? words : kept + "\n" + words
    }
}
