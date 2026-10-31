import PebbleDesign
import PebbleProtocol
import XCTest

extension AuditSession {
    /// The Pebble tab, as someone opening the app for the first time meets it: Pebble at work on the demo's login fix,
    /// what needs review, the Mac (Keep Awake and, since round 2, Mac Screen), Ask Pebble (the bar at the bottom) and
    /// its keyboard, the mode chip; the bottom accessory, which shows on Chats, not here; then every other control.
    ///
    /// Pace 10 keeps the login run working for the first steps (at pace 6 it had ended before Stop in the re-check's
    /// test01 rerun).
    func tourPebbleTab() {
        launch(pace: 10)
        snap("pebble-tab-pebble-working")
        dumpTree("pebble-tab")
        // Lane V: the Pebble tab shows the run itself, so the accessory isn't here any more (U-04, U-05).
        if accessoryFrame(containing: Demo.login) != nil {
            note("The bottom accessory still shows the live run on the Pebble tab.", kind: .observation)
        }

        // While the run is live: its row in Working Now, its swipe (Stop, red: U-18), the accessory on Chats, then Stop.
        if tap(Demo.login, in: [.button, .cell, .staticText]) {
            screen = "pebble-working-now"
            snap("pebble-working-now-opens-the-conversation")
            goBack()
        }
        screen = "pebble"
        if swipeRow(Demo.login, left: true) {
            snap("pebble-working-now-swipe-left")
        }
        // Back to the tab's own screen with the tab button, not a swipe back: in the 21:13 run the swipe back opened the
        // row's conversation, and the rest of this tour ran inside it.
        toRoot(of: AppCopy.Tabs.pebble)
        accessoryOnChats(opens: Demo.login, shot: "chats-accessory-opens-the-conversation")
        toRoot(of: AppCopy.Tabs.pebble)
        if backButton() != nil {
            note("The Pebble tab still shows a pushed screen after going to its root.", kind: .harness)
        }
        if tap(AppCopy.Conversation.stop, in: [.button]) {
            pause(2)
            snap("pebble-tab-after-stop")
        }

        // Nothing working now. Round 2 (lane V, U-04): the accessory shows only while a run works, so Chats has none now,
        // not even for the runs that wait for the person (Reviews and the rows show those).
        openTab(AppCopy.Tabs.chats)
        snap("chats-no-accessory-after-stop")
        if accessoryFrame(containing: Demo.readme) != nil || accessoryFrame(containing: Demo.emails) != nil {
            note("The bottom accessory still shows a run that waits for the person, after Stop.", kind: .observation)
        }
        toRoot(of: AppCopy.Tabs.pebble)
        screen = "pebble"
        scrollDown()
        snap("pebble-tab-scrolled")
        scrollToTop()
        touchThePebble()

        // The mode chip opens How Pebble Acts; each mode once, then back to Ask. Full access asks first: photographed,
        // then cancelled, never confirmed.
        if tap(where: Self.modeChip, named: "the mode chip") {
            screen = "mode-sheet"
            snap("pebble-mode-sheet")
            for mode in [PermissionMode.auto, .full, .ask] {
                guard tap(ModeCopy.for(mode).name, in: [.button, .cell]) else { continue }
                if mode == .full {
                    fullAccessQuestion("pebble-mode-sheet")
                    continue
                }
                pause(0.8)
                snap("pebble-mode-sheet-chose-\(mode.rawValue)")
            }
            if tap(AppCopy.Modes.whatEachModeAllows, in: [.button, .cell, .staticText]) {
                pause(0.6)
                snap("pebble-mode-sheet-what-each-mode-allows")
            }
            leaveSheet("How Pebble Acts")
        }
        screen = "pebble"

        if tap(AppCopy.Mac.keepAwake, in: [.switch, .toggle, .button]) {
            pause(1)
            snap("pebble-keep-awake-switched")
        }

        // Mac Screen, on the Pebble tab since round 2 (lane W, U-36). Never its Share: that sheet shows the person's
        // contacts.
        if tap(AppCopy.MacScreen.title, in: [.button, .cell, .link]) {
            screen = "mac-screen"
            pause(2)
            snap("pebble-mac-screen")
            if tap(AppCopy.MacScreen.refresh, in: [.button], scroll: false) {
                pause(2)
                snap("pebble-mac-screen-refreshed", audit: false)
            }
            goBack()
        }
        toRoot(of: AppCopy.Tabs.pebble)

        // What needs review ("4 items need your review") leads to the Reviews tab. (Before lane V's fix the bottom
        // accessory lay over this row and took the tap: U-04.)
        let waiting = NSPredicate(
            format: "label MATCHES %@ AND elementType == %@", "^[0-9]+ items? needs? your review.*",
            NSNumber(value: XCUIElement.ElementType.button.rawValue))
        if tap(where: waiting, named: "the waiting items row") {
            snap("pebble-needs-review-opens-reviews")
            openTab(AppCopy.Tabs.pebble)
        }

        // The person's P1: Ask Pebble's keyboard wouldn't close, and the tab bar was out of reach (the tab has no Back).
        // Three ways out, each from a fresh keyboard: Send with nothing typed, a swipe down, a tap on the list.
        askPebbleKeyboardChecks()

        // Ask Pebble, the bar at the bottom of the tab: the words start a new conversation. The keyboard's Send key
        // should send, and the field and its arrow should stay above the keyboard (U-12). From the tab's own screen: a
        // conversation's composer has the same placeholder.
        toRoot(of: AppCopy.Tabs.pebble)
        if type("Check that signing in works on Safari", into: AppCopy.Conversation.placeholder) {
            snap("pebble-ask-pebble-typed", audit: false)
            let arrow = element(AppCopy.Home.startConversation, in: [.button], timeout: 1)
            if arrow?.isHittable != true {
                note("“\(AppCopy.Home.startConversation)” sits under the keyboard.", kind: .notTappable)
            }
            var started = false
            let send = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] 'send'")).firstMatch
            if send.waitForExistence(timeout: 1) {
                started = tap(send, named: "the keyboard's Send")
            } else if let arrow, arrow.isHittable {
                note("The keyboard has no Send key; sent with the arrow.", kind: .observation)
                started = tap(arrow, named: AppCopy.Home.startConversation)
            }
            if started {
                pause(1)
                if backButton() == nil {
                    note("Sending from Ask Pebble didn't open a conversation.", kind: .noResponse)
                }
                screen = "pebble-ask-pebble"
                snap("pebble-ask-pebble-started-a-conversation")
                pause(4)
                snap("pebble-ask-pebble-reply")
                goBack()
            }
        }
        closeOverlays()

        pullToRefresh()
        toRoot(of: AppCopy.Tabs.pebble)
        sweep("pebble", maxTaps: 15) { self.toRoot(of: AppCopy.Tabs.pebble) }
    }

    /// Ask Pebble's keyboard closes without sending, three ways (lane V's round-2 check 1), and the tab bar is in reach
    /// after each.
    /// The companion answers a touch (the person, 2026-10-31): a tap makes a resting pebble happy, three quick taps make
    /// it celebrate; while Pebble works or waits for the person, a touch only turns its eyes. The same for the tab's own
    /// glyph in the tab bar (Pebble itself, no longer a smiley). The photos show which.
    private func touchThePebble() {
        let hero = app.cells.firstMatch
        guard hero.waitForExistence(timeout: 2), !hero.frame.isEmpty else {
            note("The Pebble tab's first row (the companion) wasn't there to touch.", kind: .missing)
            return
        }
        // The avatar sits at the row's leading end, 64 pt, centred on the row's height.
        let pebble = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: hero.frame.minX + 48, dy: hero.frame.midY))
        pebble.tap()
        pause(0.4)
        snap("pebble-companion-tapped", audit: false)
        pause(1.5)
        pebble.doubleTap()
        pebble.tap()
        pause(0.5)
        snap("pebble-companion-three-taps", audit: false)
        pause(2.5)

        let tab = app.tabBars.buttons[AppCopy.Tabs.pebble].firstMatch
        guard tab.exists, tab.isHittable else {
            note("The Pebble tab's button wasn't there to tap.", kind: .missing)
            return
        }
        tab.tap()
        pause(0.4)
        snap("pebble-tab-glyph-tapped", audit: false)
        pause(1.5)
        tab.doubleTap()
        tab.tap()
        pause(0.5)
        snap("pebble-tab-glyph-three-taps", audit: false)
        pause(2.5)
    }

    private func askPebbleKeyboardChecks() {
        func openAskPebble() -> Bool {
            guard let field = element(AppCopy.Conversation.placeholder, in: Self.fieldTypes, timeout: 2),
                field.isHittable
            else { return false }
            field.tap()
            return true
        }
        for exit in [KeyboardExit.emptySubmit, .swipeDown, .tapFirstCell] {
            toRoot(of: AppCopy.Tabs.pebble)
            scrollToTop()
            keyboardCheck("Ask Pebble", shot: "pebble-ask-pebble", exit: exit, open: { openAskPebble() })
        }
    }
}
