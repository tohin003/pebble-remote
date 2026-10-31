import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Where links, the accessory and "New conversation" take the person.
struct RouterTests {
    private let pairing = PairingLink(
        version: 1, bridgeID: "b1", macName: "Studio", pin: "p1", code: "c1",
        endpoints: [Endpoint(host: "10.0.0.2", port: 7443)])

    @Test func chatLinkShowsTheChatOnTheChatsTab() {
        let router = Router()
        router.chatsPath = [ChatRoute(chatID: "old")]
        router.open(.chat("new"))
        #expect(router.tab == .chats)
        #expect(router.chatsPath == [ChatRoute(chatID: "new")])
    }

    @Test func reviewsLinkSelectsReviewsAtItsRoot() {
        let router = Router()
        router.reviewsPath = [ChatRoute(chatID: "x")]
        router.open(.reviews)
        #expect(router.tab == .reviews)
        #expect(router.reviewsPath.isEmpty)
    }

    @Test func pairingLinkWaitsForConfirmation() {
        let router = Router()
        router.open(.pair(pairing))
        #expect(router.pairingToConfirm?.link == pairing)
        #expect(router.tab == .pebble)
    }

    @Test(arguments: [AppTab.pebble, .chats, .reviews])
    func pushStaysOnTheCurrentTab(_ tab: AppTab) {
        let router = Router()
        router.tab = tab
        router.push("x")
        let paths = [router.pebblePath, router.chatsPath, router.reviewsPath]
        #expect(paths.count(where: { $0 == [ChatRoute(chatID: "x")] }) == 1)
        #expect(router.tab == tab)
    }

    @Test func pushFromControlOpensChats() {
        let router = Router()
        router.tab = .control
        router.push("x")
        #expect(router.tab == .chats)
        #expect(router.chatsPath == [ChatRoute(chatID: "x")])
    }

    @Test func resetClearsEveryPathAndSheet() {
        let router = Router()
        router.tab = .control
        router.controlPath = [.connection]
        router.pebblePath = [ChatRoute(chatID: "a")]
        router.chatsPath = [ChatRoute(draftID: "d")]
        router.isChoosingMode = true
        router.isAskingToUnlock = true
        router.reset()
        #expect(router.tab == .pebble)
        #expect(router.controlPath.isEmpty && router.pebblePath.isEmpty && router.chatsPath.isEmpty)
        #expect(!router.isChoosingMode && !router.isAskingToUnlock)
    }

    @Test func aRouteIsAConversationOrANewOne() {
        let chat = ChatRoute(chatID: "c1")
        let draft = ChatRoute(draftID: "d1")
        #expect(chat.chatID == "c1" && chat.draftID == nil)
        #expect(draft.chatID == nil && draft.draftID == "d1")
        #expect(chat != ChatRoute(chatID: "d1") && draft != ChatRoute(chatID: "d1"))
    }

    /// "New conversation" opens on the tab the person is in, as a conversation does; Control has none, so Chats.
    @Test(arguments: [AppTab.pebble, .chats, .reviews])
    func aNewConversationOpensOnTheCurrentTab(_ tab: AppTab) {
        let router = Router()
        router.tab = tab
        router.push(draft: "d1")
        let paths = [router.pebblePath, router.chatsPath, router.reviewsPath]
        #expect(paths.count(where: { $0 == [ChatRoute(draftID: "d1")] }) == 1)
        #expect(router.tab == tab)
        #expect(router.openChatID == nil)  // nothing is on the Mac yet
    }

    @Test func aNewConversationFromControlOpensOnChats() {
        let router = Router()
        router.tab = .control
        router.chatsPath = [ChatRoute(chatID: "old")]
        router.push(draft: "d1")
        #expect(router.tab == .chats)
        #expect(router.chatsPath == [ChatRoute(draftID: "d1")])
    }

    /// The first message made the conversation: it takes the draft's place where the draft is, so Back still leads to
    /// where it led, and it is the open conversation (A1: its run bar holds the Stop).
    @Test func theConversationTakesTheDraftsPlace() {
        let router = Router()
        router.tab = .chats
        router.chatsPath = [ChatRoute(chatID: "a"), ChatRoute(draftID: "d1")]
        router.pebblePath = [ChatRoute(draftID: "d2")]
        router.replace(draft: "d1", with: "c9")
        #expect(router.chatsPath == [ChatRoute(chatID: "a"), ChatRoute(chatID: "c9")])
        #expect(router.openChatID == "c9")
        #expect(router.pebblePath == [ChatRoute(draftID: "d2")])  // another draft stays as it was
        router.replace(draft: "d2", with: "c10")
        #expect(router.pebblePath == [ChatRoute(chatID: "c10")])
        router.replace(draft: "gone", with: "c11")  // a draft no tab holds: nothing moves
        #expect(router.chatsPath.count == 2 && router.pebblePath.count == 1)
    }

    /// The demo's drafts: "New conversation" opens one the store finds again by its route, in the place chosen.
    @MainActor
    @Test func aDraftsRouteFindsItInTheStore() throws {
        let store = RemoteStore.demo(pace: 0)
        let router = Router()
        router.tab = .chats
        let draft = store.newDraft(in: ProjectRef(folder: "/Users/you/Projects/pebble-web"))
        router.push(draft: draft.id)
        let id = try #require(router.chatsPath.last?.draftID)
        #expect(store.draft(id) === draft)
        #expect(draft.placeName == "pebble-web")
    }

    @Test func openChatIsTheTopOfTheSelectedTabsStack() {
        let router = Router()
        #expect(router.openChatID == nil)
        router.pebblePath = [ChatRoute(chatID: "a")]
        router.chatsPath = [ChatRoute(chatID: "b"), ChatRoute(chatID: "c")]
        #expect(router.openChatID == "a")
        router.tab = .chats
        #expect(router.openChatID == "c")
        router.tab = .reviews
        #expect(router.openChatID == nil)
        router.tab = .control
        #expect(router.openChatID == nil)
    }

    /// Design review A1: one Stop per screen. Inside a conversation whose run is live, its run bar holds the Stop and
    /// the bottom accessory gives way; anywhere else the accessory stays.
    @MainActor
    @Test func theAccessoryGivesWayOnlyInsideALiveConversation() async throws {
        let store = RemoteStore.demo(pace: 0)
        store.start()
        let router = Router()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while store.liveRuns.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let live = try #require(store.liveRuns.first)
        #expect(!router.isShowingLiveChat(in: store))
        router.showChat(live.chatID)
        #expect(router.isShowingLiveChat(in: store))
        router.chatsPath = [ChatRoute(chatID: "not-a-live-chat")]
        #expect(!router.isShowingLiveChat(in: store))
        router.tab = .control
        #expect(!router.isShowingLiveChat(in: store))
    }

    /// An app demo's Send Feedback (App.vue `demoFeedback`): the words go to the conversation's composer on the tab on
    /// screen, once; a conversation not on screen is shown first.
    @Test func feedbackWordsReachTheComposerOnTheTabOnScreenOnce() {
        let router = Router()
        router.tab = .pebble
        router.pebblePath = [ChatRoute(chatID: "c1")]
        router.chatsPath = [ChatRoute(chatID: "c1")]  // the same conversation, also open on a hidden tab
        router.write("Feedback: ", in: "c1")
        #expect(router.tab == .pebble && router.pebblePath == [ChatRoute(chatID: "c1")])
        #expect(router.takeComposerWords(for: "c2", on: .pebble) == nil)
        #expect(router.takeComposerWords(for: "c1", on: .chats) == nil)
        #expect(router.takeComposerWords(for: "c1", on: .pebble) == "Feedback: ")
        #expect(router.takeComposerWords(for: "c1", on: .pebble) == nil)

        router.write("Feedback: ", in: "c9")
        #expect(router.tab == .chats && router.chatsPath == [ChatRoute(chatID: "c9")])
        router.reset()
        #expect(router.composerWords == nil)
    }

    @Test func feedbackWordsGoOnALineAfterWhatTheFieldHolds() {
        #expect(ComposerWords.merged("", "Feedback: ") == "Feedback: ")
        #expect(ComposerWords.merged("  \n ", "Feedback: ") == "Feedback: ")
        #expect(ComposerWords.merged("The login screen  \n", "Feedback: ") == "The login screen\nFeedback: ")
        #expect(ComposerWords(chatID: "c1", words: "a") != ComposerWords(chatID: "c1", words: "a"))  // each its own
    }
}
