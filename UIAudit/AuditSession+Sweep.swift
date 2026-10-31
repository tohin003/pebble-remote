import PebbleDesign
import XCTest

/// What is on screen, from one snapshot of the app, and the sweep that tries every control on a screen.
extension AuditSession {
    /// A control a person could tap, as one snapshot saw it.
    struct Control {
        var type: XCUIElement.ElementType
        var label: String
        var identifier: String
        var frame: CGRect
        var value: String
        var isEnabled: Bool
        var isSelected: Bool

        /// The same control in another snapshot: type, label (digits ignored) and identifier.
        var key: String { "\(type.rawValue)|\(AuditSession.normalized(label))|\(identifier)" }
        /// The same place on screen: a live row whose words change every second is still the same row.
        var spot: String { "\(type.rawValue)@\(Int(frame.midX / 12)),\(Int(frame.midY / 12))" }
        var name: String { label.isEmpty ? identifier : label }
        /// What a tap can change in place: the control itself (gone or new), its value and whether it is selected.
        var state: String { "\(key)|\(AuditSession.normalized(value))|\(isSelected)" }
    }

    /// Where the person is: the navigation bars (and their Back buttons), alerts, dialogs and the keyboard. A tap that
    /// changes it opened something; scrolling doesn't change it.
    struct Place: Equatable {
        var bars: [String] = []
        var backs: [String] = []
        var alerts = 0
        var dialogs = 0
        var keyboard = false
        /// The selected tab (a tap on the bottom accessory moves to Chats).
        var tab = ""
        /// The bars' titles, for telling screens apart (not compared: a large title collapses as the list scrolls).
        var titles: [String] = []

        static func == (lhs: Place, rhs: Place) -> Bool {
            lhs.bars == rhs.bars && lhs.backs == rhs.backs && lhs.alerts == rhs.alerts && lhs.dialogs == rhs.dialogs
                && lhs.keyboard == rhs.keyboard && lhs.tab == rhs.tab
        }

        var description: String {
            "\(tab)|\(bars.joined(separator: ">"))|\(titles.joined(separator: ">"))|a\(alerts)d\(dialogs)k\(keyboard)"
        }
    }

    /// Labels a sweep never taps:
    /// - leaving the demo (it starts the demo over);
    /// - Share, whose sheet shows the person's contacts (U2 brief: never photographed);
    /// - the share sheet's targets, which act outside the app (AirDrop, Messages; saving to Photos asks for access);
    /// - confirming Full access ("Use Full Access") or forgetting the Mac ("Forget Mac"): the audit only ever cancels;
    /// - lane Z's Copy, Copy Code and Open Link (they write the person's clipboard or leave for Safari), Move to
    ///   Recently Deleted and Forget;
    /// - lane Y's confirming and settling buttons (Rewind, Compact now, Cancel agent, abandoning or settling a goal,
    ///   granting a tab, stopping Chrome or Pebble's browser, ending access);
    /// - lane S's buttons in Settings that confirm a deletion or change reach (Forget Permanently, Enable and Disable,
    ///   the two Delete all confirmations, Turn On);
    /// - lane T's Stop view and Delete Pebble's copy (the menu item and the confirmation share their words), and
    ///   Unblock, which changes the person's goal.
    static let neverTap: Set<String> = [
        AppCopy.Settings.leaveDemo, AppCopy.Settings.forgetConfirmButton, "Share", AppCopy.Modes.fullAccessConfirm,
        AppCopy.MessageMenu.copy, AppCopy.MessageMenu.copyCode, AppCopy.MessageMenu.openLink,
        AppCopy.ChatMenu.moveToRecentlyDeleted, AppCopy.Memories.forget, AppCopy.Details.rewindButton(1),
        AppCopy.Details.rewindButton(2), AppCopy.Details.compactNow, AppCopy.Details.cancelAgent,
        AppCopy.Details.abandonConfirm, AppCopy.Details.markDone, AppCopy.Details.accept, AppCopy.Details.reject,
        AppCopy.Details.markMet, AppCopy.Details.markNotMet, AppCopy.Details.verifyEvidence,
        AppCopy.Details.grantThisTab, AppCopy.Details.turnOnScreenAndGrant, AppCopy.Details.stopInChrome,
        AppCopy.Details.stopBrowser, AppCopy.Details.startBrowser, AppCopy.Details.endAccess,
        // Lane G: a row that says only the Mac does it (never a button, and never tapped).
        AppCopy.Views.onYourMac,
        // Lane S: confirming a Settings deletion or a wider reach (the tours open each question, then cancel).
        AppCopy.Learning.forgetPermanently, AppCopy.Skills.enable, AppCopy.Skills.disable,
        AppCopy.DataStorage.purgeAllButton, AppCopy.DataStorage.trashAllButton, AppCopy.Telemetry.turnOn,
        // Lane T: stopping a view, deleting an export's file, unblocking a goal's step.
        AppCopy.ViewHistory.stop, AppCopy.Exports.deleteCopy, AppCopy.Goals.unblock,
        "AirDrop", "Messages", "Mail",
        "Save Image", "Save to Files", "Print", "Edit Actions…", "Add to Photos", "Assign to Contact", "Notes",
        "Reminders", "Freeform", "Add to Reading List", "Add Bookmark", "Markup",
    ]

    // MARK: - Reading the screen

    /// The controls on screen now. Keyboard keys and the tab bar are left out (the tours open tabs themselves), and a
    /// row is left out when it holds a control of its own (the same tap).
    func controls() -> [Control] {
        guard let root = try? app.snapshot() else { return [] }
        let bounds = root.frame
        var found: [Control] = []
        var insideSwitch = false
        func walk(_ node: any XCUIElementSnapshot) {
            switch node.elementType {
            case .keyboard, .tabBar, .statusBar: return
            default: break
            }
            let wasInside = insideSwitch
            defer { insideSwitch = wasInside }
            if Self.controlTypes.contains(node.elementType), !node.frame.isEmpty, node.frame.intersects(bounds),
                !(node.elementType == .cell && (node.label.isEmpty || node.children.contains(where: Self.holdsControl))),
                !(insideSwitch && node.elementType == .switch)
            {
                found.append(
                    Control(
                        type: node.elementType, label: node.label, identifier: node.identifier, frame: node.frame,
                        value: node.value.map { "\($0)" } ?? "", isEnabled: node.isEnabled,
                        isSelected: node.isSelected))
            }
            if node.elementType == .switch || node.elementType == .toggle { insideSwitch = true }
            for child in node.children {
                walk(child)
            }
        }
        walk(root)
        return found
    }

    func place() -> Place {
        guard app.state == .runningForeground, let root = try? app.snapshot() else {
            return Place(bars: ["(not in front)"])
        }
        var place = Place()
        func walk(_ node: any XCUIElementSnapshot, inTabBar: Bool) {
            switch node.elementType {
            case .navigationBar:
                place.bars.append(node.identifier)
                place.titles.append(Self.texts(in: node).joined(separator: " "))
                place.backs.append(contentsOf: Self.backButtons(in: node))
            case .alert:
                place.alerts += 1
            case .sheet, .popover:
                place.dialogs += 1
            case .keyboard:
                place.keyboard = true
                return
            case .button where inTabBar && node.isSelected:
                place.tab = node.label
            default:
                break
            }
            for child in node.children {
                walk(child, inTabBar: inTabBar || node.elementType == .tabBar)
            }
        }
        walk(root, inTabBar: false)
        return place
    }

    /// Taps a control from a snapshot: the element again when it can be found, else the point where it was.
    func press(_ control: Control) {
        let query = app.descendants(matching: control.type).matching(
            NSPredicate(format: "label == %@ AND identifier == %@", control.label, control.identifier))
        let element = query.firstMatch
        if element.exists, element.isHittable {
            if control.type == .switch || control.type == .toggle { flip(element) } else { element.tap() }
        } else {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: control.frame.midX, dy: control.frame.midY)).tap()
        }
        pause(0.8)
    }

    /// Whether this place is new in this look: a sweep audits each screen it opens once.
    func firstVisit(_ place: Place) -> Bool {
        audited.insert("\(look.rawValue)|\(place.description)").inserted
    }

    // MARK: - The sweep

    /// Taps every control on this screen that the tour didn't, one at a time, like someone trying everything once.
    /// What each tap opens is photographed (and audited once per new screen); a menu's items are tried one by one; then
    /// the sweep backs out the way a person would. When the way back is lost it relaunches and `reopen` returns here.
    /// Stops at `maxTaps` or the area's time.
    func sweep(_ name: String, maxTaps: Int = 25, avoid: Set<String> = [], reopen: () -> Bool) {
        screen = name
        startSweepClock()
        var home = place()
        var tried: Set<String> = []
        var taps = 0
        var pages = 0
        while taps < maxTaps {
            guard hasTime else {
                note("The sweep of \(name) stopped at the area's time limit after \(taps) taps.", kind: .harness)
                return
            }
            let shown = controls().filter { control in
                !tried.contains(control.key) && !tried.contains(control.spot) && !avoid.contains(control.label)
                    && isCandidate(control)
            }
            let unnamed = shown.filter { $0.label.isEmpty && $0.identifier.isEmpty }
            if !unnamed.isEmpty {
                // A bar rebuilding (after Retry, [080]) shows its controls a moment before their names: read again.
                pause(0.8)
                let namedNow = Set(controls().filter { !$0.name.isEmpty }.map(\.spot))
                for control in unnamed {
                    tried.insert(control.key)
                    guard !namedNow.contains(control.spot) else { continue }
                    note(
                        "A \(Self.name(of: control.type).lowercased()) at \(Int(control.frame.midX)),\(Int(control.frame.midY)) has no name for VoiceOver.",
                        kind: .unlabeled)
                }
            }
            guard let next = shown.first(where: { !$0.name.isEmpty }) else {
                guard pages < 4, scrollDown() else { return }
                pages += 1
                home = place()
                continue
            }
            tried.insert(next.key)
            tried.insert(next.spot)
            taps += 1
            if !next.isEnabled {
                note("“\(next.name)” is dimmed here.", kind: .disabled)
                continue
            }
            if tryOnce(next, home: home, pages: pages, reopen: reopen) {
                home = place()  // relaunched and came back: the screen is as new
            }
        }
    }

    /// One control in a sweep. Returns whether the app had to be relaunched to get back.
    private func tryOnce(_ control: Control, home: Place, pages: Int, reopen: () -> Bool) -> Bool {
        let shownBefore = controls()
        let before = Set(shownBefore.map(\.key))
        press(control)
        tapped.insert("\(screen)|\(control.name)")
        guard stillRunning(after: control.name) else { return comeBack(pages: pages, reopen: reopen) }
        let now = place()
        if now != home {
            snap("\(screen)-\(control.name)", audit: firstVisit(now))
            return backOut(to: home, pages: pages, reopen: reopen)
        }
        let shownAfter = controls()
        let added = shownAfter.filter { !before.contains($0.key) }
        if !added.isEmpty {
            if shareSheetShows() || added.contains(where: { Self.shareSheetLabels.contains($0.label) }) {
                // The share sheet: never photographed (the person's contacts), never used, closed at once.
                note("“\(control.name)” opened the share sheet: not photographed, closed at once.", kind: .observation)
                closeShareSheet()
                return backOut(to: home, pages: pages, reopen: reopen)
            }
            if isCovered(control) {
                // A menu or popover over the screen: photographed and audited once, then each of its items.
                snap("\(screen)-\(control.name)", audit: audited.insert("\(look.rawValue)|menu|\(screen)|\(control.key)").inserted)
                return tryMenu(opener: control, items: added, home: home, pages: pages, reopen: reopen)
            }
            // New controls in place (a row opened up, a choice was made): the same screen in a new state.
            snap("\(screen)-\(control.name)", audit: false)
            return false
        }
        if control.type == .switch || control.type == .toggle {
            snap("\(screen)-\(control.name)-switched", audit: false)
            return false
        }
        // A choice selected, a value changed, or controls gone (End Access removes its own buttons): a response too
        // ([098], [101]). Digits are ignored, so a ticking time isn't one.
        if Set(shownAfter.map(\.state)) != Set(shownBefore.map(\.state)) {
            snap("\(screen)-\(control.name)", audit: false)
            return false
        }
        note("Tapping “\(control.name)” changed nothing a person could see.", kind: .noResponse)
        return false
    }

    /// A menu (or a popover) the sweep opened: each of its items once, reopening the menu for each.
    private func tryMenu(opener: Control, items: [Control], home: Place, pages: Int, reopen: () -> Bool) -> Bool {
        let choices = items.filter { !$0.name.isEmpty && $0.type != .other && !Self.neverTap.contains($0.label) }
        closeMenu(items)
        var relaunched = false
        for item in choices.prefix(8) where hasTime {
            press(opener)
            let again = controls()
            guard let fresh = again.first(where: { $0.key == item.key }) else {
                note("“\(item.name)” wasn't in “\(opener.name)” the second time.", kind: .observation)
                closeMenu(again.filter { control in items.contains { $0.key == control.key } })
                continue
            }
            let before = Set(again.map(\.key))
            press(fresh)
            tapped.insert("\(screen)|\(item.name)")
            guard stillRunning(after: item.name) else {
                relaunched = comeBack(pages: pages, reopen: reopen) || relaunched
                continue
            }
            let now = place()
            snap("\(screen)-\(opener.name)-\(item.name)", audit: now != home && firstVisit(now))
            let submenu = controls().filter { !before.contains($0.key) }
            if now == home, !submenu.isEmpty { closeMenu(submenu) }
            relaunched = backOut(to: home, pages: pages, reopen: reopen) || relaunched
        }
        return relaunched
    }

    /// Back to `home` the way a person would: close what covers it, then Back; relaunch when nothing works. Returns
    /// whether it relaunched.
    @discardableResult
    func backOut(to home: Place, pages: Int, reopen: () -> Bool) -> Bool {
        for step in 0..<6 {
            let now = place()
            if now == home { return false }
            if now.alerts > 0 || now.dialogs > 0 || now.keyboard {
                closeOverlays()
            } else if !home.tab.isEmpty, now.tab != home.tab {
                openTab(home.tab)
            } else if closeSheet() {
                continue
            } else if now.backs != home.backs, backButton() != nil {
                goBack()
            } else if step >= 2 {
                swipeSheetDown()
            }
        }
        if place() == home { return false }
        note("Couldn't get back to \(screen) the way a person would; relaunched to carry on.", kind: .stuck)
        return comeBack(pages: pages, reopen: reopen)
    }

    /// A fresh launch, back to the screen and as far down it as the sweep had scrolled.
    private func comeBack(pages: Int, reopen: () -> Bool) -> Bool {
        let name = screen
        if app.state == .runningForeground { relaunch() }
        if !reopen() { note("Couldn't reopen \(name) after relaunching.", kind: .harness) }
        screen = name
        for _ in 0..<pages {
            scrollDown()
        }
        return true
    }

    /// Whether something now sits over the control just tapped: an open menu or popover catches the next tap, so the
    /// control can't be reached (or the system's dismiss region is there).
    func isCovered(_ control: Control) -> Bool {
        let dismiss = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'PopoverDismissRegion' OR label == 'dismiss popup'")
        ).firstMatch
        if dismiss.exists { return true }
        let opener = app.descendants(matching: control.type).matching(
            NSPredicate(format: "label == %@ AND identifier == %@", control.label, control.identifier)
        ).firstMatch
        return opener.exists && !opener.isHittable
    }

    private func isCandidate(_ control: Control) -> Bool {
        if Self.neverTap.contains(control.label) || control.label.hasPrefix("Share ") { return false }
        // A link in a reply opens on the iPhone, in Safari: a sweep would leave the app (lane Z's Open Link).
        if control.type == .link { return false }
        if control.identifier == "BackButton" || control.label == "Back" { return false }
        return !tapped.contains("\(screen)|\(control.name)")
    }

    private static func holdsControl(_ node: any XCUIElementSnapshot) -> Bool {
        switch node.elementType {
        case .button, .link, .switch, .toggle, .textField, .textView:
            true
        default:
            node.children.contains(where: holdsControl)
        }
    }

    private static func texts(in node: any XCUIElementSnapshot) -> [String] {
        var texts: [String] = []
        if node.elementType == .staticText, !node.label.isEmpty { texts.append(normalized(node.label)) }
        for child in node.children {
            texts += Self.texts(in: child)
        }
        return texts
    }

    /// A bar's Back buttons: UIKit's `BackButton`, or a leading button that isn't a sheet's Cancel, Close or Done.
    private static func backButtons(in node: any XCUIElementSnapshot) -> [String] {
        var backs: [String] = []
        if node.elementType == .button,
            node.identifier == "BackButton" || node.label == "Back"
                || (node.frame.minX < 40 && !sheetWays.contains(node.label))
        {
            backs.append(node.label)
        }
        for child in node.children {
            backs += Self.backButtons(in: child)
        }
        return backs
    }
}
