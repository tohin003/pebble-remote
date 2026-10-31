import PebbleDesign
import XCTest

extension AuditSession {
    /// Chats, Pebble's sidebar on the phone: the list top to bottom, search, swipe actions, a long press, Recently
    /// Deleted, a new conversation before its first message (where it starts, the + menu, the first message), the
    /// places under Your Space, Connect a project and the Mac's folders; then every other control on the list.
    func tourChats() {
        launch(pace: 6)
        openTab(AppCopy.Tabs.chats)
        snap("chats-list")
        dumpTree("chats-list")
        // U-04 (round 2): the accessory shows only while a run works, and rows that scroll under it hide behind a hard
        // edge. What lies under it now, with the login fix working:
        if let accessory = accessoryFrame(containing: Demo.login) {
            let under = controls().filter { control in
                (control.type == .button || control.type == .cell) && control.frame != accessory
                    && control.frame.intersects(accessory)
            }
            let names = under.map(\.name).filter { !$0.isEmpty }
            note(
                "The accessory (y \(Int(accessory.minY))-\(Int(accessory.maxY))) lies over: "
                    + (names.isEmpty ? "no row." : names.joined(separator: "; ") + "."),
                kind: .observation)
        }
        var page = 0
        while page < 3, scrollDown() {
            page += 1
            snap("chats-list-page-\(page + 1)")
        }
        toRoot(of: AppCopy.Tabs.chats)
        scrollToTop()

        searchChats()
        swipeActions()

        // A long press on a conversation (lane Z, U-19): Pebble's sidebar actions in a menu (Rename, New conversation in
        // its project, Delete), with a small preview (the title and the last line). Delete asks first; Cancel keeps it.
        if let added = longPress(Demo.commits, in: [.button, .cell, .staticText]) {
            if added.isEmpty {
                note("A long press on a conversation in Chats shows nothing (no context menu).", kind: .observation)
            } else {
                snap("chats-long-press-menu-and-preview", audit: false)
                if pick(AppCopy.ChatMenu.delete, in: added) {
                    pause(0.6)
                    snap("chats-long-press-delete-question", audit: false)
                    answerSafely(AppCopy.Common.cancel)
                }
            }
        }
        closeOverlays()

        recentlyDeleted()
        waitingConversations()
        newConversationDraft()

        // Your Space: each place starts a new conversation there.
        for place in [AppCopy.Sidebar.companion, Demo.docsProject] {
            toRoot(of: AppCopy.Tabs.chats)
            if tap(AppCopy.Sidebar.newConversation(in: place), in: [.button]) {
                snap("chats-your-space-\(place)-opens-a-new-conversation")
                goBack()
            }
        }

        connectProjectFromChats()

        toRoot(of: AppCopy.Tabs.chats)
        sweep("chats", maxTaps: 22, avoid: [AppCopy.Chats.searchPrompt]) { self.toRoot(of: AppCopy.Tabs.chats) }
    }

    /// Search, and its keyboard (the person's P1: in Chats the keyboard wouldn't close). The keyboard must close on a
    /// swipe down without searching; then a search, then the system's Cancel or Close ends it, and the tab bar must be
    /// in reach again.
    private func searchChats() {
        screen = "chats-search"
        func openSearch() -> Bool {
            let field = app.searchFields.firstMatch
            if !field.waitForExistence(timeout: 2) || !field.isHittable {
                // Search sits above the list: a person pulls the list down to find it.
                scrollUp()
            }
            guard field.exists, field.isHittable else { return false }
            field.tap()
            return true
        }
        keyboardCheck("Chats search", shot: "chats-search", exit: .swipeDown, open: { openSearch() })
        guard openSearch() else {
            note("Couldn't find the search field on Chats.", kind: .missing)
            return
        }
        snap("chats-search-active", audit: false)
        app.typeText("dark")
        pause(1.5)
        snap("chats-search-dark")
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "zzz")
        pause(1.5)
        snap("chats-search-nothing-found")
        let leave = app.buttons.matching(
            NSPredicate(
                format: "(label == %@ OR label == %@) AND identifier != 'BackButton'", AppCopy.Common.cancel,
                AppCopy.Common.close)
        ).firstMatch
        if leave.exists, leave.isHittable {
            // Its word, read while it is there: the button goes with the search, and reading a gone element's label
            // stops the whole test (the 12:15 run lost the rest of Chats here, this note too).
            let word = leave.label
            tap(leave, named: "Search's \(word)")
            pause(0.6)
            snap("chats-search-ended", audit: false)
            if app.keyboards.firstMatch.exists {
                note("Keyboard: Search's \(word) left the keyboard up.", kind: .keyboardTrap)
                forceCloseKeyboard("Chats search")
            } else if let reach = chromeInReach() {
                note("Keyboard: Search's \(word) closed it; \(reach) can be tapped.", kind: .keyboard)
            } else {
                note("Keyboard: after Search's \(word), neither the tab bar nor Back can be tapped.", kind: .keyboardTrap)
            }
        } else {
            note("Search on Chats has no Cancel or Close.", kind: .observation)
            closeOverlays()
        }
        screen = "chats"
    }

    /// Swipe actions. The swipe's photo comes without an accessibility audit and the action is tapped at once: in both
    /// earlier runs Delete and Rename were gone by the time the tour tapped them. Rename's alert takes the keyboard:
    /// its Cancel must close it, and the tab bar must be in reach again.
    private func swipeActions() {
        screen = "chats"
        if swipeRow(Demo.weather, left: true) {
            snap("chats-swipe-left-a-finished-conversation", audit: false)
            if tap(AppCopy.Deleted.delete, in: [.button], timeout: 1, scroll: false) {
                pause(1)
                snap("chats-after-delete")
            }
        }
        toRoot(of: AppCopy.Tabs.chats)
        func openRename() -> Bool {
            guard swipeRow(Demo.readme, left: false) else { return false }
            snap("chats-swipe-right-a-conversation", audit: false)
            return tap(AppCopy.Chats.rename, in: [.button], timeout: 1, scroll: false)
        }
        keyboardCheck("Rename", shot: "chats-rename", exit: .button(AppCopy.Chats.cancel), open: { openRename() })
        closeOverlays()
        toRoot(of: AppCopy.Tabs.chats)
        if swipeRow(Demo.login, left: true) {
            snap("chats-swipe-left-a-working-conversation", audit: false)
        }
        // Back to the list with the tab button, not a swipe back, which can open the row (the re-check's test01).
        toRoot(of: AppCopy.Tabs.chats)
    }

    private func recentlyDeleted() {
        toRoot(of: AppCopy.Tabs.chats)
        guard tap(AppCopy.Deleted.title, in: [.button, .cell]) else { return }
        screen = "recently-deleted"
        snap("chats-recently-deleted")
        if swipeRow(Demo.weather, left: true) {
            snap("recently-deleted-swipe-left", audit: false)
            if tap(AppCopy.Deleted.deleteForGood, in: [.button], timeout: 1, scroll: false) {
                snap("recently-deleted-delete-for-good-question")
                closeOverlays()
            }
        }
        if tap(AppCopy.Deleted.restore, in: [.button]) {
            pause(1.5)
            snap("recently-deleted-after-restore")
        }
        goBack()
        screen = "chats"
    }

    /// The conversations that wait for the person (lane V's checks 2 and 7): each should open with its card's or
    /// question's top in view (U-11, U-25); a run waiting for review has no Pause or Stop in its bar, and its ⋯ menu
    /// keeps Pause (U-10).
    private func waitingConversations() {
        if openChat(Demo.readme) {
            pause(1)
            snap("chats-readme-opens-on-its-card")
            if let menu = openMenu(AppCopy.Conversation.more, in: [.button]) {
                snap("chats-readme-more-menu-while-waiting")
                closeMenu(menu)
            }
        }
        if openChat(Demo.emails) {
            pause(1)
            snap("chats-onboarding-opens-on-its-question")
        }
        toRoot(of: AppCopy.Tabs.chats)
    }

    /// "New conversation" (the toolbar's button): before its first message, its keyboard (a swipe down on the welcome
    /// closes it, and Back is in reach), then the first message; then the keyboard in that short conversation and in
    /// a long one (the login fix, finished by now).
    private func newConversationDraft() {
        toRoot(of: AppCopy.Tabs.chats)
        guard tap(AppCopy.Chats.newConversation, in: [.button]) else { return }
        screen = "draft"
        snap("draft-new-conversation")
        dumpTree("draft")
        if let menu = openMenu(AppCopy.Sidebar.newConversation(in: AppCopy.Sidebar.companion), in: [.button]) {
            snap("draft-where-menu", audit: false)
            if pick(Demo.webProject, in: menu) {
                pause(0.6)
                snap("draft-starts-in-a-project")
            }
        }
        if let menu = openMenu(AppCopy.AddContext.title, in: [.button]) {
            snap("draft-add-context-menu")
            closeMenu(menu)
        }
        keyboardCheck("a new conversation's composer", shot: "draft", exit: .swipeDown, open: { openComposer() })
        keyboardCheck("a new conversation's composer", shot: "draft", exit: .tapAbove, open: { openComposer() })
        if type("Draft the release notes for 2.0", into: AppCopy.Conversation.placeholder) {
            snap("draft-message-typed", audit: false)
            if tap(AppCopy.Conversation.send, in: [.button]) {
                pause(1.5)
                snap("draft-first-message-made-the-conversation")
                pause(5)
                snap("draft-reply-arrives")
                closeOverlays()
                keyboardCheck(
                    "a short conversation's composer", shot: "short-conversation", exit: .swipeDown, open: { openComposer() })
            }
        }
        if openChat(Demo.login) {
            keyboardCheck("a long conversation's composer", shot: "long-conversation", exit: .swipeDown, open: { openComposer() })
            keyboardCheck("a long conversation's composer", shot: "long-conversation", exit: .tapAbove, open: { openComposer() })
        }
        toRoot(of: AppCopy.Tabs.chats)
    }

    /// Connect a project from Chats: the projects, the Mac's folders, a folder inside, New Folder, then connecting
    /// one, which starts a new conversation there.
    private func connectProjectFromChats() {
        toRoot(of: AppCopy.Tabs.chats)
        guard tap(AppCopy.Sidebar.connectProject, in: [.button]) else { return }
        screen = "connect-project"
        snap("connect-project-sheet")
        dumpTree("connect-project")
        guard tap(AppCopy.ConnectProject.chooseFolder, in: [.button, .cell]) else {
            leaveSheet("Connect a project")
            return
        }
        pause(1)
        snap("connect-project-home-folder")
        if tap("Projects", in: [.button, .cell]) {
            pause(1)
            snap("connect-project-projects-folder")
            if tap("sketches", in: [.button, .cell]) {
                pause(1)
                snap("connect-project-a-folder-no-conversation-uses")
                if tap(AppCopy.ConnectProject.newFolder, in: [.button], timeout: 1, scroll: false) {
                    snap("connect-project-new-folder-alert")
                    closeAlert()
                }
                if tap(AppCopy.ConnectProject.connectThisFolder, in: [.button]) {
                    pause(1.5)
                    snap("connect-project-connected-starts-a-conversation")
                }
            }
        }
        closeOverlays()
        toRoot(of: AppCopy.Tabs.chats)
    }
}
