import PebbleDesign
import PebbleProtocol
import XCTest

extension AuditSession {
    /// Reviews, everything waiting for the person: the list top to bottom, what a card holds, the conversation it came
    /// from, the question, approving, a held task's question, an uncertain task's details, then deciding everything to
    /// reach the empty state; then, from a fresh demo, every other control on the tab.
    func tourReviews() {
        launch(pace: 1)
        openTab(AppCopy.Tabs.reviews)
        snap("reviews-list")
        dumpTree("reviews")
        var page = 0
        while page < 4, scrollDown() {
            page += 1
            snap("reviews-list-page-\(page + 1)")
        }
        scrollToTop()

        // What a card holds.
        if tapFirst(of: Self.cardDetailWords) != nil {
            screen = "card-details"
            pause(1)
            snap("reviews-card-details")
            leaveSheet("The card's details")
        }
        // `tapFirst` looks down the list page by page: back to the top, where the next steps start.
        scrollToTop()
        screen = "reviews"
        if element(AppCopy.Reviews.showMore, in: [.button], timeout: 0.5) != nil,
            tap(AppCopy.Reviews.showMore, in: [.button], scroll: false)
        {
            snap("reviews-card-show-more")
        }

        // The conversation a card came from.
        if tap(AppCopy.Reviews.inConversation(Demo.readme), in: [.button]) {
            snap("reviews-opens-the-cards-conversation")
            goBack()
        }
        screen = "reviews"

        // Pebble's question: its written answer takes the keyboard, which must close without sending (the person's P1 of
        // 2026-10-30), with the tab bar in reach. Then choose an answer, and submit.
        keyboardCheck(
            "the question's written answer", shot: "reviews-written-answer", exit: .swipeDown,
            open: { tap(AppCopy.Reviews.otherAnswer, in: [.button, .cell, .staticText]) })
        closeOverlays()
        if tap("Warm and friendly", in: [.button, .cell, .staticText]) {
            snap("reviews-question-answer-chosen")
            if tap(AppCopy.Reviews.sendAnswer, in: [.button]) {
                pause(1.5)
                snap("reviews-question-answered")
            }
        }

        // Approving the waiting command (in the demo, Face ID agrees by itself).
        if tapFirst(of: [AppCopy.Reviews.approve(.command), AppCopy.Reviews.approveFallback]) != nil {
            pause(2)
            snap("reviews-command-approved")
        }

        // The held task asks before keeping a change unverified.
        if tap(RecoveryCopy.Held.acceptAsUnverified, in: [.button]) {
            snap("reviews-accept-as-unverified-question")
            closeOverlays()
        }

        // The uncertain task's details.
        if tap(RecoveryCopy.Task.details, in: [.button]) {
            screen = "uncertain-outcomes"
            pause(1)
            snap("reviews-uncertain-outcomes")
            leaveSheet("Uncertain Outcomes")
        }
        screen = "reviews"

        // Deciding the rest, the quick way a person would, to reach the empty state.
        for decision in [
            RecoveryCopy.Held.askPebbleToFinish, RecoveryCopy.PausedWindow.done, AppCopy.Reviews.reject,
            AppCopy.Reviews.cancelRequest,
        ] where element(decision, in: [.button], timeout: 0.5) != nil {
            tap(decision, in: [.button], scroll: false)
            pause(2)
        }
        snap("reviews-after-deciding")
        if shows(AppCopy.Reviews.emptyTitle, timeout: 6) {
            snap("reviews-empty")
        } else {
            note("Reviews still lists items after deciding every one the tour could.", kind: .observation)
        }

        relaunch()
        openTab(AppCopy.Tabs.reviews)
        sweep("reviews", maxTaps: 20) { self.openTab(AppCopy.Tabs.reviews) }
    }
}
