import PebbleDesign
import PebbleProtocol
import XCTest

extension AuditSession {
    /// The demo's walkthroughs (lane R, board 15:25): each decision Pebble waits for, from a fresh demo each time, so
    /// every path starts where a person would find it.
    func tourWalkthroughs() {
        heldChange()
        uncertainStepInMail()
        runningCommand()
        failedTask()
    }

    /// "Add a dark mode toggle": a change made but not verified. Run the Tests, Ask Pebble to Finish, Accept as
    /// Unverified, and the applied edit's Undo and diff.
    private func heldChange() {
        launch(pace: 1)
        guard openChat(Demo.theme) else { return }
        snap("theme-held-change")
        dumpTree("theme-held-change")
        scrollDown()
        snap("theme-held-change-decisions")
        if tap(RecoveryCopy.Held.runTheTests, in: [.button]) {
            pause(2)
            snap("theme-run-the-tests-proposes-a-card")
            if tapFirst(of: [AppCopy.Reviews.approve(.tests), AppCopy.Reviews.approveFallback]) != nil {
                pause(5)
                snap("theme-tests-ran-change-verified")
            }
        }

        relaunch()
        if openChat(Demo.theme), tap(RecoveryCopy.Held.askPebbleToFinish, in: [.button]) {
            pause(5)
            snap("theme-asked-pebble-to-finish")
        }

        relaunch()
        if openChat(Demo.theme), tap(RecoveryCopy.Held.acceptAsUnverified, in: [.button]) {
            snap("theme-accept-as-unverified-question")
            let confirm = app.sheets.buttons[RecoveryCopy.Held.acceptAsUnverified].firstMatch
            let button = confirm.exists ? confirm : app.buttons[RecoveryCopy.Held.acceptAsUnverified].firstMatch
            if tap(button, named: "the question's Accept as Unverified") {
                pause(2)
                snap("theme-accepted-as-unverified")
            }
        }

        relaunch()
        if openChat(Demo.theme) {
            // The card's details by the words this screen shows, not only "View Diff" ([112]).
            if tapFirst(of: Self.cardDetailWords) != nil {
                pause(1)
                snap("theme-edit-diff")
                leaveSheet("The edit's diff")
            }
            // Undo This Edit sits at the end of the transcript (U-30): from the end, not the top ([113]).
            jumpToEnd()
            if tap(RecoveryCopy.Undo.edit, in: [.button]) {
                pause(2)
                snap("theme-edit-undone")
                closeOverlays()
            }
        }
    }

    /// "Send the weekly update in Mail": Pebble lost track of a press in Mail. The paused window's Done and End
    /// Access, and the Uncertain Outcomes sheet with its two ways to settle.
    private func uncertainStepInMail() {
        launch(pace: 1)
        guard openChat(Demo.mail) else { return }
        snap("mail-uncertain-step")
        scrollDown()
        snap("mail-paused-window")
        if tap(RecoveryCopy.Task.details, in: [.button]) {
            screen = "uncertain-outcomes"
            pause(1)
            snap("mail-uncertain-outcomes")
            dumpTree("mail-uncertain-outcomes")
            // Its VoiceOver label names the step ("Settle “…” from Pebble's readback"); the drawn words are another
            // element's ([116]).
            if tap(
                where: NSPredicate(
                    format: "label == %@ OR label BEGINSWITH %@", RecoveryCopy.Outcomes.settle, "Settle \u{201C}"),
                named: RecoveryCopy.Outcomes.settle)
            {
                pause(2)
                snap("mail-settled-from-readback")
            }
            leaveSheet("Uncertain Outcomes")
        }

        relaunch()
        if openChat(Demo.mail), tap(RecoveryCopy.Task.details, in: [.button]) {
            screen = "uncertain-outcomes"
            // "Report it yourself" lists its choices in place (an inline picker), so "It did not happen" is tapped there.
            if tap(RecoveryCopy.Outcomes.didNotHappen, in: [.button, .cell, .staticText]) {
                snap("mail-report-it-did-not-happen", audit: false)
            }
            // The note's keyboard closes on Return with nothing typed (lane W's keyboard rule); Done stays in reach.
            keyboardCheck(
                "Uncertain Outcomes' note", shot: "mail-outcome-note", exit: .emptySubmit, inSheet: true,
                open: { openField(RecoveryCopy.Outcomes.notePlaceholder) })
            if type("Checked the Sent folder: it isn't there.", into: RecoveryCopy.Outcomes.notePlaceholder) {
                snap("mail-report-written", audit: false)
                if tap(RecoveryCopy.Outcomes.record, in: [.button]) {
                    pause(2)
                    snap("mail-report-recorded")
                }
            }
            leaveSheet("Uncertain Outcomes")
        }

        for (decision, name) in [(RecoveryCopy.PausedWindow.done, "done"), (RecoveryCopy.PausedWindow.endAccess, "end-access")] {
            relaunch()
            if openChat(Demo.mail), tap(decision, in: [.button]) {
                pause(2)
                snap("mail-paused-window-\(name)")
            }
        }
    }

    /// "Run the docs site locally": a command still running that waits for an answer, and one Pebble lost track of.
    private func runningCommand() {
        launch(pace: 1)
        guard openChat(Demo.site) else { return }
        let here = screen
        snap("site-commands")
        dumpTree("site-commands")
        scrollDown()
        snap("site-command-cards")
        if tap(RecoveryCopy.Command.typeInto, in: [.button]) {
            screen = "type-into-the-command"
            pause(1)
            snap("site-type-into-the-command")
            // Round 2 (U-51): Send with nothing typed closes the keyboard; Done (leading) stays in reach while it's up.
            keyboardCheck(
                "Type into the Command", shot: "site-type-into-the-command", exit: .emptySubmit, inSheet: true,
                open: { openField(RecoveryCopy.Command.typeIntoField) })
            // The bar's Send (its label and identifier stay Pebble's "Send Line"), then "Sent." above the field.
            if type("y", into: RecoveryCopy.Command.typeIntoField), tap(RecoveryCopy.Command.sendLine, in: [.button]) {
                pause(2)
                snap("site-line-sent")
            }
            // Send Ctrl-C and Send Ctrl-D are in "Send a Key" beside the field: looked at, not used.
            if let menu = openMenu(AppCopy.CommandState.keys, in: [.button]) {
                snap("site-send-a-key-menu", audit: false)
                closeMenu(menu)
            }
            leaveSheet("Type into the Command")
        }
        screen = here
        if tap(RecoveryCopy.Command.readOutput, in: [.button]) {
            pause(1.5)
            snap("site-read-output")
            leaveSheet("Read Output")
        }
        screen = here
        if tap(RecoveryCopy.Command.recordInspection, in: [.button]) {
            screen = "record-inspection"
            pause(1)
            snap("site-record-my-inspection")
            // Return in the empty note closes the keyboard (lane W's keyboard rule); Cancel stays in reach.
            keyboardCheck(
                "the inspection note", shot: "site-inspection-note", exit: .emptySubmit, inSheet: true,
                open: { openField(RecoveryCopy.Command.inspectionNote) })
            chooseAnother(RecoveryCopy.Command.observedOutcome, shot: "site-observed-outcome", named: "Observed outcome")
            // Recording needs the note (U-44): written first, so Record does what it says.
            _ = type("The docs site answered on its local address.", into: RecoveryCopy.Command.inspectionNote)
            hideKeyboard()
            let confirm = app.navigationBars.buttons[RecoveryCopy.Command.recordInspection].firstMatch
            if confirm.exists, tap(confirm, named: "Record My Inspection") {
                pause(2)
                snap("site-inspection-recorded")
            }
            // Still open (refused, or never sent): closed, so Stop Command isn't tried behind it ([136]).
            if app.navigationBars.buttons[RecoveryCopy.Command.recordInspection].exists {
                leaveSheet("Record My Inspection")
            }
        }
        screen = here
        if tap(RecoveryCopy.Command.stop, in: [.button]) {
            pause(2)
            snap("site-command-stopped")
        }
        // Forget shows once the command's output is saved and it has ended: looked for on this screen, not assumed.
        if shows(RecoveryCopy.Command.forgetOutput, timeout: 3) {
            if tap(RecoveryCopy.Command.forgetOutput, in: [.button]) {
                pause(1.5)
                snap("site-command-output-forgotten")
            }
        } else {
            note("“\(RecoveryCopy.Command.forgetOutput)” isn't offered on this screen after Stop Command.", kind: .observation)
        }
    }

    /// "Deploy the preview build": a failed task. Its details, Resume, and a new model offering "Continue with the new
    /// model" (review, approve, start the new run).
    private func failedTask() {
        launch(pace: 1)
        guard openChat(Demo.deploy) else { return }
        snap("deploy-failed")
        scrollDown()
        snap("deploy-failed-task")
        if tap(RecoveryCopy.Task.details, in: [.button]) {
            pause(1)
            snap("deploy-details")
            leaveSheet("Details")
        }
        if tap(RecoveryCopy.Task.resume, in: [.button]) {
            pause(1)
            snap("deploy-resumed")
            pause(5)
            snap("deploy-resumed-reply")
        }

        relaunch()
        guard openChat(Demo.deploy) else { return }
        // The model menu stays open 5 s first (U-53), then the pick that offers the handoff (U-34).
        if chooseAnother("\(AppCopy.Control.model),", shot: "deploy-model", named: "The model menu", waitFirst: 5) {
            pause(3)
            snap("deploy-new-model-offers-a-handoff")
            scrollDown()
            snap("deploy-handoff-card")
            if tap(RecoveryCopy.Handoff.approve, in: [.button]) {
                pause(2)
                snap("deploy-handoff-approved")
                if tap(RecoveryCopy.Handoff.start, in: [.button]) {
                    pause(5)
                    snap("deploy-handoff-new-run")
                }
            }
        }
    }

    // MARK: - Details (lane Y, fix 8)

    /// Details, the phone's copy of Pebble's details drawer, opened from ⋯ in every conversation, during and after a
    /// task (U-22).
    ///
    /// - **Each conversation lane Y names, with its tabs:**
    ///   - the login fix (during its run), Activity;
    ///   - this week's commits: Activity's folded group, Show More, the reasoning, and More sections;
    ///   - the held change: Context with Compact…, Changes with Rewind, Task with Abandon…, and (lane T) the goal's
    ///     edits: a criterion's Edit with its keyboard, a step's menu with Edit step and Block step, Add step and
    ///     Blockers;
    ///   - the README: Task with (lane T) the Review that opens the npm test card, an agent's own screen with its
    ///     Technical details, Send input and Cancel agent, then Tools, and Browser with the grant sheet.
    /// - **Activity's count against its list (U-45).**
    /// - **Confirmations:** each is opened, photographed and left with its safe answer. Never Rewind, Cancel agent,
    ///   Abandon, a grant, Compact now, Stop Pebble in Chrome, End access, or anything that settles a goal.
    /// - **The rest:** the other conversations' Details, each opened once.
    func tourDetails() {
        launch(pace: 6)
        if openChat(Demo.login), openDetails() {
            snap("details-login-while-working")
            activityCount("details-login")
            leaveSheet("Details")
        }
        if openChat(Demo.commits), openDetails() {
            snap("details-commits-activity")
            activityCount("details-commits")
            if element(AppCopy.Details.showMore, in: [.button], timeout: 1) != nil,
                tap(AppCopy.Details.showMore, in: [.button], timeout: 1)
            {
                pause(0.6)
                snap("details-commits-show-more", audit: false)
            }
            if find(AppCopy.Details.reasoning, in: Self.controlTypes + Self.textTypes, timeout: 1) != nil {
                snap("details-commits-reasoning", audit: false)
            }
            detailsMoreSections("details-commits")
            leaveSheet("Details")
        }
        if openChat(Demo.theme), openDetails() {
            snap("details-theme")
            if chooseDetailsTab(AppCopy.Details.context, shot: "details-theme-context") {
                askThenDecline(AppCopy.Details.compact, shot: "details-theme-compact")
            }
            if chooseDetailsTab(AppCopy.Details.changes, shot: "details-theme-changes") {
                askThenDecline(AppCopy.Details.rewindButton(1), shot: "details-theme-rewind")
                // Reviewing only reads what a rewind would change (rewind_preview); nothing changes without its
                // confirmation, which the tour never gives.
                if element(AppCopy.Details.reviewUndoRewind, in: [.button], timeout: 1) != nil,
                    tap(AppCopy.Details.reviewUndoRewind, in: [.button], timeout: 1)
                {
                    pause(1.5)
                    snap("details-theme-review-undoing-the-rewind")
                }
            }
            if chooseDetailsTab(AppCopy.Details.task, shot: "details-theme-task") {
                askThenDecline(AppCopy.Details.abandon, shot: "details-theme-abandon", safe: AppCopy.Details.keepGoal)
                scrollDown()
                snap("details-theme-task-criteria", audit: false)
                goalEdits()
            }
            leaveSheet("Details")
        }
        if openChat(Demo.readme), openDetails() {
            snap("details-readme")
            if chooseDetailsTab(AppCopy.Details.task, shot: "details-readme-task") {
                reviewFromBlockers()
                agentScreen()
            }
            chooseDetailsTab(AppCopy.Details.tools, shot: "details-readme-tools")
            if chooseDetailsTab(AppCopy.Details.browser, shot: "details-readme-browser") {
                if element(AppCopy.Details.checkAgain, in: [.button], timeout: 1) != nil,
                    tap(AppCopy.Details.checkAgain, in: [.button], timeout: 1)
                {
                    pause(1.5)
                    snap("details-readme-browser-checked-again", audit: false)
                }
                // The grant sheet, in Pebble's words: looked at, then Cancel. Never "Grant this tab".
                if tap(AppCopy.Details.letPebbleUseTab, in: [.button], timeout: 1) {
                    pause(1)
                    snap("details-readme-grant-sheet")
                    scrollDown()
                    snap("details-readme-grant-sheet-further", audit: false)
                    leaveSheet("Let Pebble use this tab")
                }
            }
            leaveSheet("Details")
        }
        // The rest: Details in ⋯ in every conversation, after its task too.
        for title in [Demo.emails, Demo.mail, Demo.site, Demo.deploy, Demo.weather] {
            if openChat(title), openDetails() {
                snap("details-\(Self.slug(title))")
                leaveSheet("Details")
            }
        }
    }

    /// Lane T: the theme goal's edits, each sheet opened, photographed and left with Cancel, so nothing is saved: a
    /// criterion's Edit (its keyboard closes with Return), a blocked step's menu and Edit step, a pending step's Block
    /// step (the Reason's keyboard), Add step with its After choices, then the Blockers. Unblock is never tapped.
    private func goalEdits() {
        if tap(AppCopy.Goals.editCriterion("c1"), in: [.button], timeout: 2) {
            pause(1)
            snap("details-theme-edit-criterion")
            keyboardCheck(
                "a criterion's words", shot: "details-theme-edit-criterion", exit: .emptySubmit, inSheet: true,
                open: { tap(AppCopy.Goals.criterion, in: [.textField], timeout: 1) })
            leaveSheet(AppCopy.Goals.editCriterion("c1"))
        }
        let blocked = AppCopy.Goals.stepActions("s3", "Check the contrast in both themes")
        if let menu = openMenu(blocked, in: [.button]) {
            snap("details-theme-step-menu", audit: false)
            let unblock = [AppCopy.Goals.unblock, AppCopy.Goals.unblockStep("s3")]
            if menu.contains(where: { unblock.contains($0.label) }) {
                note("A blocked step's menu offers Unblock.", kind: .observation)
            }
            if pick(AppCopy.Goals.editStep, in: menu) {
                pause(1)
                snap("details-theme-edit-step")
                leaveSheet(AppCopy.Goals.editStepNamed("s3"))
            }
        }
        if let menu = openMenu(AppCopy.Goals.stepActions("s2", "Run the settings tests"), in: [.button]),
            pick(AppCopy.Goals.blockStep, in: menu)
        {
            pause(1)
            snap("details-theme-block-step")
            keyboardCheck(
                "a step's reason", shot: "details-theme-block-step", exit: .emptySubmit, inSheet: true,
                open: { tap(AppCopy.Goals.reasonPlaceholder, in: [.textField], timeout: 1) })
            leaveSheet(AppCopy.Goals.blockStep)
        }
        if tap(AppCopy.Goals.addStep, in: [.button], timeout: 2) {
            pause(1)
            snap("details-theme-add-step")
            leaveSheet(AppCopy.Goals.addStep)
        }
        if find(AppCopy.Goals.blockers, in: Self.textTypes + Self.controlTypes, timeout: 1) != nil {
            snap("details-theme-blockers", audit: false)
        } else {
            note("The theme goal's Blockers don't show in Details › Task.", kind: .missing)
        }
    }

    /// Lane T: the README goal's step waits for the npm test card; its blocker's Review opens that card over Details,
    /// photographed and left with Done (never Approve or Reject).
    private func reviewFromBlockers() {
        guard tap(AppCopy.Goals.review, in: [.button], timeout: 2) else { return }
        pause(1)
        if shows(AppCopy.Goals.reviewGone) {
            note("Review opened no waiting card: “\(AppCopy.Goals.reviewGone)”.", kind: .observation)
        }
        snap("details-readme-review-card")
        leaveSheet(AppCopy.Goals.review)
    }

    /// Lane T: an agent opens its own screen (`agent_get`): its state, use, task and result, Technical details
    /// unfolded, then Send input (its alert's keyboard, then Cancel, so nothing is sent) and Cancel agent (asked, then
    /// declined).
    private func agentScreen() {
        guard tap("Link checker", in: [.button, .cell], timeout: 2) else { return }
        pause(1.2)
        snap("details-readme-agent")
        if tap(AppCopy.Goals.technicalDetails, in: [.button, .disclosureTriangle], timeout: 1) {
            pause(0.6)
            snap("details-readme-agent-technical", audit: false)
        }
        // In the Details sheet: the sheet covers the tab bar and Back by design, so its own ways out count ([250]).
        keyboardCheck(
            "an agent's task input", shot: "details-readme-send-input", exit: .button(AppCopy.Common.cancel),
            inSheet: true, open: { tap(AppCopy.Details.sendInput, in: [.button], timeout: 1) })
        closeOverlays()
        askThenDecline(AppCopy.Details.cancelAgent, shot: "details-readme-cancel-agent")
        goBack()
    }

    /// ⋯ › Details (lane Y: once "What Pebble did"). Returns whether the Details sheet opened.
    @discardableResult
    func openDetails() -> Bool {
        guard let menu = openMenu(AppCopy.Conversation.more, in: [.button]) else { return false }
        guard pick(AppCopy.Details.title, in: menu) else { return false }
        pause(1.2)
        screen = "details"
        if app.navigationBars[AppCopy.Details.title].waitForExistence(timeout: 3) { return true }
        note("⋯ › Details showed no Details screen.", kind: .noResponse)
        return false
    }

    /// Chooses a Details tab: its segment; at accessibility sizes, the sections menu that stands in for the segments;
    /// or, when the tab has nothing yet, "More sections". Photographs it. Returns whether the tab was chosen.
    @discardableResult
    func chooseDetailsTab(_ title: String, shot: String) -> Bool {
        // Right after a question or an alert closed, the segments are found only once it has gone ([246], [250]).
        settle()
        if let segment = element(title, in: [.button], timeout: 1), segment.isHittable, tap(segment, named: title) {
            pause(1)
            snap(shot)
            return true
        }
        for menuName in [AppCopy.Details.sections, AppCopy.Details.moreSections] {
            guard element(menuName, in: [.button], timeout: 0.5) != nil,
                let menu = openMenu(menuName, in: [.button])
            else { continue }
            let item = menu.first { $0.label == title || $0.label == Self.moreTitle(title) }
            guard let item else {
                closeMenu(menu)
                continue
            }
            press(item)
            pause(1)
            snap(shot)
            return true
        }
        note("Details has no “\(title)” tab here.", kind: .observation)
        return false
    }

    /// "More sections" (DetailsDrawer.vue): each tab it offers, opened once.
    func detailsMoreSections(_ shot: String) {
        guard element(AppCopy.Details.moreSections, in: [.button], timeout: 0.5) != nil,
            let menu = openMenu(AppCopy.Details.moreSections, in: [.button])
        else { return }
        snap("\(shot)-more-sections", audit: false)
        let titles = menu.filter { item in
            !item.label.isEmpty && item.type != .other && item.identifier != "PopoverDismissRegion"
                && item.label != "dismiss popup"
        }.map(\.label)
        closeMenu(menu)
        for title in titles.prefix(5) {
            guard let again = openMenu(AppCopy.Details.moreSections, in: [.button]), pick(title, in: again) else { continue }
            pause(1)
            snap("\(shot)-more-\(Self.slug(title))")
        }
    }

    /// The name "More sections" gives a tab (DetailsDrawer.vue).
    static func moreTitle(_ title: String) -> String {
        switch title {
        case AppCopy.Details.task: AppCopy.Details.moreTask
        case AppCopy.Details.context: AppCopy.Details.moreContext
        case AppCopy.Details.changes: AppCopy.Details.moreChanges
        case AppCopy.Details.tools: AppCopy.Details.moreTools
        case AppCopy.Details.browser: AppCopy.Details.moreBrowser
        default: title
        }
    }

    /// U-45: Activity's count against its list, as a finding.
    /// - **Pebble's count:** the receipt line above the steps ("Worked for 38 s · 6 steps").
    /// - **The list:** the rows under the steps' header. A folded row counts what it folds ("Explored · read 2 files,
    ///   1 search" is 3; "GPT-5.1 responded · 3 steps" is 3).
    /// - **Pebble's own note** ("Pebble counted N steps; M are listed here.") is recorded as it reads.
    /// - **Lane G:** the plan line ("Working · 2 of 4 steps") counts the plan's steps, so it is never the receipt; the
    ///   work view's Summary section and Pebble's reasoning sit under the steps and are no steps; a step Pebble drew as
    ///   a card is one row.
    ///
    /// Only rows on screen are counted, so the list is photographed too.
    func activityCount(_ shot: String) {
        guard let root = try? app.snapshot() else { return }
        var texts: [(label: String, frame: CGRect)] = []
        var cells: [CGRect] = []
        func walk(_ node: any XCUIElementSnapshot) {
            if !node.label.isEmpty { texts.append((node.label, node.frame)) }
            if node.elementType == .cell { cells.append(node.frame) }
            for child in node.children {
                walk(child)
            }
        }
        walk(root)
        let header = texts.first { $0.label == AppCopy.Details.did || $0.label == AppCopy.Details.doing }
        guard let header else {
            note("U-45, \(shot): Activity shows no steps list.", kind: .observation)
            return
        }
        let receipt = texts.first { text in
            text.frame.maxY <= header.frame.minY && !Self.isPlanLine(text.label)
                && !Self.numbers(in: text.label, before: "steps?").isEmpty
        }
        let counted = receipt.flatMap { Self.numbers(in: $0.label, before: "steps?").last }
        // A row's words: the first label inside each cell under the header, down to the work view's Summary.
        let end = texts.filter { $0.label == AppCopy.Views.summary && $0.frame.minY > header.frame.maxY }
            .map { $0.frame.minY }.min() ?? .greatestFiniteMagnitude
        let rows = cells.filter { $0.minY >= header.frame.maxY - 1 && $0.minY < end }.compactMap { cell in
            texts.first { cell.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }?.label
        }.filter { $0 != AppCopy.Details.reasoning }
        let listed = rows.reduce(0) { sum, row in
            if row.hasPrefix("Explored") {
                return sum + Self.numbers(in: row, before: "files?|search(?:es)?").reduce(0, +)
            }
            if let folded = Self.numbers(in: row, before: "steps").first { return sum + folded }
            return sum + 1
        }
        let pebbleNote = texts.first { $0.label.hasPrefix("Pebble counted") }?.label
        let verdict = counted.map { $0 == listed ? "equal" : "NOT equal" } ?? "no count to compare"
        note(
            "U-45, \(shot): Pebble's count \(counted.map { "\($0)" } ?? "none") (“\(receipt?.label ?? "no receipt line")”); "
                + "\(listed) listed in \(rows.count) rows: \(verdict)."
                + (pebbleNote.map { " Pebble's note: “\($0)”." } ?? ""),
            kind: .observation)
        snap("\(shot)-activity-list", audit: false)
    }

    /// Whether `text` is the plan's progress (lane G: "Working · 2 of 4 steps", "2 of 4 plan steps done").
    static func isPlanLine(_ text: String) -> Bool {
        text.range(of: "[0-9]+ of [0-9]+ (?:plan )?steps", options: .regularExpression) != nil
    }

    /// The numbers in `text` written just before one of `words` (a regular expression): "read 2 files, 1 search" with
    /// "files?|search(?:es)?" gives [2, 1].
    static func numbers(in text: String, before words: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: "([0-9]+) (?:\(words))\\b") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
        }
    }
}
