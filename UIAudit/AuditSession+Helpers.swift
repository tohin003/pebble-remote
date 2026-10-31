import PebbleDesign
import XCTest

/// Small moves the tours share: leaving a sheet, the conversation's title menu, the bottom accessory, menus of choices.
extension AuditSession {
    /// The demo's conversations (DemoData), by the titles the Chats list shows.
    enum Demo {
        static let login = "Fix the login redirect loop"
        static let readme = "Update the README for 2.0"
        static let emails = "Plan the onboarding emails"
        static let commits = "Summarize this week's commits"
        static let deploy = "Deploy the preview build"
        static let weather = "Weather in Lisbon this weekend"
        static let theme = "Add a dark mode toggle"
        static let mail = "Send the weekly update in Mail"
        static let site = "Run the docs site locally"
        /// The projects the demo's conversations use.
        static let webProject = "pebble-web"
        static let docsProject = "pebble-docs"
    }

    /// The mode chip on the Pebble tab: VoiceOver reads it "Permissions: <mode>".
    static let modeChip = NSPredicate(format: "label BEGINSWITH %@ AND elementType == %@", "Permissions:",
        NSNumber(value: XCUIElement.ElementType.button.rawValue))

    /// Leaves a sheet the way its own buttons offer (Cancel, Done, Close), or by dragging it down.
    func leaveSheet(_ what: String) {
        if closeSheet() { return }
        note("\(what) has no Cancel, Done or Close; dragged it down.", kind: .observation)
        swipeSheetDown()
    }

    /// The conversation's title, which is a menu (Pebble's sidebar actions for this place). Returns its items.
    func openTitleMenu(_ title: String) -> [Control]? {
        let before = Set(controls().map(\.key))
        let query = app.navigationBars.firstMatch.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ OR label == %@", title, AppCopy.Place.menu))
        guard query.firstMatch.waitForExistence(timeout: 2) else {
            note("The conversation's title (“\(title)”) wasn't found in the navigation bar.", kind: .missing)
            return nil
        }
        guard tap(hittable(in: query), named: "the title menu") else { return nil }
        let added = controls().filter { !before.contains($0.key) }
        if added.isEmpty {
            note("Tapping the conversation's title opened nothing.", kind: .noResponse)
            return nil
        }
        return added
    }

    /// Where the tab bar's bottom accessory shows a button whose label contains `text`: a button in the lower part of
    /// the screen that lies outside every list, scroll view, cell, navigation bar and the tab bar (the accessory is its
    /// own layer over the tab bar; a list row with the same words is not it). Nil when there is none.
    func accessoryFrame(containing text: String) -> CGRect? {
        guard let root = try? app.snapshot() else { return nil }
        let bottom = root.frame.height * 0.6
        var found: CGRect?
        func walk(_ node: any XCUIElementSnapshot) {
            guard found == nil else { return }
            switch node.elementType {
            case .collectionView, .table, .scrollView, .cell, .navigationBar, .tabBar, .keyboard, .textField:
                return
            case .button where node.label.contains(text) && node.frame.minY > bottom:
                found = node.frame
                return
            default:
                break
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(root)
        return found
    }

    /// Taps the bottom accessory's button whose label contains `text`, at its place. Returns whether it was there.
    @discardableResult
    func tapAccessory(containing text: String, named name: String) -> Bool {
        guard let frame = accessoryFrame(containing: text) else { return false }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        tapped.insert("\(screen)|\(name)")
        pause(0.8)
        return stillRunning(after: name)
    }

    /// The bottom accessory on the Chats list, where it now shows (lane V: not on the Pebble tab, not in a
    /// conversation): the run's words open its conversation.
    func accessoryOnChats(opens title: String, shot: String) {
        toRoot(of: AppCopy.Tabs.chats)
        if tapAccessory(containing: title, named: "the bottom accessory's run") {
            screen = "chats-accessory"
            snap(shot)
            goBack()
        } else {
            note("The bottom accessory didn't show the live run (“\(title)”) on Chats.", kind: .observation)
            snap("chats-accessory-not-found", audit: false)
        }
        screen = "chats"
    }

    /// Choosing Full access asks first (lane W, U-07): the question is photographed, then cancelled. The audit never
    /// confirms it. If no question came, that is a finding (and the mode may now be Full access).
    func fullAccessQuestion(_ shot: String) {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else {
            note("Choosing Full access didn't ask “\(AppCopy.Modes.fullAccessTitle)” first.", kind: .observation)
            snap("\(shot)-full-access-without-a-question")
            return
        }
        snap("\(shot)-full-access-question")
        let cancel = alert.buttons[AppCopy.Common.cancel]
        if cancel.exists, cancel.isHittable {
            cancel.tap()
            pause(0.8)
        } else {
            let words = alert.exists ? alert.label : ""  // a gone element's label would stop the whole test
            note("“\(AppCopy.Modes.fullAccessTitle)” had no Cancel: “\(words)”.", kind: .observation)
            closeAlert()  // never its "Use Full Access": closeAlert only ever taps Cancel, Close, OK or Done
        }
    }

    /// The bottom accessory's control whose label contains `text` (the live run's bar opens its conversation).
    func accessoryButton(containing text: String) -> XCUIElement? {
        let query = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text))
        let bottom = app.frame.height * 0.7
        for index in 0..<min(query.count, 8) {
            let button = query.element(boundBy: index)
            if button.isHittable, button.frame.minY > bottom { return button }
        }
        return nil
    }

    /// Picks the first item of a menu of choices that isn't the current one (not marked selected, and not named in
    /// `current`, the menu button's own label, such as "Model, GPT-5").
    @discardableResult
    func pickAnother(in menu: [Control], besides current: String? = nil, named what: String) -> Bool {
        let choices = menu.filter { item in
            !item.name.isEmpty && item.type != .other && !item.isSelected
                && !(current.map { $0.hasSuffix(", \(item.name)") || $0 == item.name } ?? false)
        }
        guard let choice = choices.first else {
            note("\(what) offered no other choice: \(menu.map(\.name).joined(separator: ", ")).", kind: .observation)
            closeMenu(menu)
            return false
        }
        press(choice)
        tapped.insert("\(screen)|\(choice.name)")
        return stillRunning(after: choice.name)
    }

    /// The first row of a list screen: a row or button below the navigation bar, other than the one marked chosen.
    func firstRow() -> Control? {
        let top = app.frame.height * 0.15
        return controls().first { row in
            (row.type == .button || row.type == .cell) && row.frame.minY > top && !row.isSelected && !row.name.isEmpty
        }
    }

    /// A menu button's whole label ("Model, GPT-5"), found by how it starts.
    func currentLabel(of prefix: String) -> String? {
        element(prefix, in: [.button], timeout: 1)?.label
    }

    /// Opens a menu of choices whose button starts with `prefix` and picks another one; returns whether it did.
    ///
    /// The pick comes before any accessibility audit: an audit takes seconds, and in the re-check the model menu was
    /// gone by the time the tour tapped (U-53), so the open menu is photographed without one. With `waitFirst`, the menu
    /// is left open that long first, photographed, and checked (U-53: does it close by itself?); if it closed, that is a
    /// finding, and the menu opens again for the pick.
    @discardableResult
    func chooseAnother(_ prefix: String, shot: String, named what: String, waitFirst: TimeInterval = 0) -> Bool {
        let current = currentLabel(of: prefix)
        guard var menu = openMenu(prefix, in: [.button]) else { return false }
        if waitFirst > 0 {
            pause(waitFirst)
            if menuStillOpen(menu, besides: current) {
                note("\(what) stayed open for \(Int(waitFirst)) s, as a person reads it (U-53).", kind: .observation)
                snap("\(shot)-still-open-after-\(Int(waitFirst))-s", audit: false)
            } else {
                note("\(what) closed by itself within \(Int(waitFirst)) s (U-53).", kind: .observation)
                snap("\(shot)-closed-by-itself", audit: false)
                guard let again = openMenu(prefix, in: [.button]) else { return false }
                menu = again
            }
        } else {
            snap("\(shot)-choices", audit: false)
        }
        guard pickAnother(in: menu, besides: current, named: what) else { return false }
        pause(1.5)
        snap("\(shot)-changed")
        return true
    }

    /// Whether a menu the tour opened is still open: the choice `pickAnother` would take (not the current one, named in
    /// `current`, the menu button's own label) is still there to tap.
    func menuStillOpen(_ items: [Control], besides current: String? = nil) -> Bool {
        let choices = items.filter { item in
            !item.name.isEmpty && item.type != .other && !item.isSelected
                && !(current.map { $0.hasSuffix(", \(item.name)") || $0 == item.name } ?? false)
        }
        guard let item = choices.first else { return false }
        let still = app.descendants(matching: item.type).matching(
            NSPredicate(format: "label == %@ AND identifier == %@", item.label, item.identifier)
        ).firstMatch
        return still.exists && still.isHittable
    }

    /// The first of `labels` that is on screen now, tapped.
    @discardableResult
    func tapFirst(of labels: [String], in types: [XCUIElement.ElementType] = [.button]) -> String? {
        // Page by page from here to the end of the content: a card's buttons can lie below the fold ([089]).
        for _ in 0..<12 {
            for label in labels {
                if let element = element(label, in: types, timeout: 0.3), element.isHittable, tap(element, named: label) {
                    return label
                }
            }
            if !scrollDown() { break }
        }
        // Checked against the screen, not only the copy: what it offers instead, so a word the app no longer shows
        // reads apart from one out of reach ([089], [112]).
        let offered = controls().filter { $0.type == .button && !$0.label.isEmpty }.prefix(12).map { "“\($0.label)”" }
        note(
            "None of \(labels.map { "“\($0)”" }.joined(separator: ", ")) is on this screen; it offers "
                + (offered.isEmpty ? "no named button." : offered.joined(separator: ", ") + "."),
            kind: .observation)
        return nil
    }

    /// A card's details button, in each of the words the app gives it (CardDetailCopy: by the card's kind).
    static let cardDetailWords = [
        CardDetailCopy.viewDiff, CardDetailCopy.viewTheCheck, CardDetailCopy.technicalDetails, CardDetailCopy.details,
    ]

    /// To the end of a conversation's transcript: Jump to Latest when it shows, else scrolling down until the content
    /// stops (U-30's Undo This Edit sits at the end).
    func jumpToEnd() {
        if let jump = element(AppCopy.Conversation.jumpToLatest, in: [.button], timeout: 0.5), jump.isHittable {
            jump.tap()
            pause(0.8)
            return
        }
        var moves = 0
        while moves < 8, scrollDown() {
            moves += 1
        }
    }

    /// Opens a row of the Settings tab (once Control; `AppCopy.Tabs.control` carries its name), photographs what it
    /// shows, lets `then` act there, and comes back to Settings.
    func visitControlRow(_ row: String, as name: String, then: () -> Void = {}) {
        toRoot(of: AppCopy.Tabs.control)
        // A row just above the tab bar took the tap and opened nothing ([171]): to the middle of the screen first.
        if let found = find(row, in: [.button, .cell, .link], timeout: 2), found.frame.maxY > app.frame.height * 0.7 {
            _ = bringToMiddle(found)
        }
        // Only once its page is open does `then` act: a swipe meant for Toolbox's first row swiped the Settings root's
        // Model row and opened Model ([172]).
        guard open(row, in: [.button, .cell, .link]) else { return }
        screen = name
        pause(0.6)
        snap(name)
        then()
        closeOverlays()
    }

    // MARK: - Questions, long presses, searches

    /// Leaves a question with its safe answer (Cancel, Keep, Keep goal), in an alert, a dialog or wherever it shows:
    /// never its confirming button. When the safe answer isn't there (an iPhone confirmation can hide its cancel
    /// button), a tap beside the question closes it, as a person does.
    func answerSafely(_ safe: String) {
        let inAlert = app.alerts.firstMatch.buttons[safe]
        let inDialog = app.sheets.firstMatch.buttons[safe]
        let anywhere = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'BackButton'", safe))
            .firstMatch
        for button in [inAlert, inDialog, anywhere] where button.exists && button.isHittable {
            button.tap()
            pause(0.6)
            return
        }
        note("The question had no “\(safe)” to tap; closed it the way a person does.", kind: .observation)
        closeOverlays()
    }

    /// Opens a question with `opener`, photographs it, and leaves it with `safe` (`answerSafely`): never its confirming
    /// button, which often has the opener's own words ("Rewind 1 file", "Cancel agent and descendants").
    func askThenDecline(_ opener: String, shot: String, safe: String = AppCopy.Common.cancel) {
        guard tap(opener, in: [.button], timeout: 1) else { return }
        pause(0.8)
        snap("\(shot)-question", audit: false)
        answerSafely(safe)
    }

    /// Long-presses the first element whose label contains `text` (for rows whose label starts with other words, such
    /// as a memory's origin, or "You:" before the person's own message) and returns what appeared, or nil when it isn't
    /// there.
    func longPress(containing text: String) -> [Control]? {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text))
        guard query.firstMatch.waitForExistence(timeout: 2) else {
            note("Couldn't find “\(text)” to long-press.", kind: .missing)
            return nil
        }
        let target = hittable(in: query)
        let before = Set(controls().map(\.key))
        target.press(forDuration: 1.2)
        pause(0.8)
        guard stillRunning(after: "long press on \(text)") else { return nil }
        return controls().filter { !before.contains($0.key) }
    }

    /// Ends a search with the system's Cancel or Close, and records whether that closed the keyboard and left the tab bar
    /// or Back in reach.
    func endSearch(_ what: String) {
        let leave = app.buttons.matching(
            NSPredicate(
                format: "(label == %@ OR label == %@) AND identifier != 'BackButton'", AppCopy.Common.cancel,
                AppCopy.Common.close)
        ).firstMatch
        guard leave.exists, leave.isHittable else {
            note("\(what) has no Cancel or Close.", kind: .observation)
            closeOverlays()
            return
        }
        let name = leave.label
        leave.tap()
        pause(0.6)
        if app.keyboards.firstMatch.exists {
            note("Keyboard: \(what)'s \(name) left the keyboard up.", kind: .keyboardTrap)
            forceCloseKeyboard(what)
        } else if let reach = chromeInReach() {
            note("Keyboard: \(what)'s \(name) closed it; \(reach) can be tapped.", kind: .keyboard)
        } else {
            note("Keyboard: after \(what)'s \(name), neither the tab bar nor Back can be tapped.", kind: .keyboardTrap)
        }
    }

    // MARK: - The keyboard (the person's P1 of 2026-10-30: on the Pebble tab and in Chats it wouldn't close)

    /// How a check closes the keyboard without sending anything.
    enum KeyboardExit {
        /// A swipe down that starts on the content and runs through the keyboard.
        case swipeDown
        /// The keyboard's own Send, Return, Done, Go or Search key, with nothing typed.
        case emptySubmit
        /// The same key after typing (lane G's form: Return must close the keyboard and send nothing).
        case typedReturn
        /// A tap on the screen's first list cell, which isn't a control (on the Pebble tab, the hero).
        case tapFirstCell
        /// A tap high on the transcript or the welcome, in its left margin, where no row's control sits (a conversation,
        /// a new one: the person's report of 2026-10-31 that in Chats the keyboard stayed up).
        case tapAbove
        /// A button that ends editing without sending: an alert's Cancel, Search's Cancel or Close.
        case button(String)

        var name: String {
            switch self {
            case .swipeDown: "a swipe down"
            case .emptySubmit: "Return or Send with nothing typed"
            case .typedReturn: "Return after typing"
            case .tapFirstCell: "a tap on the list"
            case .tapAbove: "a tap on the transcript"
            case .button(let label): "“\(label)”"
            }
        }

        var slug: String {
            switch self {
            case .swipeDown: "swipe-down"
            case .emptySubmit: "empty-send"
            case .typedReturn: "return-after-typing"
            case .tapFirstCell: "tap-on-the-list"
            case .tapAbove: "tap-on-the-transcript"
            case .button(let label): AuditSession.slug(label)
            }
        }
    }

    /// One keyboard check: `open` brings the keyboard up (it taps the field, or shows an alert whose field takes it),
    /// then it is photographed, closed with `exit`, photographed again, and the way out is checked. Away from a sheet,
    /// the tab bar or Back must then be tappable; in a sheet (`inSheet`), its Cancel or Done must be tappable while the
    /// keyboard is still up, since that is a sheet's exit too. Every outcome is a finding: `keyboard` when it passed,
    /// `keyboard-trap` when the keyboard stayed or nothing could be tapped to leave. A keyboard that stayed is then
    /// closed another way, so the tour goes on. Returns whether `exit` closed it.
    @discardableResult
    func keyboardCheck(
        _ what: String, shot: String, exit: KeyboardExit, inSheet: Bool = false, open: () -> Bool
    ) -> Bool {
        let shotName = "\(shot)-keyboard-\(exit.slug)"
        guard open() else {
            note("Keyboard: couldn't open \(what) to check its keyboard.", kind: .missing)
            return false
        }
        guard app.keyboards.firstMatch.waitForExistence(timeout: 3) else {
            note("Keyboard: \(what) brought up no keyboard.", kind: .observation)
            return false
        }
        snap("\(shotName)-up", audit: false)
        if inSheet {
            if let exitButton = sheetExitInReach() {
                note("Keyboard: with \(what)'s keyboard up, \(exitButton) can be tapped.", kind: .keyboard)
            } else {
                note("Keyboard: with \(what)'s keyboard up, the sheet's Cancel or Done can't be tapped.", kind: .keyboardTrap)
            }
        }
        guard perform(exit) else {
            // Nothing was pressed, so nothing was tested: not a trap (the re-check's [076]).
            note("Keyboard: \(what) wasn't checked with \(exit.name): there was nothing to press.", kind: .observation)
            forceCloseKeyboard(what)
            return false
        }
        pause(0.8)
        let closed = !app.keyboards.firstMatch.exists
        snap("\(shotName)-after", audit: false)
        if closed {
            note("Keyboard: \(what) closed with \(exit.name), nothing sent.", kind: .keyboard)
            if !inSheet {
                if let reach = chromeInReach() {
                    note("Keyboard: after \(what), \(reach) can be tapped.", kind: .keyboard)
                } else {
                    note("Keyboard: after \(what), neither the tab bar nor Back can be tapped.", kind: .keyboardTrap)
                }
            }
        } else {
            note("Keyboard: \(what) did NOT close with \(exit.name).", kind: .keyboardTrap)
            forceCloseKeyboard(what)
        }
        return closed
    }

    /// Does what `exit` says, once. Returns whether anything was pressed: false when the key, cell or button wasn't
    /// there, so the check says "not tested" rather than calling the keyboard a trap.
    @discardableResult
    func perform(_ exit: KeyboardExit) -> Bool {
        switch exit {
        case .swipeDown:
            swipeDownThroughKeyboard()
        case .emptySubmit, .typedReturn:
            let keyboard = app.keyboards.firstMatch
            guard keyboard.exists else {
                note("Keyboard: no keyboard to press Return on.", kind: .observation)
                return false
            }
            let key = keyboard.buttons.matching(
                NSPredicate(
                    format: "label ==[c] 'send' OR label ==[c] 'return' OR label ==[c] 'done' OR label ==[c] 'go' OR label ==[c] 'search'")
            ).firstMatch
            // Right after a burst of deletes the keyboard redraws its keys: wait for the key a moment ([076]).
            if key.waitForExistence(timeout: 2), key.isHittable {
                key.tap()
            } else {
                // No key the audit knows by name: Return typed as a key press, into the field that has the keyboard.
                note("Keyboard: no Return, Send or Done key by name; pressed Return by typing it.", kind: .observation)
                app.typeText(XCUIKeyboardKey.return.rawValue)
            }
        case .tapFirstCell:
            let cell = app.cells.firstMatch
            if cell.exists, !cell.frame.isEmpty, cell.frame.midY < app.frame.height * 0.5 {
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: cell.frame.midX, dy: cell.frame.midY)).tap()
            } else {
                note("Keyboard: no list cell in the upper half to tap.", kind: .observation)
                return false
            }
        case .tapAbove:
            // 8 pt from the left edge, a third of the way down: the rows' own margin, below the navigation bar.
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 8, dy: app.frame.height * 0.33)).tap()
        case .button(let label):
            let inAlert = app.alerts.firstMatch.buttons[label]
            let button = inAlert.exists ? inAlert : app.buttons.matching(
                NSPredicate(format: "label == %@ AND identifier != 'BackButton'", label)
            ).firstMatch
            if button.exists, button.isHittable {
                button.tap()
            } else {
                note("Keyboard: no “\(label)” to tap.", kind: .missing)
                return false
            }
        }
        return true
    }

    /// The conversation's message field, by its name ("Message Pebble", U-61) and its place: the lowest such field on
    /// screen, in the bottom bar. Its placeholder goes once it holds words, so a placeholder can't find it then ([075]).
    func composerField(timeout: TimeInterval = 1) -> XCUIElement? {
        let kinds = Self.fieldTypes.map { NSNumber(value: $0.rawValue) }
        let query = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "elementType IN %@ AND (label == %@ OR placeholderValue == %@ OR placeholderValue == %@)", kinds,
                AppCopy.Conversation.placeholder, AppCopy.Conversation.placeholder,
                AppCopy.Conversation.placeholderWhileWorking))
        guard query.firstMatch.waitForExistence(timeout: timeout) else { return nil }
        return query.allElementsBoundByIndex.filter { $0.exists && !$0.frame.isEmpty }
            .max { $0.frame.minY < $1.frame.minY }
    }

    /// Taps a conversation's (or a new one's) message field, whichever words it shows now, so its keyboard comes up.
    func openComposer() -> Bool {
        for placeholder in [AppCopy.Conversation.placeholder, AppCopy.Conversation.placeholderWhileWorking] {
            if let field = element(placeholder, in: Self.fieldTypes, timeout: 0.5), field.isHittable {
                field.tap()
                return true
            }
        }
        return false
    }

    /// Taps the first field labelled or showing `placeholder` (searching the screen as `find` does), so its keyboard
    /// comes up.
    func openField(_ placeholder: String) -> Bool {
        guard let field = find(placeholder, in: Self.fieldTypes, timeout: 2), field.isHittable else { return false }
        field.tap()
        return true
    }

    /// What the person can tap to leave the screen: the tab bar, or Back. Nil when neither is there. A bar shrunk to
    /// fewer buttons than the four tabs is reported on its own (U-55): it reads as "the tabs can't be reached".
    func chromeInReach() -> String? {
        let bar = app.tabBars.firstMatch
        if bar.exists {
            let buttons = bar.buttons
            var reachable = 0
            for index in 0..<min(buttons.count, 6) where buttons.element(boundBy: index).isHittable {
                reachable += 1
            }
            if reachable >= Self.tabCount { return "the tab bar" }
            if reachable > 0 {
                note(
                    "The tab bar is shrunk to \(reachable) of its \(Self.tabCount) buttons: the other tabs can't be seen.",
                    kind: .observation)
                return "the shrunk tab bar"
            }
        }
        return backButton() == nil ? nil : "Back"
    }

    /// The app's tabs: Pebble, Chats, Reviews and Settings (IA rule 2).
    static let tabCount = 4

    /// A sheet's own way out, in its bar: Cancel, Done or Close; while an alert with a field is up in the sheet (Details'
    /// Send input), the alert's Cancel.
    func sheetExitInReach() -> String? {
        let alertCancel = app.alerts.firstMatch.buttons[AppCopy.Common.cancel]
        if alertCancel.exists, alertCancel.isHittable { return "the alert's “\(AppCopy.Common.cancel)”" }
        for bar in app.navigationBars.allElementsBoundByIndex.reversed() where bar.exists {
            for label in [AppCopy.Common.cancel, AppCopy.Common.done, AppCopy.Common.close] {
                let button = bar.buttons[label]
                if button.exists, button.isHittable { return "its “\(label)”" }
            }
        }
        return nil
    }

    /// After a failed check: closes the keyboard the ways a person finally would, and says so if even that fails.
    func forceCloseKeyboard(_ what: String) {
        if hideKeyboard() { return }
        perform(.emptySubmit)
        pause(0.6)
        if app.keyboards.firstMatch.exists {
            closeOverlays()
        }
        if app.keyboards.firstMatch.exists {
            note("Keyboard: \(what)'s keyboard stayed up after every way out the audit knows.", kind: .keyboardTrap)
        }
    }
}
