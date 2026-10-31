import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// The lead's IA decision (2026-10-31 02:30): each conversation's Details › Tools is the one home for its schedules and
/// shared windows; a row in Settings › Across Conversations opens that conversation, then its Details on Tools.
struct DetailsRoutingTests {
    @Test func aSettingsRowOpensItsConversationThenDetailsOnTools() {
        let router = Router()
        router.tab = .control
        router.controlPath = [.schedules]
        router.showDetails(DetailsOpening.tools(of: "c-theme"))
        #expect(router.tab == .chats)
        #expect(router.chatsPath == [ChatRoute(chatID: "c-theme")])
        #expect(router.detailsToOpen == DetailsTarget(chatID: "c-theme", tab: .tools))
        #expect(router.openChatID == "c-theme")
    }

    @Test func onlyItsOwnConversationTakesTheDetailsAndOnlyOnce() {
        let router = Router()
        router.showDetails(DetailsOpening.tools(of: "c1"))
        #expect(router.takeDetails(for: "c2", on: .chats) == nil)
        #expect(router.detailsToOpen != nil)
        #expect(router.takeDetails(for: "c1", on: .chats) == DetailsTarget(chatID: "c1", tab: .tools))
        #expect(router.takeDetails(for: "c1", on: .chats) == nil && router.detailsToOpen == nil)
    }

    @Test func theSameConversationOnAHiddenTabLeavesTheDetailsToChats() {
        let router = Router()
        router.pebblePath = [ChatRoute(chatID: "c1")]  // c1 also open on the Pebble tab, which stays alive while hidden
        router.showDetails(DetailsOpening.tools(of: "c1"))
        #expect(router.takeDetails(for: "c1", on: .pebble) == nil)
        #expect(router.takeDetails(for: "c1", on: nil) == nil)
        #expect(router.takeDetails(for: "c1", on: .chats) == DetailsTarget(chatID: "c1", tab: .tools))
    }

    @Test func startingOverForgetsAWaitingDetails() {
        let router = Router()
        router.showDetails(DetailsOpening.tools(of: "c1"))
        router.reset()
        #expect(router.detailsToOpen == nil && router.chatsPath.isEmpty)
    }

    @Test func aDetailsRequestOpensOnItsTabWithOrWithoutATask() {
        let tools = RunDetailsRequest(chatID: "c1", runID: nil, tab: .tools)
        #expect(tools.tab == .tools && tools.runID == nil)
        #expect(RunDetailsRequest(chatID: "c1", runID: "r1").tab == .activity)
        #expect(tools.id != RunDetailsRequest(chatID: "c1", runID: nil).id)
    }
}
