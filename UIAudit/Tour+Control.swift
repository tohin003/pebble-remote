import PebbleDesign
import PebbleProtocol
import XCTest

extension AuditSession {
    /// Settings (round 2, lane W: once Control; `AppCopy.Tabs.control` carries the new name).
    ///
    /// The tab shows Pebble's Settings in its sidebar's order: Models, Permissions, Memory, Skills & connectors, Data &
    /// storage, Privacy & Stealth. Then come the iPhone section, Appearance and General, then Across Conversations.
    ///
    /// The tour covers:
    /// - Stop Everything while Pebble works;
    /// - each of Pebble's settings (Full access asks first);
    /// - Stealth Lockdown;
    /// - the lists: Toolbox, Schedules (with New Schedule's keyboard), Shared Windows;
    /// - the iPhone section: Connection with Forget This Mac, and Paired iPhones;
    /// - Recently Deleted's shortcut to Chats;
    /// - every other control on the form;
    /// - last, leaving the demo.
    ///
    /// Keep Awake and Mac Screen moved to the Pebble tab (U-36), and the Pebble tab's tour visits them there.
    func tourControl() {
        launch(pace: 6)
        openTab(AppCopy.Tabs.control)
        snap("settings-top")
        dumpTree("settings")

        // Stop Everything (Across Conversations) asks first, only while something runs: the login fix, in its first
        // minute.
        if tap(AppCopy.Control.stopEverything, in: [.button]) {
            snap("settings-stop-everything-question")
            closeOverlays()
        }
        // Pebble's settings while the login fix still works: the accessory shows on the Settings root only, never on
        // these pages (round 2, U-04), so their photos show whether it stays away.
        pebbleSettings()

        toRoot(of: AppCopy.Tabs.control)
        scrollToTop()
        var page = 0
        while page < 6, scrollDown() {
            page += 1
            snap("settings-page-\(page + 1)")
        }

        // Stealth Lockdown (Privacy & Stealth): on (the Veil on every pebble), then off again.
        toRoot(of: AppCopy.Tabs.control)
        if tap(AppCopy.Stealth.name, in: [.switch, .toggle, .button]) {
            pause(2)
            snap("settings-stealth-lockdown-on")
            tap(AppCopy.Stealth.name, in: [.switch, .toggle, .button])
            pause(1)
        }
        usageTelemetry()

        lists()
        skillsAndConnectors()
        iPhoneSection()
        recentlyDeletedShortcut()
        dataStorage()
        // Memory last before the sweep: the login fix has ended by now, and Forget waits while a task works.
        memoryTour()

        toRoot(of: AppCopy.Tabs.control)
        scrollToTop()
        sweep("settings", maxTaps: 30) { self.toRoot(of: AppCopy.Tabs.control) }

        // Last, because it starts over: Leave the Demo, in the iPhone section (in the audit a fresh demo; never a Mac).
        toRoot(of: AppCopy.Tabs.control)
        if tap(AppCopy.Settings.leaveDemo, in: [.button]) {
            pause(2)
            snap("settings-left-the-demo")
        }
    }

    /// Pebble's own settings, each opened and tried once, in the Mac's sidebar order.
    private func pebbleSettings() {
        visitControlRow(AppCopy.Control.permissions, as: "settings-how-pebble-acts") {
            if tap(ModeCopy.for(.auto).name, in: [.button, .cell]) {
                pause(1)
                snap("settings-how-pebble-acts-auto")
            }
            // Full access asks first, with a red "Use Full Access" (round 2, U-50): photographed, then cancelled.
            if tap(ModeCopy.for(.full).name, in: [.button, .cell]) {
                fullAccessQuestion("settings-how-pebble-acts")
            }
            scrollDown()
            snap("settings-available-tools")
            if let tool = AppCopy.PebbleSettings.toolOrder.first,
                tap(AppCopy.PebbleSettings.tool(tool), in: [.switch, .toggle, .button])
            {
                pause(1)
                snap("settings-a-tool-switched")
            }
            // Lane S (SP-14): Pebble's Shell's websites and folders, photographed; Remove is never tapped.
            if tap(AppCopy.ShellAccess.row, in: [.button, .cell]) {
                screen = "shell-grants"
                pause(1)
                snap("settings-pebbles-shell")
                goBack()
                screen = "settings-how-pebble-acts"
            }
            scrollToTop()
            tap(ModeCopy.for(.ask).name, in: [.button, .cell])
        }
        visitControlRow(AppCopy.Control.model, as: "settings-models") {
            // A model other than the one Pebble uses (the chosen row is marked selected).
            if let other = firstRow() {
                press(other)
                pause(1.5)
                snap("settings-models-chose-another")
            }
            // Lane S (SM-10): with the demo's model file in use (Pebble refuses the switch while a task works), Load
            // Now under its row loads it and Rest Model rests it again.
            if shows(AppCopy.LocalModel.load), tap(AppCopy.LocalModel.load, in: [.button], scroll: false) {
                pause(1.5)
                snap("settings-models-file-loaded", audit: false)
                if tap(AppCopy.LocalModel.rest, in: [.button], scroll: false) {
                    pause(1)
                }
            }
        }
        visitControlRow(AppCopy.Control.effort, as: "settings-effort")
        visitControlRow(AppCopy.Control.fastReplies, as: "settings-fast-replies") {
            if tap(AppCopy.Control.fastRepliesName(.always), in: [.button, .cell]) {
                pause(1)
                snap("settings-fast-replies-always")
            }
        }
        // Memory's row reads "Remember useful context" since round 2; the screen inside has the switch of that name.
        // It is switched off and on again, so memory is on for the memory tour later.
        visitControlRow(AppCopy.PebbleSettings.rememberContext, as: "settings-memory") {
            if tap(AppCopy.PebbleSettings.rememberContext, in: [.switch, .toggle]) {
                pause(1)
                snap("settings-memory-switched")
                tap(AppCopy.PebbleSettings.rememberContext, in: [.switch, .toggle])
                pause(1)
            }
        }
        visitControlRow(AppCopy.PebbleSettings.appearance, as: "settings-appearance-on-your-mac") {
            chooseAnother(AppCopy.PebbleSettings.theme, shot: "settings-mac-theme", named: "Theme")
            scrollDown()
            snap("settings-appearance-on-your-mac-further")
        }
        visitControlRow(AppCopy.SettingsTab.notificationsOnYourMac, as: "settings-notifications-on-your-mac") {
            scrollDown()
            snap("settings-notifications-further")
            // Lane S (SG-13): the Delivery block; one schedule's banners muted, then back on (nothing else changes).
            let schedule = "Weekly commit summary"
            if tap(AppCopy.Delivery.label(schedule, muted: false), in: [.button]) {
                pause(1)
                snap("settings-notifications-delivery-muted", audit: false)
                tap(AppCopy.Delivery.label(schedule, muted: true), in: [.button])
                pause(1)
            }
        }
    }

    /// Skills & connectors' Toolbox, and Across Conversations' Schedules (with New Schedule's keyboard) and Shared
    /// Windows.
    private func lists() {
        visitControlRow(AppCopy.Control.toolbox, as: "settings-toolbox") {
            if let row = firstRow(), swipeRow(row.name, left: true) {
                snap("settings-toolbox-swipe", audit: false)
                closeOverlays()
            }
        }
        visitControlRow(AppCopy.Control.schedules, as: "settings-schedules") {
            if tap(AppCopy.NewSchedule.add, in: [.button]) {
                screen = "new-schedule"
                pause(1)
                snap("settings-new-schedule")
                // Each field's keyboard closes on Return with nothing typed (lane W's keyboard rule); Cancel stays in
                // reach.
                keyboardCheck(
                    "New Schedule's name", shot: "new-schedule-name", exit: .emptySubmit, inSheet: true,
                    open: { openField(AppCopy.NewSchedule.name) })
                keyboardCheck(
                    "New Schedule's task", shot: "new-schedule-task", exit: .emptySubmit, inSheet: true,
                    open: { openField(AppCopy.NewSchedule.task) })
                type("Morning summary", into: AppCopy.NewSchedule.name)
                type("Summarize what changed overnight in pebble-web.", into: AppCopy.NewSchedule.task)
                if tap(AppCopy.NewSchedule.review, in: [.button]) {
                    pause(1.5)
                    snap("settings-new-schedule-review")
                }
                leaveSheet("New Schedule")
            }
        }
        visitControlRow(AppCopy.Control.sharedWindows, as: "settings-shared-windows")
    }

    /// Lane S (SK-04 to SK-09): Skills and Connectors, with the "On your Mac" row for Remove and sign-in; the demo's
    /// skill (its Review, then a reference file and Load Next Page) and its connector's Review. Enable and Disable are
    /// never tapped: they change what Pebble may reach.
    private func skillsAndConnectors() {
        visitControlRow(AppCopy.Skills.title, as: "settings-skills-and-connectors") {
            if tap("Release checklist", in: [.button, .cell]) {
                screen = "skill-review"
                pause(1)
                snap("skill-review")
                if tap("references/steps.md", in: [.button, .cell]) {
                    screen = "skill-text"
                    pause(1.5)
                    snap("skill-reference-text")
                    if tap(AppCopy.Skills.loadNextPage, in: [.button]) {
                        pause(1.5)
                        snap("skill-reference-text-next-page", audit: false)
                    }
                    goBack()
                }
                goBack()
            }
            if tap("GitHub", in: [.button, .cell]) {
                screen = "connector-review"
                pause(1)
                snap("connector-review")
                scrollDown()
                snap("connector-review-further", audit: false)
                goBack()
            }
            screen = "settings-skills-and-connectors"
        }
    }

    /// The iPhone section (round 2, lane W: where the Mac has its iPhone tab): the section itself, Connection with
    /// Forget This Mac at its bottom (asked, never confirmed), and Paired iPhones.
    private func iPhoneSection() {
        toRoot(of: AppCopy.Tabs.control)
        if find(AppCopy.Connection.title, in: [.button, .cell]) != nil {
            snap("settings-iphone-section")
        }
        visitControlRow(AppCopy.Connection.title, as: "settings-connection") {
            scrollDown()
            snap("settings-connection-further")
            if tap(AppCopy.Settings.forgetMac, in: [.button]) {
                snap("settings-forget-this-mac-question")
                closeOverlays()
            }
        }
        visitControlRow(AppCopy.Devices.title, as: "settings-paired-iphones")
    }

    /// Settings › Memory (lane Z): the layer rows with their counts; one layer ("Your preferences", where the demo's
    /// contested pair lives): its switch, Search with its keyboard, and a long press on a memory, whose menu offers Copy
    /// and Forget; Forget's question gets Keep. Then the contested memories' three decisions, each question
    /// cancelled. Copy is never tapped (it writes the person's clipboard) and nothing is forgotten; in the demo the
    /// elevated steps agree by themselves, so no Face ID prompt can hold the tour.
    /// Lane S adds New Memory (opened, then cancelled), Learning Candidates, and Forget All Memories' question,
    /// answered Keep Them.
    private func memoryTour() {
        visitControlRow(AppCopy.PebbleSettings.rememberContext, as: "settings-memory-layers") {
            scrollDown()
            snap("settings-memory-layers-further")
            scrollToTop()
            if tap(SettingsCopy.Memory.layerName("profile"), in: [.button, .cell]) {
                screen = "memory-layer"
                pause(1.5)
                snap("memory-layer-your-preferences")
                // Inside this closure a local function isn't on the main actor unless it says so.
                @MainActor func openSearch() -> Bool {
                    let field = app.searchFields.firstMatch
                    if !field.waitForExistence(timeout: 2) || !field.isHittable {
                        scrollUp()
                    }
                    guard field.exists, field.isHittable else { return false }
                    field.tap()
                    return true
                }
                keyboardCheck("Search this layer", shot: "memory-search", exit: .swipeDown, open: { openSearch() })
                if openSearch() {
                    app.typeText("spelling")
                    pause(1.5)
                    snap("memory-search-spelling")
                }
                if let menu = longPress(containing: "British spelling") {
                    if menu.isEmpty {
                        note("A long press on a memory shows no menu.", kind: .observation)
                    } else {
                        snap("memory-long-press-menu", audit: false)
                        if pick(AppCopy.Memories.forget, in: menu) {
                            pause(0.6)
                            snap("memory-forget-question", audit: false)
                            answerSafely(AppCopy.Memories.keep)
                        }
                    }
                }
                endSearch("Search this layer")
                addMemorySheet()
                goBack()
            }
            // The contested memories (Keep This, Remove This, Keep Both): each opens its question, which Cancel closes.
            for decision in ["keep", "reject", "keep_both"] {
                let label = AppCopy.Memories.decision(decision)
                askThenDecline(label, shot: "memory-contest-\(Self.slug(label))")
            }
            learningCandidates()
            // Lane S (SY-19): Forget All Memories asks first; the tour answers Keep Them, never Forget Permanently.
            askThenDecline(AppCopy.Learning.forgetAll, shot: "memory-forget-all", safe: AppCopy.Learning.keepThem)
        }
    }

    /// Lane S (SY-16): a layer's "Add" in the bar opens New Memory: its field's keyboard, the recall scope, then
    /// Cancel. Nothing is saved.
    private func addMemorySheet() {
        let add = AppCopy.Learning.addLayer(SettingsCopy.Memory.layerName("profile"))
        guard tap(add, in: [.button], scroll: false) else { return }
        screen = "new-memory"
        pause(1)
        snap("memory-new-memory")
        keyboardCheck(
            "New Memory's words", shot: "new-memory-words", exit: .emptySubmit, inSheet: true,
            open: { openField(AppCopy.Learning.placeholder) })
        // The scope is a menu when Pebble knows projects (the demo does): opened, photographed, closed unchanged.
        if let menu = openMenu(AppCopy.Learning.recallScope, in: [.button, .cell]) {
            snap("memory-new-memory-scope", audit: false)
            closeMenu(menu)
        }
        leaveSheet("New Memory")
        screen = "memory-layer"
    }

    /// Lane S (SY-12, SY-13): Learning Candidates, one list by layer: photographed, then Check Waiting Memories Now
    /// (the demo's upkeep saves its waiting test recipe). Use This Value and Keep Current are the person's decisions:
    /// never tapped.
    private func learningCandidates() {
        guard tap(AppCopy.Learning.title, in: [.button, .cell]) else { return }
        screen = "learning-candidates"
        pause(1)
        snap("memory-learning-candidates")
        if tap(AppCopy.Learning.checkNow, in: [.button]) {
            pause(1.5)
            snap("memory-learning-candidates-checked", audit: false)
        }
        goBack()
        screen = "settings-memory-layers"
    }

    /// Lane S (SS-03, SS-06): Usage Telemetry, off as the demo starts. What each event can contain opens; "I have read
    /// this notice…" is switched on (Turn On wakes) and off again. Turn On is never tapped: telemetry stays off.
    private func usageTelemetry() {
        visitControlRow(AppCopy.Telemetry.title, as: "settings-usage-telemetry") {
            if tap(AppCopy.Telemetry.whatEachEventHolds, in: [.button, .cell]) {
                pause(0.6)
                snap("settings-usage-telemetry-fields", audit: false)
            }
            if tap(AppCopy.Telemetry.agree, in: [.switch, .toggle]) {
                pause(0.6)
                snap("settings-usage-telemetry-notice-read", audit: false)
                tap(AppCopy.Telemetry.agree, in: [.switch, .toggle])
                pause(0.6)
            }
        }
    }

    /// Lane S (SD-11, SD-12, SD-14, SD-15): Manage Data. Recent Changes from Your Files opens, Update Copies Now runs
    /// (the demo forgets its waiting deletion), and each Delete all question is answered Keep: nothing is deleted.
    private func dataStorage() {
        visitControlRow(AppCopy.DataStorage.manage, as: "settings-manage-data") {
            pause(1.5)  // Pebble measures its folders for this page
            if tap(AppCopy.DataStorage.recentChanges, in: [.button, .cell]) {
                pause(0.6)
                snap("settings-manage-data-recent-changes", audit: false)
            }
            if tap(AppCopy.DataStorage.updateCopies, in: [.button]) {
                pause(1.5)
                snap("settings-manage-data-copies-updated", audit: false)
            }
            // Delete All Now shows only while Recently deleted holds a conversation (an earlier tour may have put one
            // there).
            if shows(AppCopy.DataStorage.deleteAllNow) {
                askThenDecline(
                    AppCopy.DataStorage.deleteAllNow, shot: "settings-delete-all-now", safe: AppCopy.DataStorage.keep)
            }
            askThenDecline(
                AppCopy.DataStorage.deleteAllConversations, shot: "settings-delete-all-conversations",
                safe: AppCopy.DataStorage.keep)
        }
    }

    /// Data & storage's "Recently Deleted · In Chats": a shortcut that switches to Chats and opens the list there.
    private func recentlyDeletedShortcut() {
        toRoot(of: AppCopy.Tabs.control)
        guard tap(AppCopy.Deleted.title, in: [.button, .cell]) else { return }
        pause(1)
        screen = "settings-recently-deleted-shortcut"
        snap("settings-recently-deleted-opens-it-in-chats")
        toRoot(of: AppCopy.Tabs.chats)
    }
}
