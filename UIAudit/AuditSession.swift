import PebbleDesign
import XCTest

/// One area of lane U's audit (`docs/lanes/U-brief.md`). It drives Pebble Remote's in-app demo the way a curious
/// first-time user would: it opens each screen, photographs each state as `NNN-screen-state` (kept in the result
/// bundle) and runs the accessibility audit on it. Every step is guarded: a control that isn't there, can't be tapped
/// or does nothing becomes a finding in the log, never a failure, and the tour carries on.
@MainActor
final class AuditSession {
    enum Look: String {
        case standard
        /// The largest accessibility text size, for this app only (a launch argument; the phone's setting is untouched).
        case largestText = "xxxl"
        /// Dark, for this app only (the DEBUG hook's `-PebbleUIAuditAppearance dark`; the phone's setting is untouched).
        case dark
        /// Light, the same way: the other appearance when the phone itself is dark.
        case light

        /// The appearance the phone isn't in, so the audit sees both (the phone's own setting is only read).
        @MainActor static var otherAppearance: Look {
            XCUIDevice.shared.appearance == .dark ? .light : .dark
        }
    }

    enum Kind: String {
        /// A control the tour expected isn't on screen.
        case missing
        /// It's there but can't be tapped: covered, or out of reach.
        case notTappable = "not-tappable"
        /// It's dimmed.
        case disabled
        /// Tapping it changed nothing a person could see.
        case noResponse = "no-response"
        case crashed
        /// A tap took the person out of the app.
        case leftApp = "left-app"
        /// The way back from a screen wasn't there; the audit relaunched.
        case stuck
        /// A control with no name for VoiceOver.
        case unlabeled
        /// Something the review should look at (an alert's words, a state the tour met).
        case observation
        /// The harness itself: an XCTest issue, an audit that didn't run, the time limit.
        case harness
        /// A keyboard check that passed (the person's P1 of 2026-10-30): it closed without sending, and the tab bar or
        /// Back (or a sheet's Cancel or Done) could be tapped.
        case keyboard
        /// A keyboard check that failed: the keyboard stayed, or nothing could be tapped to leave afterwards.
        case keyboardTrap = "keyboard-trap"
    }

    /// Screenshots are numbered in the order they were taken, across the run (XCTest runs the areas in name order).
    private static var shots = 0
    /// What a person can tap or type in.
    static let controlTypes: [XCUIElement.ElementType] = [
        .button, .link, .switch, .toggle, .menuItem, .cell, .textField, .textView, .searchField, .secureTextField,
        .segmentedControl, .slider, .stepper, .picker, .datePicker,
    ]
    /// Where a label sits when it isn't on a control: a row's text, an image.
    static let textTypes: [XCUIElement.ElementType] = [.staticText, .other, .image]
    static let fieldTypes: [XCUIElement.ElementType] = [.textField, .textView, .searchField, .secureTextField]

    let area: String
    let app = XCUIApplication()
    let log: AuditLog
    private let test: XCTestCase
    /// The sweep's time, in seconds (scaled); its clock starts when the sweep does, so the tour itself always finishes.
    private let sweepBudget: TimeInterval
    private var deadline = Date.distantFuture
    /// Where the tour is, for findings and screenshot names.
    var screen = "start"
    /// "screen|label" of each control the tour tapped, so a sweep doesn't tap it again.
    var tapped: Set<String> = []
    /// Places already audited (in each look): a sweep audits a screen once.
    var audited: Set<String> = []
    private(set) var look: Look = .standard
    private(set) var pace: Double = 1

    /// - Parameter minutes: this area's time for its sweep; `PEBBLE_AUDIT_TIME_SCALE` in the test's environment
    ///   (`TEST_RUNNER_PEBBLE_AUDIT_TIME_SCALE=0.5` before the xcodebuild command) scales every sweep's time.
    init(_ test: XCTestCase, area: String, log: AuditLog, minutes: Double) {
        self.test = test
        self.area = area
        self.log = log
        let scale = ProcessInfo.processInfo.environment["PEBBLE_AUDIT_TIME_SCALE"].flatMap(Double.init) ?? 1
        sweepBudget = minutes * 60 * max(scale, 0.05)
    }

    var hasTime: Bool { Date() < deadline }

    /// Starts the sweep's clock.
    func startSweepClock() {
        deadline = Date().addingTimeInterval(sweepBudget)
    }

    // MARK: - Launching

    /// Launches the Debug app straight into its demo (`-PebbleUIAudit 1`): no Mac, no Face ID, no app lock.
    /// - Parameter pace: the demo's pace; 6 keeps the demo's live run going for about a minute.
    func launch(pace: Double = 1, look: Look = .standard) {
        self.pace = pace
        self.look = look
        var arguments = ["-PebbleUIAudit", "1", "-PebbleUIAuditPace", String(pace)]
        switch look {
        case .standard:
            break
        case .largestText:
            arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        case .dark:
            arguments += ["-PebbleUIAuditAppearance", "dark"]
        case .light:
            arguments += ["-PebbleUIAuditAppearance", "light"]
        }
        app.launchArguments = arguments
        app.launch()
        screen = "pebble"
        if !app.tabBars.firstMatch.waitForExistence(timeout: 20) {
            note("The tab bar didn't appear within 20 s of launching.", kind: .harness)
        }
        pause(1.2)  // the demo connects and Pebble's state arrives
    }

    /// A fresh demo with the same pace and look.
    func relaunch() {
        launch(pace: pace, look: look)
    }

    // MARK: - Screenshots, the accessibility audit, findings

    /// A screenshot of the whole screen, named `NNN-state` (plus the look), kept in the result bundle; then the
    /// accessibility audit of this state.
    ///
    /// Never of the system's share sheet: it shows the person's own contacts. If one is up, the
    /// number is used without a picture, the sheet is closed at once, and a finding says so.
    @discardableResult
    func snap(_ state: String, audit: Bool = true) -> String {
        Self.shots += 1
        let suffix = look == .standard ? "" : "-\(look.rawValue)"
        let name = String(format: "%03d-", Self.shots) + Self.slug(state + suffix)
        if shareSheetShows() {
            note(
                "A share sheet was up at \(name): not photographed (it shows the person's contacts), closed at once.",
                kind: .observation)
            closeShareSheet()
            return name
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot(), quality: .medium)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        if audit { runAudit(name) }
        return name
    }

    /// `performAccessibilityAudit()` on what is on screen now. Every issue is recorded (with the element it names),
    /// and the handler returns true, so an issue never fails the run.
    func runAudit(_ shot: String) {
        var found: [XCUIAccessibilityAuditIssue] = []
        // A screen still settling can time the audit out (the handoff's, [143]-[145]): once more after a moment.
        for attempt in 1...2 {
            found = []
            do {
                try app.performAccessibilityAudit(for: .all) { issue in
                    found.append(issue)
                    return true
                }
                break
            } catch {
                if attempt == 1 {
                    pause(1.5)
                    continue
                }
                note("The accessibility audit didn't run on \(shot), twice: \(error.localizedDescription)", kind: .harness)
            }
        }
        for (index, issue) in found.enumerated() {
            log.add(
                AuditLog.Issue(
                    shot: shot, area: area, screen: screen, type: Self.name(of: issue.auditType),
                    compact: issue.compactDescription, detailed: issue.detailedDescription,
                    element: index < 30 ? describe(issue.element) : nil))
        }
    }

    func note(_ detail: String, kind: Kind) {
        log.add(AuditLog.Finding(shot: Self.shots, area: area, screen: screen, kind: kind.rawValue, detail: detail))
    }

    /// The accessibility tree as XCUITest sees it: for fixing the tour's selectors when the app changes.
    func dumpTree(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "tree-\(Self.slug(name)).txt"
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    /// The area's findings and accessibility issues, as JSON attachments.
    func finish() {
        for attachment in log.attachments(for: area) {
            test.add(attachment)
        }
    }

    private func describe(_ element: XCUIElement?) -> String? {
        guard let element, element.exists, let shot = try? element.snapshot() else { return nil }
        let frame = shot.frame
        return "\(Self.name(of: shot.elementType)) “\(shot.label)”"
            + (shot.identifier.isEmpty ? "" : " #\(shot.identifier)")
            + " at \(Int(frame.minX)),\(Int(frame.minY)), \(Int(frame.width))×\(Int(frame.height)) pt"
    }

    // MARK: - Finding things

    /// The element labelled `label` (or with that identifier or placeholder), or one whose label starts with it, among
    /// `types`: an exact match first, then one that can be tapped. One query, so a label SwiftUI extends ("Auto in
    /// project, Runs without asking: ...") costs no extra wait. Waits up to `timeout` for it to appear.
    func element(
        _ label: String, in types: [XCUIElement.ElementType] = controlTypes, timeout: TimeInterval = 3
    ) -> XCUIElement? {
        let kinds = types.map { NSNumber(value: $0.rawValue) }
        let query = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "(label == %@ OR identifier == %@ OR placeholderValue == %@ OR label BEGINSWITH %@) AND elementType IN %@",
                label, label, label, label, kinds))
        guard query.firstMatch.waitForExistence(timeout: timeout) else { return nil }
        let count = min(query.count, 8)
        var firstHittable: XCUIElement?
        for index in 0..<count {
            let candidate = query.element(boundBy: index)
            guard candidate.isHittable else { continue }
            if candidate.label == label || candidate.identifier == label { return candidate }
            if firstHittable == nil { firstHittable = candidate }
        }
        return firstHittable ?? query.firstMatch
    }

    /// `element(_:in:timeout:)`, scrolling down (then back up) through the screen when it isn't there yet or lies
    /// outside the screen. One that is on screen but covered (by the keyboard, say) is returned as it is: scrolling
    /// wouldn't uncover it.
    func find(
        _ label: String, in types: [XCUIElement.ElementType] = controlTypes, timeout: TimeInterval = 3,
        scroll: Bool = true
    ) -> XCUIElement? {
        let found = element(label, in: types, timeout: timeout)
        if let found, found.isHittable || isOnScreen(found) || !scroll { return found }
        guard scroll else { return nil }
        // Down until the content stops moving, then up the same way: a long screen (the Settings root) is more than
        // three pages ([148]).
        for down in [true, false] {
            for _ in 0..<12 {
                let moved = down ? scrollDown() : scrollUp()
                if let found = element(label, in: types, timeout: 0.2), found.isHittable { return found }
                if !moved { break }
            }
        }
        return element(label, in: types, timeout: 0)
    }

    /// Whether the element's frame lies inside the screen (even if something covers it).
    func isOnScreen(_ element: XCUIElement) -> Bool {
        let frame = element.frame
        let screen = app.frame
        return !frame.isEmpty && frame.minY >= screen.minY && frame.maxY <= screen.maxY
    }

    /// Whether `label` shows anywhere now (text or control).
    func shows(_ label: String, timeout: TimeInterval = 0) -> Bool {
        element(label, in: Self.controlTypes + Self.textTypes, timeout: timeout) != nil
    }

    /// Waits until something labelled `label` shows (or, with `gone`, is gone).
    @discardableResult
    func wait(for label: String, gone: Bool = false, timeout: TimeInterval) -> Bool {
        let query = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label))
        return gone
            ? query.firstMatch.waitForNonExistence(timeout: timeout)
            : query.firstMatch.waitForExistence(timeout: timeout)
    }

    func hittable(in query: XCUIElementQuery) -> XCUIElement {
        for index in 0..<min(query.count, 8) {
            let candidate = query.element(boundBy: index)
            if candidate.isHittable { return candidate }
        }
        return query.firstMatch
    }

    // MARK: - Tapping and typing

    /// Taps the control labelled `label` as a person would (scrolling to it when it's further down). If it can't be
    /// found or tapped, that is a finding, and the tour goes on.
    @discardableResult
    func tap(
        _ label: String, in types: [XCUIElement.ElementType]? = nil, timeout: TimeInterval = 3, scroll: Bool = true
    ) -> Bool {
        var element = find(label, in: types ?? Self.controlTypes, timeout: timeout, scroll: scroll)
        if element == nil, types == nil {
            element = find(label, in: Self.textTypes, timeout: 0.3, scroll: false)
        }
        guard let element else {
            note("Couldn't find “\(label)”.", kind: .missing)
            return false
        }
        return tap(element, named: label)
    }

    /// Taps the first element matching `predicate` (for words Pebble fills in, like counts).
    @discardableResult
    func tap(where predicate: NSPredicate, named name: String, timeout: TimeInterval = 3) -> Bool {
        let query = app.descendants(matching: .any).matching(predicate)
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            note("Couldn't find \(name).", kind: .missing)
            return false
        }
        return tap(hittable(in: query), named: name)
    }

    @discardableResult
    func tap(_ element: XCUIElement, named label: String) -> Bool {
        guard element.exists else {
            note("“\(label)” went away before it could be tapped.", kind: .missing)
            return false
        }
        guard element.isHittable || bringToMiddle(element) else {
            note("“\(label)” is there but can't be tapped (covered, or out of reach).", kind: .notTappable)
            return false
        }
        guard element.isEnabled else {
            note("“\(label)” is dimmed here.", kind: .disabled)
            return false
        }
        switch element.elementType {
        case .switch, .toggle: flip(element)
        default: element.tap()
        }
        tapped.insert("\(screen)|\(label)")
        pause(0.8)
        return stillRunning(after: label)
    }

    /// A switch row: its knob, at the trailing end (tapping a SwiftUI Toggle row's label does nothing).
    func flip(_ toggle: XCUIElement) {
        let knob = toggle.descendants(matching: .switch).firstMatch
        if knob.exists, knob.isHittable {
            knob.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }

    /// Types into the field whose label or placeholder is `field`: tap it, then type, as a person does.
    /// - Parameter scroll: look further down the screen for it (not for a composer, which is always in view).
    @discardableResult
    func type(_ text: String, into field: String, scroll: Bool = true) -> Bool {
        guard let element = find(field, in: Self.fieldTypes, timeout: 3, scroll: scroll) else {
            note("Couldn't find the field “\(field)”.", kind: .missing)
            return false
        }
        guard tap(element, named: field) else { return false }
        pause(0.4)
        app.typeText(text)
        pause(0.4)
        return true
    }

    /// Long-presses `label` and returns what appeared (a context menu's items), or nil when it isn't there.
    func longPress(_ label: String, in types: [XCUIElement.ElementType]? = nil) -> [Control]? {
        guard let element = find(label, in: types ?? Self.controlTypes + Self.textTypes, timeout: 3) else {
            note("Couldn't find “\(label)” to long-press.", kind: .missing)
            return nil
        }
        let before = Set(controls().map(\.key))
        element.press(forDuration: 1.2)
        pause(0.8)
        guard stillRunning(after: "long press on \(label)") else { return nil }
        return controls().filter { !before.contains($0.key) }
    }

    /// Swipes a list row to show its swipe actions: left for the trailing ones, right for the leading ones.
    @discardableResult
    func swipeRow(_ title: String, left: Bool) -> Bool {
        let row = app.cells.containing(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        let target: XCUIElement? =
            row.waitForExistence(timeout: 2) ? row : find(title, in: [.button, .staticText], timeout: 2)
        guard let target, target.exists else {
            note("Couldn't find the row “\(title)” to swipe.", kind: .missing)
            return false
        }
        if left { target.swipeLeft() } else { target.swipeRight() }
        pause(0.7)
        return true
    }

    // MARK: - Moving around

    /// Selects a tab. The tab bar collapses to the current tab's button while a list scrolls (iOS 26, its value
    /// "Collapsed"); tapping that button opens the bar again, as a person does. At accessibility text sizes a
    /// conversation hides the tab bar altogether (lane V's U-43), so then Back comes first, as a person would go back to
    /// reach the tabs (the re-check's largest-text area stayed in one conversation without this).
    @discardableResult
    func openTab(_ name: String) -> Bool {
        closeOverlays()
        // Back first whenever no tab can be tapped: a bar hidden at accessibility sizes (a conversation, a new one) can
        // still be in the tree, and a tap where its tab would be landed on the new conversation's field ([217]-[219]).
        if !tabBarInReach() {
            for _ in 0..<4 where !tabBarInReach() && backButton() != nil {
                goBack()
            }
        }
        let tab = app.tabBars.buttons[name].firstMatch
        if !tab.waitForExistence(timeout: 1) || !tab.isHittable {
            let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == 'Collapsed'")).firstMatch
            if collapsed.exists, collapsed.isHittable {
                collapsed.tap()
                pause(0.6)
            }
            if !tab.waitForExistence(timeout: 1) || !tab.isHittable {
                drag(from: 0.32, to: 0.72)
                _ = tab.waitForExistence(timeout: 1)
            }
        }
        guard tab.exists else {
            note("There is no “\(name)” tab.", kind: .missing)
            return false
        }
        if tab.isHittable {
            tab.tap()
        } else if tabBarInReach() {
            tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            note("No tab can be tapped here, and there is no Back: “\(name)” can't be reached.", kind: .stuck)
            return false
        }
        screen = Self.slug(name)
        pause(0.7)
        return stillRunning(after: "the \(name) tab")
    }

    /// Whether any of the tab bar's buttons can be tapped (a shrunk bar's one button counts: tapping it opens the bar).
    func tabBarInReach() -> Bool {
        let bar = app.tabBars.firstMatch
        guard bar.exists else { return false }
        let buttons = bar.buttons
        for index in 0..<min(buttons.count, 6) where buttons.element(boundBy: index).isHittable {
            return true
        }
        return false
    }

    /// The tab's first screen, popping whatever it had pushed.
    @discardableResult
    func toRoot(of tab: String) -> Bool {
        guard openTab(tab) else { return false }
        for _ in 0..<5 where backButton() != nil {
            goBack()
        }
        screen = Self.slug(tab)
        return true
    }

    /// Opens a conversation from the Chats tab's list.
    ///
    /// A row low on the screen can lie under the tab bar's accessory, which takes the tap: in the re-check, taps on
    /// "Send the weekly update in Mail" opened the accessory's conversation (U-04). So a low row is scrolled up first; the
    /// Chats tour records what lies under the accessory, so the problem is still seen.
    @discardableResult
    func openChat(_ title: String) -> Bool {
        guard toRoot(of: AppCopy.Tabs.chats) else { return false }
        if let row = element(title, in: [.button, .cell, .staticText], timeout: 2),
            row.frame.maxY > app.frame.height * 0.7
        {
            drag(from: 0.62, to: 0.32)
        }
        guard open(title, in: [.button, .cell, .staticText]) else { return false }
        screen = Self.slug(title)
        return true
    }

    /// Taps `label` and says whether it opened something (a page or a sheet: the place changed). A tap that opened
    /// nothing is tried once more, then it is a finding with the control's frame, and the caller doesn't act on a
    /// screen that isn't there ([171], [224]: a row's tap opened nothing, and the next step acted on the list).
    func open(_ label: String, in types: [XCUIElement.ElementType]) -> Bool {
        let before = place()
        guard tap(label, in: types) else { return false }
        if place() != before { return true }
        pause(0.8)
        if place() != before { return true }
        let control = element(label, in: types, timeout: 0.5)
        if let control, control.exists, control.isHittable {
            control.tap()
            pause(1)
            if place() != before { return true }
        }
        let frame = control?.frame ?? .zero
        note(
            "Tapping “\(label)” at \(Int(frame.minX)),\(Int(frame.minY)), \(Int(frame.width))×\(Int(frame.height)) pt opened "
                + "nothing, twice.",
            kind: .noResponse)
        return false
    }

    /// The ways out a sheet's own bar offers; never a Back button.
    static let sheetWays: Set<String> = [AppCopy.Common.cancel, AppCopy.Common.close, AppCopy.Common.done]

    /// The navigation bar's Back button, in a sheet's bar first: UIKit's `BackButton`, or a bar's leading button named
    /// after the screen it returns to.
    func backButton() -> XCUIElement? {
        for bar in app.navigationBars.allElementsBoundByIndex.reversed() where bar.exists {
            let back = bar.buttons.matching(NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'"))
                .firstMatch
            if back.exists, back.isHittable { return back }
            let leading = bar.buttons.allElementsBoundByIndex.first { button in
                button.exists && button.isHittable && button.frame.minX < 40 && !Self.sheetWays.contains(button.label)
            }
            if let leading { return leading }
        }
        return nil
    }

    /// Back, with the Back button, or by swiping from the screen's leading edge when there isn't one.
    @discardableResult
    func goBack() -> Bool {
        if let back = backButton() {
            back.tap()
            pause(0.7)
            return true
        }
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        pause(0.7)
        return false
    }

    /// Scrolls the content about a page further down. Returns whether anything moved (the controls on screen changed).
    @discardableResult
    func scrollDown() -> Bool {
        moved { drag(from: 0.72, to: 0.32) }
    }

    @discardableResult
    func scrollUp() -> Bool {
        moved { drag(from: 0.32, to: 0.72) }
    }

    /// Back to the top of the screen's content, as far as it goes (at most six pages).
    func scrollToTop() {
        var moves = 0
        while moves < 6, scrollUp() {
            moves += 1
        }
    }

    /// Pull to refresh, from the top of a list.
    func pullToRefresh() {
        drag(from: 0.25, to: 0.75)
        pause(1)
    }

    private func moved(_ scroll: () -> Void) -> Bool {
        let before = controls().map(\.key)
        scroll()
        return controls().map(\.key) != before
    }

    /// A quick drag, as a person flicks a list (a slow one took six seconds a page on the iPhone).
    private func drag(from start: CGFloat, to end: CGFloat) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start))
        from.press(
            forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end)),
            withVelocity: .fast, thenHoldForDuration: 0)
        pause(0.5)
    }

    // MARK: - Backing out

    /// Backs out of whatever covers the screen, the way a person does, never choosing a destructive button: an alert's
    /// Cancel or OK, a dialog's Cancel, the keyboard, a sheet's Cancel, Done or Close.
    func closeOverlays() {
        for _ in 0..<4 {
            if closeAlert() || closeDialog() || hideKeyboard() || closeSheet() { continue }
            return
        }
    }

    /// An alert: noted with its words (Pebble's refusals arrive as alerts), then closed.
    @discardableResult
    func closeAlert() -> Bool {
        let alert = app.alerts.firstMatch
        guard alert.exists else { return false }
        // Read once, while it is there: a gone alert's label would stop the whole test.
        let words = alert.label
        note("An alert said: “\(words)”.", kind: .observation)
        for label in [AppCopy.Common.cancel, AppCopy.Common.close, AppCopy.Common.ok, AppCopy.Common.done] {
            let button = alert.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                pause(0.6)
                return true
            }
        }
        note("An alert had no Cancel, Close or OK: “\(words)”.", kind: .observation)
        return false
    }

    /// A confirmation dialog: its Cancel, else a tap beside it.
    @discardableResult
    func closeDialog() -> Bool {
        let dialog = app.sheets.firstMatch
        guard dialog.exists else { return false }
        let cancel = dialog.buttons[AppCopy.Common.cancel]
        if cancel.exists, cancel.isHittable {
            cancel.tap()
        } else {
            tapAway(from: dialog.frame)
        }
        pause(0.6)
        return true
    }

    /// The keyboard, by scrolling the content a little (this app's lists hide it as they scroll). Lists that close it
    /// interactively (round 2: `.scrollDismissesKeyboard(.interactively)`) need the drag to run into the keyboard, so a
    /// longer drag follows when the short one didn't close it.
    @discardableResult
    func hideKeyboard() -> Bool {
        guard app.keyboards.firstMatch.exists else { return false }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        pause(0.6)
        if app.keyboards.firstMatch.exists {
            swipeDownThroughKeyboard()
        }
        return !app.keyboards.firstMatch.exists
    }

    /// A swipe down that starts on the content and runs through the keyboard, as a person pulls a keyboard away: it
    /// closes one whose screen dismisses it on scrolling, immediately or interactively.
    func swipeDownThroughKeyboard() {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)))
        pause(0.8)
    }

    /// A sheet's own way out: Cancel, Done or Close in its bar (the system's pickers and share sheet included).
    @discardableResult
    func closeSheet() -> Bool {
        settle()
        let ways = [AppCopy.Common.cancel, AppCopy.Common.done, AppCopy.Common.close]
        for bar in app.navigationBars.allElementsBoundByIndex.reversed() where bar.exists {
            for label in ways {
                let button = bar.buttons[label]
                if button.exists, button.isHittable {
                    button.tap()
                    pause(0.8)
                    return true
                }
            }
        }
        // A sheet's bar isn't always a navigation bar to XCUITest (Details' Done after a popover closed, [246]): the
        // same buttons anywhere on screen.
        for label in ways {
            let button = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
            if button.exists, button.isHittable {
                button.tap()
                pause(0.8)
                return true
            }
        }
        return false
    }

    /// Waits for an alert or a popover that is closing to be gone, so the next query sees the screen under it: right
    /// after one closed, Details' segments and Done weren't found ([246], [250]).
    func settle(timeout: TimeInterval = 2) {
        _ = app.alerts.firstMatch.waitForNonExistence(timeout: timeout)
        let popover = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'PopoverDismissRegion' OR label == 'dismiss popup'")
        ).firstMatch
        _ = popover.waitForNonExistence(timeout: timeout)
    }

    /// An element on screen but covered (under the tab bar, a bar's edge): its content dragged toward the middle of
    /// the screen, once. Returns whether it can be tapped now ([095]: Accept as Unverified lay under the tab bar).
    func bringToMiddle(_ element: XCUIElement) -> Bool {
        let frame = element.frame
        let screen = app.frame
        guard !frame.isEmpty, frame.intersects(screen) else { return false }
        let distance = frame.midY - screen.midY
        guard abs(distance) > 44 else { return element.isHittable }
        // From the screen's left margin, where no row's control sits, by the distance; held at the end, so the list
        // stops where it is put.
        let startY = distance > 0 ? screen.height * 0.75 : screen.height * 0.25
        let endY = min(max(startY - distance, screen.height * 0.15), screen.height * 0.85)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: 12, dy: startY)).press(
            forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 12, dy: endY)), withVelocity: .slow,
            thenHoldForDuration: 0.2)
        pause(0.5)
        return element.exists && element.isHittable
    }

    /// The system share sheet's own list, and targets only it offers (`neverTap` keeps the sweeps away from them).
    static let shareSheetIDs = ["ActivityListView", "UIActivityContentView"]
    static let shareSheetLabels = ["AirDrop", "Edit Actions…", "Save Image", "Assign to Contact", "Add to Shared Album"]

    /// Whether the system's share sheet is on screen (one query).
    func shareSheetShows() -> Bool {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@ OR label IN %@", Self.shareSheetIDs, Self.shareSheetLabels)
        ).firstMatch.exists
    }

    /// Closes the share sheet without using it: its own Close or Cancel, else a drag down from its top edge (a drag,
    /// never a tap, so no contact or target in it can act).
    func closeShareSheet() {
        if closeSheet(), !shareSheetShows() { return }
        let list = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", Self.shareSheetIDs)
        ).firstMatch
        if list.exists {
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).press(
                forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
            pause(0.8)
        }
        if shareSheetShows() { swipeSheetDown() }
        if shareSheetShows() { note("The share sheet stayed open after Close and two drags down.", kind: .stuck) }
    }

    /// Drags a sheet down by its top edge, as a person dismisses one that has no button for it.
    func swipeSheetDown() {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
        pause(0.8)
    }

    /// Opens a menu (or anything that adds controls without leaving the screen) and returns what it added.
    func openMenu(_ label: String, in types: [XCUIElement.ElementType]? = nil) -> [Control]? {
        let before = Set(controls().map(\.key))
        guard tap(label, in: types) else { return nil }
        let added = controls().filter { !before.contains($0.key) }
        if added.isEmpty {
            note("“\(label)” opened nothing a person could see.", kind: .noResponse)
            return nil
        }
        return added
    }

    /// Picks `item` in a menu the tour just opened.
    @discardableResult
    func pick(_ item: String, in menu: [Control]) -> Bool {
        if let control = menu.first(where: { $0.label == item }) ?? menu.first(where: { $0.label.hasPrefix(item) }) {
            press(control)
            tapped.insert("\(screen)|\(item)")
            return stillRunning(after: item)
        }
        note("The menu had no “\(item)”; it had: \(menu.map(\.label).filter { !$0.isEmpty }.joined(separator: ", ")).",
            kind: .missing)
        closeMenu(menu)
        return false
    }

    /// Closes a menu by tapping beside it, away from its items, as a person does; nothing when it has closed already.
    func closeMenu(_ items: [Control]) {
        guard let first = items.first(where: { !$0.label.isEmpty }) ?? items.first else { return }
        let still = app.descendants(matching: first.type).matching(NSPredicate(format: "label == %@", first.label))
        guard still.firstMatch.exists else { return }
        tapAway(from: items.reduce(first.frame) { $0.union($1.frame) })
        // At the largest text size a menu can cover every spot `tapAway` tries, and the next step then ran behind it
        // ([212]-[214]): the system's dismiss region, then the screen's top edge.
        guard still.firstMatch.exists else { return }
        let dismiss = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'PopoverDismissRegion' OR label == 'dismiss popup'")
        ).firstMatch
        if dismiss.exists {
            dismiss.tap()
            pause(0.6)
        }
        guard still.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.03)).tap()
        pause(0.6)
        if still.firstMatch.exists {
            note("A menu stayed open after every way to close it the audit knows.", kind: .harness)
        }
    }

    /// A tap on the screen outside `area`: a menu or dialog closes and nothing under the tap acts.
    func tapAway(from area: CGRect) {
        let size = app.frame.size
        let spots = [(0.5, 0.5), (0.12, 0.5), (0.88, 0.5), (0.5, 0.22), (0.5, 0.8), (0.12, 0.25), (0.88, 0.75)]
        for (x, y) in spots {
            let point = CGPoint(x: x * size.width, y: y * size.height)
            if !area.insetBy(dx: -24, dy: -24).contains(point) {
                app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
                pause(0.6)
                return
            }
        }
    }

    // MARK: - Small things

    /// After a tap the app should still be in front. A crash is a finding (then a fresh launch); a link that opened
    /// another app is a finding, and the audit comes back.
    @discardableResult
    func stillRunning(after label: String) -> Bool {
        switch app.state {
        case .runningForeground:
            return true
        case .notRunning, .unknown:
            note("Pebble Remote quit or crashed after “\(label)”.", kind: .crashed)
            relaunch()
            return false
        default:
            note("“\(label)” took the person out of Pebble Remote.", kind: .leftApp)
            snap("\(screen)-left-the-app-after-\(label)", audit: false)
            app.activate()
            pause(1)
            return false
        }
    }

    /// Lets an animation or the demo's next step finish, keeping the run loop going.
    func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    nonisolated static func slug(_ text: String) -> String {
        var slug = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
            } else if slug.last != "-" {
                slug.append("-")
            }
        }
        return String(slug.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(90))
    }

    /// A label as a key: digits become "#", so a ticking time doesn't make a control look new.
    nonisolated static func normalized(_ label: String) -> String {
        String(label.map { $0.isNumber ? "#" : $0 })
    }

    static func name(of type: XCUIAccessibilityAuditType) -> String {
        let known: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "element detection"), (.hitRegion, "hit region"),
            (.sufficientElementDescription, "element description"), (.dynamicType, "Dynamic Type"),
            (.textClipped, "text clipped"), (.trait, "trait"),
        ]
        let names = known.filter { type.contains($0.0) }.map(\.1)
        return names.isEmpty ? "other (\(type.rawValue))" : names.joined(separator: ", ")
    }

    static func name(of type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: "Button"
        case .staticText: "Text"
        case .image: "Image"
        case .cell: "Row"
        case .switch, .toggle: "Switch"
        case .link: "Link"
        case .textField, .textView, .searchField, .secureTextField: "Field"
        case .navigationBar: "Navigation bar"
        case .tabBar: "Tab bar"
        case .menuItem: "Menu item"
        case .other: "Group"
        default: "Element \(type.rawValue)"
        }
    }
}
