import CoreGraphics
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI
import Testing

@testable import PebbleRemoteUI

/// Lane V (the UX audit of 2026-10-30, layout and chrome): where the bottom accessory shows, which run controls a run
/// offers, where the reply banner shows, where a conversation opens and holds on to, and the Chats order while touched.
struct ChromeRulesTests {
    // MARK: - Stop and Pause on a run that waits for the person (U-10), as on Pebble's Mac

    @Test func aRunWaitingForADecisionOffersNeitherStopNorPause() {
        for state in [RunState.waitingApproval, .waitingInput] {
            #expect(RunControls.awaitsDecision(state))
            #expect(!RunControls.offersStop(state))
            #expect(!RunControls.offersPauseInBar(state))
        }
    }

    @Test func aWorkingOrPausedRunKeepsStopAndPause() {
        for state in [RunState.queued, .running, .retryWait, .paused] {
            #expect(!RunControls.awaitsDecision(state))
            #expect(RunControls.offersStop(state))
            #expect(RunControls.offersPauseInBar(state))
        }
    }

    // MARK: - The bottom accessory (U-04, U-05, U-16; the lead's rule after the re-check)

    static func run(_ chat: String, _ state: RunState, status: StatusKey = .reading) -> LiveRun {
        LiveRun(id: "r-\(chat)", chatID: chat, chatTitle: chat, state: state, status: status)
    }

    @Test func theAccessoryNeverShowsOnThePebbleTab() {
        let router = Router()
        router.tab = .pebble
        #expect(!router.showsRunAccessory(runIsWorking: true))
        router.pebblePath = [ChatRoute(chatID: "c1")]
        #expect(!router.showsRunAccessory(runIsWorking: true))
    }

    @Test(arguments: [AppTab.chats, .reviews, .control])
    func theAccessoryShowsOnARootOnlyWhilePebbleWorks(_ tab: AppTab) {
        let router = Router()
        router.tab = tab
        #expect(router.showsRunAccessory(runIsWorking: true))
        #expect(!router.showsRunAccessory(runIsWorking: false))
    }

    @Test(arguments: [AppTab.chats, .reviews])
    func theAccessoryNeverShowsInsideAConversation(_ tab: AppTab) {
        let router = Router()
        router.tab = tab
        let pushed = [ChatRoute(chatID: "c1")]
        if tab == .chats { router.chatsPath = pushed } else { router.reviewsPath = pushed }
        #expect(!router.showsRunAccessory(runIsWorking: true))
        // A new conversation, not on the Mac yet, has the composer too.
        let draft = [ChatRoute(draftID: "d1")]
        if tab == .chats { router.chatsPath = draft } else { router.reviewsPath = draft }
        #expect(!router.showsRunAccessory(runIsWorking: true))
    }

    @Test func theAccessoryLeavesControlsPagesAndRecentlyDeleted() {
        let router = Router()
        router.tab = .control
        router.controlPath = [.schedules]
        #expect(!router.showsRunAccessory(runIsWorking: true))
        router.tab = .chats
        router.isShowingRecentlyDeleted = true
        #expect(!router.showsRunAccessory(runIsWorking: true))
        // Opening a conversation from anywhere leaves Recently Deleted.
        router.showChat("c1")
        #expect(!router.isShowingRecentlyDeleted)
    }

    @Test func theAccessoryShowsOnlyARunPebbleIsWorkingOn() {
        let waiting = [Self.run("a", .waitingApproval, status: .review), Self.run("b", .waitingInput, status: .question)]
        #expect(RunControls.accessoryRun(waiting, openChat: nil) == nil)
        #expect(RunControls.accessoryRun([Self.run("p", .paused, status: .paused)], openChat: nil) == nil)
        let mixed = waiting + [Self.run("c", .running), Self.run("d", .queued)]
        #expect(RunControls.accessoryRun(mixed, openChat: nil)?.chatID == "c")
        #expect(RunControls.accessoryRun(mixed, openChat: "d")?.chatID == "d")
        #expect(RunControls.accessoryRun(mixed, openChat: "a")?.chatID == "c")  // never the waiting one, even when open
        #expect(RunControls.accessoryRun([Self.run("e", .retryWait, status: .reconnecting)], openChat: nil)?.chatID == "e")
    }

    // MARK: - Ask Pebble's keyboard always lets go (the person's P1)

    @Test func sendWithNothingTypedClosesTheKeyboard() {
        #expect(AskPebbleField.Submission("") == .closeKeyboard)
        #expect(AskPebbleField.Submission("  \n\t ") == .closeKeyboard)
    }

    @Test func sendWithWordsSendsThemTrimmed() {
        #expect(AskPebbleField.Submission("  Check the login  \n") == .send("Check the login"))
    }

    // MARK: - Model and effort at every text size (U-52)

    /// The screen decides once and both the bottom bar and the ⋯ menu follow: whenever the chips are hidden, the menu has
    /// Model and Effort, and never both.
    @Test func modelAndEffortAreInExactlyOnePlaceAtEveryTextSize() {
        for size in DynamicTypeSize.allCases {
            let placement = ModelEffortPlacement(textSize: size)
            #expect(placement.showsChips != placement.showsInMenu)
            #expect(placement.showsInMenu == size.isAccessibilitySize)
        }
    }

    // MARK: - The reply banner (U-21)

    @Test func theBannerDoesNotShowInTheConversationItAnnounces() {
        let router = Router()
        router.tab = .chats
        router.chatsPath = [ChatRoute(chatID: "c1")]
        #expect(!router.showsBanner(for: "c1"))
        #expect(router.showsBanner(for: "c2"))
        router.chatsPath = []
        #expect(router.showsBanner(for: "c1"))
    }

    // MARK: - Where a conversation opens (U-11, U-25)

    static func message(_ id: String, _ role: MessageItem.Role = .assistant) -> TranscriptItem {
        .message(MessageItem(id: id, role: role, text: "Words"))
    }

    static func card(_ id: String) -> TranscriptItem {
        .review(ReviewItem(chatID: "c1", chatTitle: "Fix", actionID: id, kind: .command, title: "Runs npm test."))
    }

    static func question(_ id: String) -> TranscriptItem {
        .question(QuestionCard(chatID: "c1", chatTitle: "Fix", questionID: id, runID: "r1", revision: 1, required: true, prompts: []))
    }

    @Test func aConversationThatEndsWithWordsOpensAtTheEnd() {
        #expect(TranscriptScroll.openingCard(in: []) == nil)
        #expect(TranscriptScroll.openingCard(in: [Self.message("m1", .user), Self.message("m2")]) == nil)
        let ended: [TranscriptItem] = [
            Self.message("m1"), .runEnd(id: "e1", runID: "r1", state: .completed, seconds: 9, note: nil),
        ]
        #expect(TranscriptScroll.openingCard(in: ended) == nil)
    }

    @Test func aConversationThatEndsWithWaitingCardsOpensOnTheFirstOfThem() {
        let items = [Self.message("m1", .user), Self.card("a0"), Self.message("m2"), Self.card("a1"), Self.question("q1")]
        #expect(TranscriptScroll.openingCard(in: items) == Self.card("a1").id)
        #expect(TranscriptScroll.openingCard(in: [Self.question("q1")]) == Self.question("q1").id)
    }

    // MARK: - Where the transcript holds on to (U-15, U-49, U-30), with the re-check's frames (iPhone 17, 402 × 874 pt)

    /// The space between the bars: below the navigation bar (y 116), above the bottom bar at `bottom`.
    static func space(bottom: CGFloat) -> CGRect { CGRect(x: 0, y: 116, width: 402, height: bottom - 116) }

    /// The transcript's stack on screen, from `top`, `height` tall.
    static func stack(top: CGFloat, height: CGFloat) -> CGRect { CGRect(x: 0, y: top, width: 402, height: height) }

    static func metrics(stack: CGRect, bottom: CGFloat = 641, card: CGFloat? = nil) -> TranscriptScroll.Metrics {
        var metrics = TranscriptScroll.Metrics()
        metrics.stack = stack
        metrics.visible = Self.space(bottom: bottom)
        metrics.waitingCardTop = card
        return metrics
    }

    @Test func theHeldChangeAtItsEndIsAtTheEnd() {
        // The re-check's tree: the stack 751 tall from y -110 ends at 641, where the space between the bars ends; "Jump
        // to Latest" showed there all the same, over the task's Details.
        let held = Self.metrics(stack: Self.stack(top: -110, height: 751))
        #expect(held.canScroll && held.isAtEnd && held.restsAtEnd)
        #expect(!held.showsJump)
    }

    @Test func aShortTranscriptIsAtItsEndAndOffersNoJump() {
        // The working conversation in the re-check's tree: 187 pt from y 402, the space ends at 589.
        let short = Self.metrics(stack: Self.stack(top: 402, height: 187), bottom: 589)
        #expect(!short.canScroll && short.isAtEnd && short.restsAtEnd)
        #expect(!short.showsJump)
    }

    @Test func jumpShowsOnlyAwayFromTheEndAndNeverOverAWaitingCard() {
        // 100 pt above the end: not at the end, so it shows.
        let above = Self.metrics(stack: Self.stack(top: -10, height: 751))
        #expect(above.canScroll && !above.isAtEnd && above.showsJump)
        // 30 pt above the end: within Pebble's 48 pt it still counts as the end, though it doesn't rest there.
        let near = Self.metrics(stack: Self.stack(top: -80, height: 751))
        #expect(near.isAtEnd && !near.restsAtEnd && !near.showsJump)
        // A waiting card whose top is in the space: it stays away from the card's buttons.
        let card = Self.metrics(stack: Self.stack(top: -10, height: 751), card: 400)
        #expect(card.waitingCardInView && !card.showsJump)
        // The card further down, out of the space: it shows, to lead back to it.
        let cardBelow = Self.metrics(stack: Self.stack(top: -10, height: 751), card: 700)
        #expect(!cardBelow.waitingCardInView && cardBelow.showsJump)
        // Not measured yet: never.
        #expect(!TranscriptScroll.Metrics().showsJump)
    }

    @Test func anEmptyBandUnderTheEndIsNotAtRest() {
        // Scrolled past the end, so an empty band shows above the composer: at the end, but not resting there.
        let past = Self.metrics(stack: Self.stack(top: -400, height: 751))
        #expect(past.isAtEnd && !past.restsAtEnd && past.hasBandUnderEnd)
        // A short transcript lifted off the bars (the re-check's 024) has a band too; one resting on them has none.
        let lifted = Self.metrics(stack: Self.stack(top: 300, height: 187), bottom: 589)
        #expect(!lifted.canScroll && lifted.hasBandUnderEnd && !lifted.restsAtEnd)
        let resting = Self.metrics(stack: Self.stack(top: 402, height: 187), bottom: 589)
        #expect(!resting.hasBandUnderEnd && resting.restsAtEnd)
    }

    @Test func onlySizeChangesCountAsLayoutChanges() {
        let before = Self.metrics(stack: Self.stack(top: -110, height: 751))
        #expect(!Self.metrics(stack: Self.stack(top: 0, height: 751)).layoutChanged(from: before))
        #expect(Self.metrics(stack: Self.stack(top: -110, height: 800)).layoutChanged(from: before))
        #expect(Self.metrics(stack: Self.stack(top: -110, height: 751), bottom: 589).layoutChanged(from: before))
    }

    // MARK: - Chats holds its order while touched (U-31)

    struct Row: Identifiable, Equatable {
        let id: String
        var title = ""
    }

    @Test func nothingHeldShowsTheRowsAsTheyCome() {
        let rows = [Row(id: "b"), Row(id: "a")]
        #expect(HeldOrder.apply(nil, to: rows) == rows)
    }

    @Test func aHeldOrderKeepsPlacesDropsGoneRowsAndHoldsBackNewOnes() {
        // Pebble moved "c" to the top, "b" went away and "d" is new; the held order was a, b, c.
        let now = [Row(id: "c", title: "Finished"), Row(id: "d"), Row(id: "a")]
        let shown = HeldOrder.apply(["a", "b", "c"], to: now)
        #expect(shown.map(\.id) == ["a", "c"])
        #expect(shown.last?.title == "Finished")  // the newest content, in the old place
    }
}
