import PebbleDesign
import XCTest

extension AuditSession {
    /// A conversation while Pebble works (the menus that wait for it, the ⋯ menu, the title menu, guidance, the run
    /// bar), once it has finished (Jump to Latest, a long press on a message, model and effort, the + menu with each of
    /// its sheets and pickers), a finished and a Companion conversation; then every other control in a finished one.
    ///
    /// The menus that wait for Pebble come first: in the demo a run ends a few seconds after Resume, so in the
    /// re-check they were only seen after the run had ended. A menu's item is tapped before any accessibility audit (an
    /// audit takes seconds, and a menu can close meanwhile: U-53), so open menus are photographed without one.
    func tourConversation() {
        launch(pace: 6)
        guard openChat(Demo.login) else { return }
        // The run bar's Pause, then Resume (U-23), first: after the menus below the login run had already ended
        // ([046]). The demo ends a run within seconds of Resume, so a fresh demo follows for the menus while it works.
        if tap(AppCopy.Conversation.pause, in: [.button], scroll: false) {
            pause(1.5)
            snap("conversation-paused")
            if tap(AppCopy.Conversation.resume, in: [.button], scroll: false) {
                pause(1)
                snap("conversation-resumed")
            }
        }
        relaunch()
        guard openChat(Demo.login) else { return }
        let live = screen
        snap("conversation-working")
        dumpTree("conversation-working")

        // While Pebble works, model, effort and the + menu open, their choices greyed under a header that says why
        // (lane V, U-09). The model menu stays open 5 s first (U-53: it closed by itself in the re-check). Each is
        // photographed and closed without choosing.
        let model = currentLabel(of: "\(AppCopy.Control.model),")
        if let menu = openMenu("\(AppCopy.Control.model),", in: [.button]) {
            pause(5)
            if menuStillOpen(menu, besides: model) {
                note("The model menu stayed open for 5 s while Pebble works (U-53).", kind: .observation)
            } else {
                note("The model menu closed by itself within 5 s while Pebble works (U-53).", kind: .observation)
            }
            snap("conversation-model-menu-while-working-after-5-s", audit: false)
            closeMenu(menu)
        }
        screen = live
        if let menu = openMenu(AppCopy.AddContext.title, in: [.button]) {
            snap("conversation-add-context-menu-while-working", audit: false)
            closeMenu(menu)
        }
        screen = live

        // The ⋯ menu while Pebble works.
        if let menu = openMenu(AppCopy.Conversation.more, in: [.button]) {
            snap("conversation-more-menu-while-working", audit: false)
            // "Details" (lane Y: once "What Pebble did"), during the run (U-22).
            if pick(AppCopy.Details.title, in: menu) {
                pause(1)
                snap("conversation-details-while-working")
                leaveSheet("Details")
            }
        }
        screen = live

        // The title is a menu: where the conversation is.
        if let menu = openTitleMenu(Demo.login) {
            snap("conversation-title-menu", audit: false)
            if pick(AppCopy.Sidebar.newConversation(in: Demo.webProject), in: menu) {
                snap("conversation-title-menu-new-conversation-here")
                goBack()
            }
        }
        screen = live
        if let menu = openTitleMenu(Demo.login), pick(AppCopy.Sidebar.connectProject, in: menu) {
            pause(0.8)
            snap("conversation-title-menu-connect-a-project")
            leaveSheet("Connect a project")
        }
        screen = live

        // Telling Pebble something while it works (when the run hasn't finished yet).
        if element(AppCopy.Conversation.placeholderWhileWorking, in: Self.fieldTypes, timeout: 0.5) != nil,
            type("Also check Safari's private windows", into: AppCopy.Conversation.placeholderWhileWorking, scroll: false)
        {
            if tap(AppCopy.Conversation.send, in: [.button], scroll: false) {
                pause(1)
                snap("conversation-guidance-sent-while-working")
            }
        }
        closeOverlays()

        // The reply finishes.
        if !wait(for: AppCopy.Conversation.stop, gone: true, timeout: 100) {
            note("The demo's login run was still working after 100 s.", kind: .harness)
        }
        pause(1)
        snap("conversation-finished")
        scrollUp()
        snap("conversation-finished-top", audit: false)
        // Jump to Latest shows only away from the end of a transcript taller than the screen, in the bottom bar since
        // round 2; it brings the person back (U-15, U-49).
        if let jump = element(AppCopy.Conversation.jumpToLatest, in: [.button], timeout: 1) {
            if tap(jump, named: AppCopy.Conversation.jumpToLatest) {
                pause(1)
                snap("conversation-jumped-to-latest", audit: false)
                if element(AppCopy.Conversation.jumpToLatest, in: [.button], timeout: 0.5) != nil {
                    note("“\(AppCopy.Conversation.jumpToLatest)” still shows at the end.", kind: .observation)
                }
            }
        } else {
            note("“\(AppCopy.Conversation.jumpToLatest)” didn't show after scrolling up.", kind: .observation)
        }

        // A long press on a message: Pebble's window has Copy, Edit, Retry, Undo on each message.
        if let added = longPress("Signing in on Safari", in: [.staticText, .other, .cell]) {
            if added.isEmpty {
                note("A long press on a message shows nothing (no Copy, Retry or Edit).", kind: .observation)
                snap("conversation-long-press-a-message", audit: false)
            } else {
                snap("conversation-message-menu")
                closeMenu(added)
            }
        }
        closeOverlays()

        modelAndEffort()
        addContextMenu()

        // A finished conversation and what Pebble did in it; then its ⋯ › Rename, whose alert takes the keyboard: its
        // Cancel must close it without renaming, and Back must be in reach.
        if openChat(Demo.commits) {
            snap("conversation-finished-with-details")
            if let menu = openMenu(AppCopy.Conversation.more, in: [.button]) {
                snap("conversation-more-menu-finished", audit: false)
                // "Details" after the run too (lane Y, U-22: once only Rename was left).
                if pick(AppCopy.Details.title, in: menu) {
                    pause(1)
                    snap("conversation-details-after-the-run")
                    leaveSheet("Details")
                }
            }
            func openRename() -> Bool {
                guard let menu = openMenu(AppCopy.Conversation.more, in: [.button]) else { return false }
                return pick(AppCopy.Chats.rename, in: menu)
            }
            keyboardCheck(
                "Rename (the ⋯ menu)", shot: "conversation-rename", exit: .button(AppCopy.Chats.cancel), open: { openRename() })
            closeOverlays()
            messageActions()
            slashCommands()
        }
        // The Companion conversation; Retry on its reply (lane Z: the same question again as a new message, fine in the
        // demo).
        if openChat(Demo.weather) {
            snap("conversation-in-companion")
            sourceMarker()
            if let menu = longPress(containing: "Saturday: sunny"), !menu.isEmpty {
                snap("conversation-companion-reply-menu", audit: false)
                if pick(AppCopy.MessageMenu.retry, in: menu) {
                    pause(3)
                    snap("conversation-retried")
                }
            }
            closeOverlays()
        }

        // The sweep, in a finished conversation.
        openChat(Demo.commits)
        sweep("conversation-finished", maxTaps: 20) { self.openChat(Demo.commits) }
        systemPickers()
    }

    /// A reply's source marker (TR-10) in the weather reply: S2's address isn't https, so the phone names the source
    /// instead of opening it. S1 would leave for Safari and is never tapped.
    private func sourceMarker() {
        guard let marker = find("S2", in: [.link], timeout: 2, scroll: false) else {
            note("The source marker S2 isn't an element of its own here; VoiceOver reaches it through the Links rotor.",
                kind: .observation)
            return
        }
        guard tap(marker, named: "S2") else { return }
        pause(1.5)
        snap("conversation-source-named", audit: false)
        let named = NSPredicate(format: "label CONTAINS %@", "Lisbon weekend outlook")
        if !app.descendants(matching: .any).matching(named).firstMatch.waitForExistence(timeout: 2) {
            note("Tapping the source marker S2 showed no words about it.", kind: .noResponse)
        }
        closeOverlays()
    }

    /// Message actions on a long press (lane Z). The reply's menu (Copy, Copy Code, Open Link, Retry) is photographed
    /// and closed: never Copy, Copy Code or Open Link, which write the person's clipboard or leave for Safari. The
    /// person's own message (VoiceOver reads it "You: …") offers Edit, whose sheet is cancelled, after its keyboard
    /// closes with a swipe (Cancel stays in reach): nothing is sent.
    private func messageActions() {
        if let menu = longPress(containing: "This week in pebble-web") {
            if menu.isEmpty {
                note("A long press on Pebble's reply shows no menu.", kind: .observation)
            } else {
                snap("conversation-reply-menu", audit: false)
                closeMenu(menu)
            }
        }
        closeOverlays()
        func openEdit() -> Bool {
            guard let menu = longPress(containing: AppCopy.Accessibility.fromYou("Summarize this week's commits")),
                !menu.isEmpty
            else { return false }
            snap("conversation-your-message-menu", audit: false)
            guard pick(AppCopy.MessageMenu.edit, in: menu) else { return false }
            pause(1)
            return app.keyboards.firstMatch.exists || openField(AppCopy.MessageMenu.editField)
        }
        keyboardCheck("Edit's message", shot: "conversation-edit", exit: .swipeDown, inSheet: true, open: { openEdit() })
        if shows(AppCopy.MessageMenu.editTitle, timeout: 0.5) {
            leaveSheet("Edit Your Message")
        }
        closeOverlays()
    }

    /// The "/" commands (lane Z): "/" lists Pebble's commands above the field, "/mem" filters them, and choosing
    /// "/memory" only fills the field (nothing is sent); "/zzz" says no command matches. The field is cleared after each,
    /// and Return in the empty field closes the keyboard.
    private func slashCommands() {
        guard openComposer() else {
            note("Couldn't open the message field for the / commands.", kind: .missing)
            return
        }
        let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12)
        app.typeText("/")
        pause(1.2)
        snap("conversation-slash-list", audit: false)
        app.typeText("mem")
        pause(1)
        snap("conversation-slash-mem", audit: false)
        if tap(AppCopy.Slash.command("memory"), in: [.button], timeout: 2, scroll: false) {
            pause(0.8)
            snap("conversation-slash-memory-chosen", audit: false)
            // The field by its name and place, not its placeholder, which goes once the field holds words ([075]).
            let value = composerField()?.value as? String ?? ""
            note(
                value.hasPrefix(AppCopy.Slash.command("memory"))
                    ? "Choosing /memory filled the field (“\(value)”); nothing was sent."
                    : "After choosing /memory the field reads “\(value)”.",
                kind: .observation)
        }
        app.typeText(clear)
        app.typeText("/zzz")
        pause(1)
        snap("conversation-slash-no-match", audit: false)
        if !shows(AppCopy.Slash.noMatch, timeout: 1) {
            note("“/zzz” didn't say “\(AppCopy.Slash.noMatch)”.", kind: .observation)
        }
        app.typeText(clear)
        let pressed = perform(.emptySubmit)
        pause(0.8)
        if !pressed {
            note("Keyboard: Return in the empty message field wasn't tested: there was nothing to press.", kind: .observation)
            forceCloseKeyboard("the message field")
        } else if app.keyboards.firstMatch.exists {
            note("Keyboard: Return in the empty message field didn't close it.", kind: .keyboardTrap)
            forceCloseKeyboard("the message field")
        } else {
            note("Keyboard: Return in the empty message field closed it, nothing sent.", kind: .keyboard)
        }
    }

    /// "Attach a file" opens the system's Files and Photos pickers, from a fresh demo (so no run of the sweep's keeps
    /// the + menu's items waiting). They are never photographed: they show the person's own files and photos. What
    /// happened is a finding: whether each opened, and whether its Cancel closed it. Photos goes last, because the
    /// person's Photos app is locked with Face ID, whose system screen the app can't close.
    private func systemPickers() {
        relaunch()
        for (item, name) in [(AppCopy.AddContext.files, "files"), (AppCopy.AddContext.photoLibrary, "photo-library")] {
            guard openChat(Demo.commits) else { continue }
            let here = screen
            guard let menu = openMenu(AppCopy.AddContext.title, in: [.button]),
                pick(AppCopy.AddContext.attachFile, in: menu)
            else { continue }
            pause(0.6)
            snap("conversation-attach-a-file-\(name)-submenu", audit: false)
            if tap(item, in: [.button, .menuItem, .cell], timeout: 2, scroll: false) {
                pause(2.5)
                screen = name
                let covered = element(AppCopy.AddContext.title, in: [.button], timeout: 0.5)?.isHittable != true
                note(
                    covered
                        ? "The \(name) picker opened (not photographed: it shows the person's own items)."
                        : "Choosing \(name) showed no picker over the conversation.",
                    kind: .observation)
                closeSheet()
                pause(1)
                if element(AppCopy.AddContext.title, in: [.button], timeout: 1)?.isHittable != true {
                    note("The \(name) picker stayed open (it runs outside the app); relaunched.", kind: .observation)
                    relaunch()
                } else if covered {
                    note("The \(name) picker closed with its own Cancel.", kind: .observation)
                    snap("conversation-after-the-\(name)-picker", audit: false)
                }
            }
            screen = here
        }
    }

    /// Model and effort, once Pebble has finished: each a menu of Pebble's choices.
    private func modelAndEffort() {
        // The model menu stays open 5 s first, as a person reads it (U-53), then a pick.
        chooseAnother("\(AppCopy.Control.model),", shot: "conversation-model", named: "The model menu", waitFirst: 5)
        chooseAnother("\(AppCopy.Control.effort),", shot: "conversation-effort", named: "The effort menu")
        closeOverlays()
    }

    /// The composer's + (Pebble's "Add context") and each of its items, in a conversation that isn't working.
    private func addContextMenu() {
        let here = screen
        if let menu = openMenu(AppCopy.AddContext.title, in: [.button]) {
            snap("conversation-add-context-menu", audit: false)
            if pick(AppCopy.AddContext.terminalCommand, in: menu) {
                screen = "terminal-command"
                pause(0.8)
                snap("terminal-command-sheet")
                // Return in the empty command closes the keyboard (lane W's keyboard rule); the sheet's Cancel is in reach.
                keyboardCheck(
                    "the terminal command", shot: "terminal-command", exit: .emptySubmit, inSheet: true,
                    open: { openField(AppCopy.TerminalCommand.placeholder) })
                if type("git status --short", into: AppCopy.TerminalCommand.placeholder) {
                    snap("terminal-command-typed", audit: false)
                    if tap(AppCopy.TerminalCommand.review, in: [.button]) {
                        pause(2)
                        snap("terminal-command-proposed")
                    }
                }
                closeOverlays()
            }
        }
        if let menu = openMenu(AppCopy.AddContext.title, in: [.button]), pick(AppCopy.AddContext.readWebSource, in: menu) {
            screen = "web-source"
            pause(0.8)
            snap("web-source-sheet")
            if type("https://docs.example.com/guide", into: AppCopy.WebSource.placeholder) {
                if tap(AppCopy.WebSource.attach, in: [.button]) {
                    pause(2)
                    screen = here
                    snap("web-source-attached-waits-for-the-next-message")
                    if tap(AppCopy.Control.remove, in: [.button], timeout: 1, scroll: false) {
                        snap("web-source-removed", audit: false)
                    }
                }
            }
            closeOverlays()
        }
        screen = here
        if let menu = openMenu(AppCopy.AddContext.title, in: [.button]), pick(AppCopy.AddContext.connectProject, in: menu) {
            pause(0.8)
            snap("conversation-add-context-connect-a-project")
            leaveSheet("Connect a project")
        }
        screen = here
        closeOverlays()
    }
}

// MARK: - Pebble's views (lane G, contract 3.12)

// In this file until the project is generated again: a new file in UIAudit/ needs XcodeGen.
extension AuditSession {
    /// The demo's views (DemoViews), by the titles their cards show.
    enum ViewTitle {
        static let diagram = "How a request reaches the app"
        static let plan = "The fix, step by step"
        static let table = "Commits by author"
        static let chart = "Commits per day"
        static let dashboard = "This week in pebble-web"
        static let evidence = "Where the numbers came from"
        static let timeline = "The week, day by day"
        static let quiz = "What's new in 2.0"
        static let appDemo = "Onboarding screens"
        static let weather = "Lisbon this weekend"
        static let page = "Docs home page preview"
        static let form = "Choose the preview's port"
    }

    /// The demo's own words around the views: the form's fields (DemoViews.portFields), the reply Pebble goes on with
    /// once it has the answers (DemoClient.deployReply), the login plan's first step, the app demo's button and heading.
    enum ViewWords {
        static let port = "5173, Vite's usual port"
        static let sharePlaceholder = "Names or a team"
        static let share = "The web team"
        static let replyStart = "Thanks. In the demo"
        static let firstPlanStep = "Read the session code"
        static let firstFileRead = "src/auth/session.ts"
        static let demoButton = "Continue"
        static let demoHeading = "Welcome to Pebble"
        static let firstNamePlaceholder = "Sam"
        /// Lane Q: the right choices of the demo's quiz, "What's new in 2.0" (DemoViews, DemoQuizzes' key).
        static let quizFirstChoice = "npm run dev"
        static let quizSecondChoice = "A sidebar in the app"
    }

    /// Pebble's views (lane G, `docs/reviews/views-2026-10-31-G.md`), from a fresh demo at pace 3, so the login run
    /// works for about 40 s:
    /// - **The work view:** in the login conversation while Pebble works, the plan line ("Working · 0 of 4 steps")
    ///   above the run's first card, its steps a tap away; once the run has finished, its three cards, one opened and
    ///   closed again.
    /// - **Every view card:** opened full screen (a form in its sheet), photographed, closed with Done. Their own
    ///   controls are used: Diagram as text, Chart data, Refresh Data, the app demo's Continue, Previous Screen and
    ///   Restart Demo, and its First name field's keyboard. The quiz is taken (lane Q): Start quiz, a choice, Next, a
    ///   choice, Submit answers, its score, Share result with Pebble. "Open on Your Mac" is only photographed.
    /// - **The waiting form:** a message in "Deploy the preview build" makes Pebble ask with "Pebble's form":
    ///   - its row on Reviews, where Answer… opens it and Cancel sends nothing;
    ///   - in the conversation, Answer…, a port chosen, the text field's Return (it closes the keyboard and sends
    ///     nothing), Submit answers, and Pebble's reply going on.
    /// - **Looks:** the two charts in the other appearance, and the cards at the largest text size, each from a fresh
    ///   demo.
    ///
    /// No sweep: the tour taps only what a person would to see each view.
    func tourViews() {
        launch(pace: 3)
        workViewWhileWorking()
        commitsViews()
        workViewFinished()
        otherViews()
        waitingForm()
        launch(pace: 3, look: Look.otherAppearance)
        chartsInThisLook()
        launch(pace: 3, look: .largestText)
        cardsAtTheLargestSize()
    }

    /// The login conversation while Pebble works: the plan line must stand above the run's first card; a tap shows the
    /// plan's steps, a second hides them.
    private func workViewWhileWorking() {
        guard openChat(Demo.login) else { return }
        let firstCard = app.descendants(matching: .any).matching(
            NSCompoundPredicate(
                orPredicateWithSubpredicates: [(1, 0), (1, 1), (2, 1)].map { counts in
                    NSPredicate(
                        format: "label BEGINSWITH %@", AppCopy.Views.explored(reads: counts.0, searches: counts.1))
                })
        ).firstMatch
        let planLines = app.descendants(matching: .any).matching(
            NSCompoundPredicate(
                orPredicateWithSubpredicates: (0...4).map { done in
                    NSPredicate(format: "label CONTAINS %@", AppCopy.Views.planSteps(done: done, total: 4))
                }))
        guard firstCard.waitForExistence(timeout: 20) else {
            note("While Pebble works, the login run showed no card within 20 s (“Read 1 file” …).", kind: .missing)
            snap("login-no-work-view", audit: false)
            return
        }
        guard planLines.firstMatch.waitForExistence(timeout: 3) else {
            note("While Pebble works, the login conversation shows no plan line (“Working · N of 4 steps”).", kind: .missing)
            snap("login-work-view-without-a-plan-line", audit: false)
            return
        }
        // Read both before the photo: its accessibility audit takes seconds, and the demo's run can end meanwhile and take
        // the plan line away (a vanished element's label stops the whole test: the 12:15 run lost Views, the quiz too).
        let cardTop = firstCard.frame.minY
        let cardWords = firstCard.label
        let lines = (0..<min(planLines.count, 6)).map { planLines.element(boundBy: $0) }.filter { $0.exists }
        let above = lines.first(where: { $0.frame.maxY <= cardTop + 4 })
        let lineWords = (above ?? lines.first).map(\.label) ?? ""
        snap("login-work-view-while-working")
        guard let line = above else {
            note(
                "While Pebble works, the plan line (“\(lineWords)”) is NOT above the run's first card (“\(cardWords)”).",
                kind: .observation)
            return
        }
        note(
            "While Pebble works, the plan line (“\(lineWords)”) shows above the run's first card (“\(cardWords)”).",
            kind: .observation)
        // The plan's steps, a tap away (display only).
        guard tap(line, named: "the plan line") else { return }
        pause(0.5)
        snap("login-plan-steps", audit: false)
        if !shows(ViewWords.firstPlanStep, timeout: 1) {
            note("A tap on the plan line didn't show the plan's steps (“\(ViewWords.firstPlanStep)” …).", kind: .noResponse)
        }
        if line.exists, tap(line, named: "the plan line") {
            pause(0.5)
            if shows(ViewWords.firstPlanStep) {
                note("A second tap on the plan line left its steps showing.", kind: .observation)
            }
        }
    }

    /// The login conversation once its run has finished: its three cards (reads and searches, the edit, the tests),
    /// the first opened and closed again; then the two views the run drew.
    private func workViewFinished() {
        guard openChat(Demo.login) else { return }
        if !wait(for: AppCopy.Conversation.stop, gone: true, timeout: 60) {
            note("The login run was still working after 60 s.", kind: .harness)
        }
        pause(1)
        snap("login-work-view-finished")
        let explored = AppCopy.Views.explored(reads: 2, searches: 1)
        let cards = [explored, AppCopy.Views.changedFiles(1), AppCopy.Views.tests(recipe: "npm-test")]
        let missing = cards.filter { find($0, in: Self.controlTypes + Self.textTypes, timeout: 1) == nil }
        if missing.isEmpty {
            note("The finished login run shows its three cards: \(cards.joined(separator: "; ")).", kind: .observation)
        } else {
            note("The finished login run doesn't show the card(s): \(missing.joined(separator: "; ")).", kind: .missing)
        }
        if let card = find(explored, in: Self.controlTypes + Self.textTypes, timeout: 1), tap(card, named: explored) {
            pause(0.6)
            snap("login-work-card-open")
            if shows(ViewWords.firstFileRead, timeout: 1) {
                note("A tap on “\(explored)” showed what it did (“\(ViewWords.firstFileRead)” …).", kind: .observation)
            } else {
                note("A tap on “\(explored)” showed nothing more.", kind: .noResponse)
            }
            if let again = find(explored, in: Self.controlTypes + Self.textTypes, timeout: 1), tap(again, named: explored) {
                pause(0.6)
                snap("login-work-card-closed", audit: false)
                if shows(ViewWords.firstFileRead) {
                    note("A second tap on “\(explored)” left its details showing.", kind: .observation)
                }
            }
        }
        visitView(ViewTitle.diagram) {
            if tap(AppCopy.Views.diagramAsText, in: [.button, .staticText, .other]) {
                pause(0.5)
                snap("\(screen)-as-text", audit: false)
            }
        }
        visitView(ViewTitle.plan)
    }

    /// "Summarize this week's commits": a table, a chart, a live dashboard, evidence, and a kind this version can't
    /// draw.
    private func commitsViews() {
        guard openChat(Demo.commits) else { return }
        snap("commits-view-cards")
        visitView(ViewTitle.table) { tableRevisionsStopAndExport() }  // lane T
        visitView(ViewTitle.chart) { chartData() }
        visitView(ViewTitle.dashboard) { refreshData() }
        visitView(ViewTitle.evidence)
        visitView(ViewTitle.timeline) {
            if shows(AppCopy.Views.updateTheApp, timeout: 1) {
                note("“\(ViewTitle.timeline)” (a kind this version can't draw) says “\(AppCopy.Views.updateTheApp)”.",
                    kind: .observation)
            } else {
                note("“\(ViewTitle.timeline)” doesn't say “\(AppCopy.Views.updateTheApp)”.", kind: .missing)
            }
        }
    }

    /// Lane T: the table's ⋯ menu (CV-02, CV-08, CV-09, DT-26 to DT-31):
    /// - Revision: its first revision, read-only ("Earlier version 1"), then back with "Current · revision 2";
    /// - Stop view: the question is photographed and declined with Cancel (never stopped);
    /// - Export…: CSV chosen, Preview export, Create file (photographed while Pebble makes it, never cancelled), the
    ///   verdict with its checks, Delete Pebble's copy asked then cancelled, the "On your Mac" Save row, and Earlier
    ///   files with one record opened. No Share sheet exists here, and none is opened.
    private func tableRevisionsStopAndExport() {
        typealias H = AppCopy.ViewHistory
        typealias X = AppCopy.Exports
        if let menu = openMenu(H.more, in: [.button]) {
            snap("view-table-more-menu", audit: false)
            if pick(H.revision, in: menu), tap(H.earlier(1, status: "ready"), in: [.button], timeout: 2) {
                pause(1)
                snap("view-table-earlier-revision")
                if shows(H.earlierVersion(1), timeout: 1) {
                    note("The table's first revision shows read-only as “\(H.earlierVersion(1))”.", kind: .observation)
                } else {
                    note("The table's earlier revision doesn't say “\(H.earlierVersion(1))”.", kind: .missing)
                }
                if tap(H.current(2), in: [.button], timeout: 2) { pause(0.8) }
            }
        }
        if let menu = openMenu(H.more, in: [.button]), pick(H.stop, in: menu) {
            pause(0.8)
            snap("view-table-stop-question", audit: false)
            answerSafely(AppCopy.Common.cancel)
        }
        guard let menu = openMenu(H.more, in: [.button]), pick(H.export, in: menu) else { return }
        pause(1)
        snap("view-table-export")
        tap(X.formatName("csv"), in: [.button, .cell], timeout: 2)
        guard tap(X.preview, in: [.button], timeout: 2), wait(for: X.previewReady, timeout: 8) else {
            note("Export: Preview export showed no “\(X.previewReady)”.", kind: .missing)
            goBack()
            return
        }
        snap("view-table-export-preview", audit: false)
        if tap(X.createFile, in: [.button], timeout: 2) {
            pause(1)
            snap("view-table-export-creating", audit: false)
            if wait(for: X.verdict("verified", format: "csv"), timeout: 15) {
                snap("view-table-export-verified")
                scrollDown()
                askThenDecline(X.deleteCopy, shot: "view-table-export-delete")
                snap("view-table-export-save-on-mac", audit: false)
            } else {
                note("Export: Create file showed no verdict within 15 s.", kind: .missing)
            }
        }
        if tap(X.earlierFiles, in: [.button, .cell], timeout: 2) {
            pause(1)
            snap("view-table-export-earlier-files")
            if tap(ViewTitle.table, in: [.button, .cell], timeout: 2) {
                pause(1)
                snap("view-table-export-record")
                goBack()
            }
            goBack()
        }
        goBack()
    }

    /// The quiz, the app demo, the weather chart and the page that only the Mac draws.
    private func otherViews() {
        if openChat(Demo.readme) {
            visitView(ViewTitle.quiz) { takeQuiz() }
        }
        if openChat(Demo.emails) {
            visitView(ViewTitle.appDemo) { appDemo() }
            appDemoFeedback()
        }
        if openChat(Demo.weather) {
            visitView(ViewTitle.weather) { chartData() }
        }
        if openChat(Demo.site) {
            visitView(ViewTitle.page) { onlyOnTheMac(AppCopy.Views.onYourMac, in: ViewTitle.page) }
        }
    }

    /// "Deploy the preview build": its answered form opens read-only. A message makes Pebble ask with a new form, which
    /// waits in the conversation and on Reviews until it is answered (either place's Answer… opens it).
    private func waitingForm() {
        guard openChat(Demo.deploy) else { return }
        let here = screen
        visitView(ViewTitle.form) {
            if element(AppCopy.Views.submitAnswers, in: [.button], timeout: 0.5) != nil {
                note("The answered form “\(ViewTitle.form)” offers “\(AppCopy.Views.submitAnswers)”.", kind: .observation)
            } else {
                note("The answered form “\(ViewTitle.form)” opens read-only, with Done.", kind: .observation)
            }
        }
        guard type("Can you try another port?", into: AppCopy.Conversation.placeholder, scroll: false),
            tap(AppCopy.Conversation.send, in: [.button], scroll: false)
        else { return }
        guard wait(for: AppCopy.Views.pebblesForm, timeout: 25) else {
            note("A message in “\(Demo.deploy)” brought no “\(AppCopy.Views.pebblesForm)” within 25 s.", kind: .missing)
            snap("deploy-no-form", audit: false)
            return
        }
        hideKeyboard()
        pause(1)
        snap("deploy-form-waiting")

        // Its row on Reviews; Answer… there opens the form, whose Cancel sends nothing.
        if openTab(AppCopy.Tabs.reviews) {
            if find(AppCopy.Views.pebblesForm, in: Self.textTypes + [.cell], timeout: 3) != nil {
                snap("reviews-form-row")
                if openWaitingForm("on Reviews") {
                    snap("reviews-form-sheet", audit: false)
                    cancelForm("opened from Reviews")
                    if element(AppCopy.Views.answerForm, in: [.button], timeout: 2) != nil {
                        note("The form's Cancel sent nothing: it still waits on Reviews.", kind: .observation)
                    } else {
                        note("After the form's Cancel, Reviews no longer offers “\(AppCopy.Views.answerForm)”.",
                            kind: .observation)
                    }
                }
            } else {
                note("While the form waits, Reviews shows no “\(AppCopy.Views.pebblesForm)” row.", kind: .missing)
            }
        }

        // In the conversation: a port, the text field's Return, then Submit answers.
        guard openChat(Demo.deploy), openWaitingForm("in the conversation") else { return }
        screen = "form"
        snap("deploy-form-sheet")
        tap(ViewWords.port, in: [.button, .cell, .staticText])
        let closed = keyboardCheck(
            "the form's text field", shot: "deploy-form-text", exit: .typedReturn, inSheet: true,
            open: { type(ViewWords.share, into: ViewWords.sharePlaceholder) })
        guard formIsOpen(timeout: 1) else {
            // Only when Return itself took the form away: a keyboard that stayed was closed by force, which may cancel.
            if closed {
                let sent = replyGoesOn(timeout: 5)
                note(
                    "Keyboard: Return in the form's text field closed the form"
                        + (sent ? " and SENT the answers." : " (nothing sent)."),
                    kind: .observation)
            }
            screen = here
            return
        }
        if closed {
            note("Keyboard: Return in the form's text field sent nothing; the form stayed open.", kind: .keyboard)
        }
        snap("deploy-form-complete", audit: false)
        guard let submit = element(AppCopy.Views.submitAnswers, in: [.button], timeout: 1), submit.isEnabled else {
            note("With a port chosen and words written, “\(AppCopy.Views.submitAnswers)” is missing or dimmed.",
                kind: .disabled)
            cancelForm("in the conversation")
            screen = here
            return
        }
        tap(submit, named: AppCopy.Views.submitAnswers)
        if !app.navigationBars.buttons[AppCopy.Views.cancel].firstMatch.waitForNonExistence(timeout: 8) {
            note("The form stayed open 8 s after “\(AppCopy.Views.submitAnswers)”.", kind: .stuck)
            snap("deploy-form-after-submit", audit: false)
            cancelForm("after Submit answers")
        }
        screen = here
        if replyGoesOn(timeout: 20) {
            pause(1.5)
            snap("deploy-form-answered-reply-goes-on")
            note("After “\(AppCopy.Views.submitAnswers)”, Pebble's reply went on (“\(ViewWords.replyStart) …”).",
                kind: .observation)
        } else {
            note("After “\(AppCopy.Views.submitAnswers)”, Pebble's reply didn't go on within 20 s.", kind: .noResponse)
            snap("deploy-form-answered-no-reply", audit: false)
        }
        if element(AppCopy.Views.answerForm, in: [.button], timeout: 0.5) != nil {
            note("After the answers, the conversation still offers “\(AppCopy.Views.answerForm)”.", kind: .observation)
        }
    }

    /// The two charts in the look the app has now: the other appearance, from a fresh demo ("-light" or "-dark" in
    /// the photos' names).
    private func chartsInThisLook() {
        if openChat(Demo.commits) {
            visitView(ViewTitle.chart) { chartData() }
        }
        if openChat(Demo.weather) {
            visitView(ViewTitle.weather) { chartData() }
        }
    }

    /// At the largest text size a card's line stacks its parts (lane G's WorkCardLine). The line is one element, so the
    /// photo shows the stacking; its size is recorded.
    private func cardsAtTheLargestSize() {
        guard openChat(Demo.login) else { return }
        let changed = AppCopy.Views.changedFiles(1)
        if let card = find(changed, in: Self.controlTypes + Self.textTypes, timeout: 25) {
            pause(0.5)
            let frame = card.frame
            let words = card.label
            snap("login-work-cards")
            note(
                "At the largest size, the card “\(words)” is \(Int(frame.width))×\(Int(frame.height)) pt; "
                    + "the photo shows whether its parts stack.",
                kind: .observation)
        } else {
            note("At the largest size, the login run's card “\(changed)” wasn't found.", kind: .missing)
        }
        if find(ViewTitle.diagram, in: [.button], timeout: 2) != nil {
            snap("login-view-card", audit: false)
        }
    }

    // MARK: Moving through views

    /// Opens the view card titled `title` (full screen, or a form in its sheet), photographs it, does `inside`, and
    /// closes it with its Done. Returns whether it opened.
    @discardableResult
    private func visitView(_ title: String, inside: () -> Void = {}) -> Bool {
        let here = screen
        defer { screen = here }
        guard let card = find(title, in: [.button], timeout: 3) else {
            note("The view card “\(title)” isn't in the conversation.", kind: .missing)
            return false
        }
        guard tap(card, named: title) else { return false }
        guard app.navigationBars.buttons[AppCopy.Views.close].firstMatch.waitForExistence(timeout: 4) else {
            note("“\(title)” didn't open (no “\(AppCopy.Views.close)” in a bar).", kind: .noResponse)
            snap("view-\(Self.slug(title))-did-not-open", audit: false)
            closeOverlays()
            return false
        }
        screen = "view-" + Self.slug(title)
        pause(0.8)  // the view is read again as it opens
        snap(screen)
        inside()
        closeView(title)
        return true
    }

    /// Closes a view with its Done and checks that it went.
    private func closeView(_ title: String) {
        let done = app.navigationBars.buttons[AppCopy.Views.close].firstMatch
        if done.exists, done.isHittable {
            done.tap()
            pause(0.8)
        } else {
            note("“\(title)” has no “\(AppCopy.Views.close)” in reach.", kind: .missing)
            closeOverlays()
        }
        if app.navigationBars.buttons[AppCopy.Views.close].firstMatch.exists {
            note("“\(AppCopy.Views.close)” didn't close “\(title)”.", kind: .stuck)
            closeOverlays()
        }
    }

    /// A chart's "Chart data": every value in words.
    private func chartData() {
        let here = screen
        if tap(AppCopy.Views.chartData, in: [.button, .staticText, .other]) {
            pause(0.5)
            snap("\(here)-chart-data")
        }
    }

    /// A live dashboard's Refresh Data (the demo answers artifact_refresh). It shows only while the dashboard is live,
    /// has a live panel and the bridge offers it.
    private func refreshData() {
        let here = screen
        guard let button = find(AppCopy.Views.refreshData, in: [.button], timeout: 2) else {
            note("The live dashboard shows no “\(AppCopy.Views.refreshData)”.", kind: .missing)
            return
        }
        if tap(button, named: AppCopy.Views.refreshData) {
            pause(1.5)
            snap("\(here)-refreshed")
        }
    }

    /// A row that says only the Mac does it: photographed, never tapped.
    private func onlyOnTheMac(_ row: String, in title: String) {
        guard let element = find(row, in: Self.textTypes + [.button, .cell], timeout: 2) else {
            note("“\(title)” doesn't show “\(row)”.", kind: .missing)
            return
        }
        snap("view-\(Self.slug(title))-only-on-the-mac", audit: false)
        let what = element.elementType == .button ? "a BUTTON" : "a row"
        note("“\(title)” shows “\(row)” as \(what) (photographed, never tapped).", kind: .observation)
    }

    /// The demo's quiz, taken as a person would (lane Q): Start quiz, the first question's answer, Next, the second's,
    /// Submit answers. The score must show ("Graded by Pebble."), then Share result with Pebble must say "Shared with
    /// Pebble" (Face ID always agrees in the demo). The demo's Pebble grades it with the key it keeps (DemoQuizzes).
    private func takeQuiz() {
        let here = screen
        guard tap(AppCopy.Views.startQuiz, in: [.button]) else { return }
        guard wait(for: AppCopy.Views.questionOf(1, 2), timeout: 5) else {
            note("“\(AppCopy.Views.startQuiz)” didn't show “\(AppCopy.Views.questionOf(1, 2))”.", kind: .noResponse)
            snap("\(here)-not-started", audit: false)
            return
        }
        snap("\(here)-question-1")
        chooseInQuiz(ViewWords.quizFirstChoice)
        guard tap(AppCopy.Views.next, in: [.button]), wait(for: AppCopy.Views.questionOf(2, 2), timeout: 3) else {
            note("“\(AppCopy.Views.next)” didn't show “\(AppCopy.Views.questionOf(2, 2))”.", kind: .noResponse)
            return
        }
        chooseInQuiz(ViewWords.quizSecondChoice)
        snap("\(here)-question-2", audit: false)
        guard tap(AppCopy.Views.submitAnswers, in: [.button]) else { return }
        let graded = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", AppCopy.Views.gradedByPebble)).firstMatch
        guard graded.waitForExistence(timeout: 5) else {
            note("After “\(AppCopy.Views.submitAnswers)” the quiz showed no score.", kind: .noResponse)
            snap("\(here)-not-graded", audit: false)
            return
        }
        let score = graded.label
        snap("\(here)-graded")
        note("Submitting the quiz showed its score: “\(score)”.", kind: .observation)
        guard tap(AppCopy.Views.shareResult, in: [.button]) else { return }
        if wait(for: AppCopy.Views.sharedWithPebble, timeout: 5) {
            snap("\(here)-shared", audit: false)
        } else {
            note("“\(AppCopy.Views.shareResult)” didn't say “\(AppCopy.Views.sharedWithPebble)”.", kind: .noResponse)
        }
    }

    /// Taps the quiz's choice whose words are `words` (its label holds its letter too), and checks that VoiceOver now
    /// hears it as selected.
    private func chooseInQuiz(_ words: String) {
        guard tap(where: NSPredicate(format: "label CONTAINS %@", words), named: words) else { return }
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", words))
        if !(0..<min(rows.count, 4)).contains(where: { rows.element(boundBy: $0).isSelected }) {
            note("The quiz's choice “\(words)” doesn't read as selected after a tap.", kind: .observation)
        }
    }

    /// The app demo: its button goes to the next screen, whose First name field's keyboard closes with a swipe down
    /// (Done in reach); Previous Screen comes back; Restart Demo starts over.
    private func appDemo() {
        let here = screen
        if tap(ViewWords.demoButton, in: [.button]) {
            pause(0.5)
            snap("\(here)-next-screen")
            keyboardCheck(
                "the app demo's First name field", shot: "\(here)-first-name", exit: .swipeDown, inSheet: true,
                open: { openField(ViewWords.firstNamePlaceholder) })
            if tap(AppCopy.Views.previousScreen, in: [.button]) {
                pause(0.5)
                snap("\(here)-previous-screen", audit: false)
            }
        }
        if tap(ViewWords.demoButton, in: [.button]), tap(AppCopy.Views.restartDemo, in: [.button]) {
            pause(0.5)
            snap("\(here)-restarted", audit: false)
            if !shows(ViewWords.demoHeading, timeout: 1) {
                note("Restart Demo didn't bring back the first screen (“\(ViewWords.demoHeading)”).", kind: .noResponse)
            }
        }
    }

    /// Send Feedback in the app demo (App.vue `demoFeedback`): the view closes and Pebble's words wait in the message
    /// box, with the keyboard up. They are deleted again and the keyboard put away: nothing is sent.
    private func appDemoFeedback() {
        guard let card = find(ViewTitle.appDemo, in: [.button], timeout: 3), tap(card, named: ViewTitle.appDemo),
            app.navigationBars.buttons[AppCopy.Views.close].firstMatch.waitForExistence(timeout: 4)
        else { return }
        guard tap(AppCopy.Views.sendFeedback, in: [.button]) else {
            closeView(ViewTitle.appDemo)
            return
        }
        pause(1.5)
        if app.navigationBars.buttons[AppCopy.Views.close].firstMatch.exists {
            note("Send Feedback left the app demo open.", kind: .noResponse)
            closeView(ViewTitle.appDemo)
            return
        }
        let words = NSPredicate(format: "value BEGINSWITH %@", "Feedback on the app demo")
        let field = app.descendants(matching: .any).matching(words).firstMatch
        guard field.waitForExistence(timeout: 2) else {
            note("After Send Feedback the message box doesn't hold “Feedback on the app demo …”.", kind: .noResponse)
            return
        }
        snap("view-app-demo-feedback-in-message-box", audit: false)
        if !app.keyboards.firstMatch.exists {
            note("After Send Feedback the message box doesn't have the keyboard.", kind: .observation)
            field.tap()
        }
        let typed = (field.value as? String)?.count ?? 0
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed + 2))
        hideKeyboard()
    }

    /// Answer… on the waiting form: its sheet must be open to answers (Cancel in its bar). One that opens read-only
    /// (Done) or not at all is a finding, and is closed again. Returns whether it is open to answers.
    private func openWaitingForm(_ place: String) -> Bool {
        guard tap(AppCopy.Views.answerForm, in: [.button]) else { return false }
        if formIsOpen() { return true }
        if app.navigationBars.buttons[AppCopy.Views.close].firstMatch.exists {
            snap("form-read-only-\(Self.slug(place))", audit: false)
            note("“\(AppCopy.Views.answerForm)” \(place) opened the waiting form read-only (Done, nothing to answer).",
                kind: .observation)
            closeView(ViewTitle.form)
        } else {
            note("“\(AppCopy.Views.answerForm)” \(place) opened no form.", kind: .noResponse)
            closeOverlays()
        }
        return false
    }

    /// Whether Pebble's reply to the form's answers shows in the transcript (it streams in; a bubble's label may start
    /// with who wrote it, so any label containing its first words).
    private func replyGoesOn(timeout: TimeInterval) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", ViewWords.replyStart))
            .firstMatch.waitForExistence(timeout: timeout)
    }

    /// Whether an open form's sheet is up: its Cancel in a bar (a form that no longer waits shows Done instead).
    private func formIsOpen(timeout: TimeInterval = 3) -> Bool {
        app.navigationBars.buttons[AppCopy.Views.cancel].firstMatch.waitForExistence(timeout: timeout)
    }

    /// Closes an open form with its Cancel, which sends nothing.
    private func cancelForm(_ place: String) {
        let cancel = app.navigationBars.buttons[AppCopy.Views.cancel].firstMatch
        if cancel.exists, cancel.isHittable {
            cancel.tap()
            pause(0.8)
        } else {
            note("The form \(place) has no Cancel in reach.", kind: .missing)
            closeOverlays()
        }
        if formIsOpen(timeout: 0.5) {
            note("Cancel didn't close the form \(place).", kind: .stuck)
            closeOverlays()
        }
    }
}
