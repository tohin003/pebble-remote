import Foundation
import PebbleProtocol
import Testing

@testable import PebbleDesign

/// Lane W's words (UX audit 2026-10-30): no tool, field or state name reaches the screen; waiting states keep one word;
/// apps, sites and paths read as a person names them.
struct StateWordsTests {
    /// Every tool Pebble has (activity_kinds.py, ported in PebbleProtocol).
    static let pebbleTools = StatusKey.toolClasses.flatMap(\.tools)

    /// An internal name: a CamelCase join, an underscore, or a raw code.
    static func looksInternal(_ text: String) -> Bool {
        text.contains("_") || text.range(of: #"[a-z][A-Z]"#, options: .regularExpression) != nil
    }

    // MARK: - U-29: uncertain outcomes

    @Test func noToolOrFieldNameReachesTheScreen() {
        #expect(Self.pebbleTools.count > 80, "the tool list was read")
        for tool in Self.pebbleTools {
            let name = AppCopy.Steps.name(tool: tool, kind: nil)
            #expect(AppCopy.Steps.toolWords[tool] != nil, "\(tool) has words")
            // "Read" may read as "Reading a file"; "ReadGitDiff" or "app_action" may never show.
            #expect(name != tool && !(Self.looksInternal(tool) && name.contains(tool)), "\(tool) shows as \(name)")
            #expect(!Self.looksInternal(name), "\(tool) shows as \(name)")
            #expect(BannedWords.isClean(name), "\(name)")
        }
        // A tool or a kind from a newer Pebble: plain words, never its name.
        for (tool, kind) in [
            ("MakeCoffee", nil), ("Brew_v2", "brew_kind"), (nil, "app_action"), (nil, "file"), ("", ""), (nil, nil),
            ("AppAction", "app_action"), ("ScreenAct", nil),
        ] as [(String?, String?)] {
            let name = AppCopy.Steps.name(tool: tool, kind: kind)
            #expect(!Self.looksInternal(name), "\(String(describing: tool)), \(String(describing: kind)): \(name)")
            for raw in [tool, kind].compactMap({ $0 }) where Self.looksInternal(raw) {
                #expect(!name.contains(raw), "\(raw) shows in \(name)")
            }
        }
        #expect(AppCopy.Steps.name(tool: "MakeCoffee", kind: nil) == AppCopy.Steps.fallback)
        #expect(AppCopy.Steps.name(tool: nil, kind: "app_action") == "An action in an app")
        // The audit's two steps in Mail, as Pebble's activity list names them, with the paused window's app.
        #expect(AppCopy.Steps.name(tool: "AppAction", kind: "app_action", app: "Mail") == "Asking an app to do one thing")
        #expect(AppCopy.Steps.name(tool: "ScreenAct", kind: nil, app: "Mail") == "Acting in Mail\u{2019}s window")
        #expect(AppCopy.Steps.name(tool: "ScreenAct", kind: nil) == "Acting in the app window")
        #expect(AppCopy.Steps.settleLabel("Acting in the app window").hasPrefix("Settle \u{201C}Acting"))
    }

    @Test func theBasisIsWordsOrNothing() {
        // Every basis Pebble's readback sends (reconcile.py `_result` and REASONS).
        let codes = [
            "after_present", "before_present", "absent_on_create", "neither_present", "never_performed", "no_receipt",
            "no_effect_started", "no_admission_record", "refused_before_start", "no_spawn_record", "no_registration",
            "folder_absent", "exit_receipt", "exit_observed", "still_running", "no_broker_action", "not_observable",
            "not_provable_by_reobservation", "indistinguishable", "readback_limit", "root_unavailable", "root_replaced",
            "absent_by_fields", "ambiguous_match", "not_found", "forged", "no_ownership", "ownership_mismatch",
            "malformed", "receipt_inconsistent", "unreadable", "binding_mismatch", "record_missing",
            "repository_unverified", "no_expected_facts", "no_supervisor_record", "supervisor_error", "exit_unobserved",
            "containment_unproven", "storage_unverified", "folder_unverified", "tree_unmeasured", "no_recorded_tree",
            "unsupported_kind", "no_service", "readback_failed", "", "something_new",
        ]
        for code in codes {
            guard let words = AppCopy.Steps.basis(code) else { continue }
            #expect(!Self.looksInternal(words) && !words.contains("Basis"), "\(code): \(words)")
            #expect(BannedWords.isClean(words), "\(code): \(words)")
            #expect(words.hasSuffix("."), "a sentence: \(words)")
        }
        #expect(AppCopy.Steps.basis("after_present") == "Pebble found the change in place.")
        #expect(AppCopy.Steps.basis("neither_present") == nil, "the verdict says it")
        #expect(AppCopy.Steps.basis("something_new") == nil)
    }

    // MARK: - U-33: a command's state

    @Test func aCommandsStateIsASentenceNeverItsCode() {
        for state in ["admitted", "running", "succeeded", "failed", "stopped", "limited", "refused", "unknown", "x_y"] {
            let title = AppCopy.CommandState.title(state)
            #expect(!title.contains("Command:") && !Self.looksInternal(title), "\(state): \(title)")
            #expect(!title.lowercased().contains("unknown"), "\(state): \(title)")
        }
        #expect(AppCopy.CommandState.title("unknown") == "Pebble lost track of a command")
        #expect(AppCopy.CommandState.title("running") == "A command is running")
        #expect(!AppCopy.CommandState.lostTrack.contains("service"))
        #expect(BannedWords.isClean(AppCopy.CommandState.lostTrack))
    }

    // MARK: - U-03, U-13: one state, one word

    @Test func waitingStatesKeepOneWordAndWorkRotatesOnOneClock() {
        for tick in 0..<12 {
            #expect(StatusCopy.word(for: .review, tick: tick) == "Needs your review")
            #expect(StatusCopy.word(for: .question, tick: tick) == "Needs your answer")
        }
        #expect(!StatusCopy.rotates(.review) && !StatusCopy.rotates(.question) && !StatusCopy.rotates(.paused))
        #expect(StatusCopy.rotates(.thinking) && StatusCopy.rotates(.editing))
        // Two views asking at the same moment get the same word, wherever they appeared.
        let now = Date(timeIntervalSinceReferenceDate: 815_000_004)
        #expect(
            StatusCopy.word(for: .thinking, at: now)
                == StatusCopy.word(for: .thinking, shownFor: now.timeIntervalSince(StatusCopy.rotationEpoch)))
        #expect(StatusCopy.word(for: .thinking, at: now, rotate: false) == "Thinking")
        #expect(StatusCopy.word(for: .review, at: now) == "Needs your review")
    }

    // MARK: - U-28, U-40: apps and sites by name

    @Test func appsKeepTheirCapitalsAndSitesShowTheirNames() {
        #expect(AppCopy.Places.appName(bundleID: "com.apple.mail") == "Mail")
        #expect(AppCopy.Places.appName(bundleID: "com.apple.calculator") == "Calculator")
        #expect(AppCopy.Places.appName(bundleID: "com.apple.iCal") == "Calendar")
        #expect(AppCopy.Places.appName(bundleID: "com.apple.TextEdit") == "TextEdit")
        #expect(AppCopy.Places.appName(bundleID: "com.apple.Preview") == "Preview")
        #expect(AppCopy.Places.appName(bundleID: "com.example.MyApp") == "MyApp")
        #expect(AppCopy.Places.appName(bundleID: nil) == nil && AppCopy.Places.appName(bundleID: " ") == nil)
        #expect(AppCopy.Places.site("https://docs.github.com") == "docs.github.com")
        #expect(AppCopy.Places.site("https://www.example.com/guide") == "example.com")
        #expect(AppCopy.Places.site("http://localhost:5173") == "localhost:5173")
        #expect(AppCopy.Places.site("not an address") == "not an address")
        #expect(AppCopy.Places.sites(["https://a.com", "https://b.com", "https://c.com"]) == "a.com and 2 more")
        #expect(AppCopy.Places.sites([]) == nil)
        #expect(BannedWords.isClean(AppCopy.Places.pebbleTab), "never Pebble's retired name for its tab")
    }

    @Test func aPathIsSpokenAsAFileInAFolder() {
        #expect(AppCopy.Paths.spoken("src/settings/ThemeToggle.tsx") == "ThemeToggle.tsx in src/settings")
        #expect(AppCopy.Paths.spoken("/Users/me/notes.txt") == "notes.txt in /Users/me")
        #expect(AppCopy.Paths.spoken("README.md") == nil)
        #expect(AppCopy.Paths.spoken("Run npm test") == nil)
        #expect(AppCopy.Paths.spoken("https://docs.github.com/en") == nil)
        #expect(AppCopy.Paths.spoken("a/b\nc/d") == nil)
    }

    // MARK: - U-07, U-34, U-27, U-47: short words first

    @Test func eachModeHasOneLineAndFullAccessSaysWhatItAllows() {
        for mode in ModeCopy.order {
            let line = AppCopy.Modes.summary(mode)
            #expect(!line.isEmpty && !line.contains("\n") && line.count < 90, "\(mode): \(line)")
            #expect(BannedWords.isClean(line))
        }
        // U-50: the question is two sentences of Pebble's, without an internal name; the rest stays one tap away.
        let message = AppCopy.Modes.fullAccessMessage
        let sentences = message.split(separator: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(sentences.count == 2, "\(message)")
        #expect(message.split(separator: " ").count <= 40, "\(message)")
        #expect(!message.contains("AgentGuard") && BannedWords.isClean(message))
        #expect(AppCopy.Control.fullAccessWarning.hasPrefix(AppCopy.Modes.fullAccessRiskPebble))
    }

    @Test func theHandoffLeadsWithItsDecision() {
        #expect(
            AppCopy.HandoffDecision.question(model: "Qwen 3.5 9B", messages: 2, onMac: true)
                == "Continue this conversation on Qwen 3.5 9B, on your Mac? Pebble sends it 2 messages and starts a new run there.")
        #expect(
            AppCopy.HandoffDecision.question(model: "GPT-5.1", messages: 1, onMac: false)
                == "Continue this conversation on GPT-5.1? Pebble uploads 1 message and starts a new run there.")
        #expect(AppCopy.HandoffDecision.question(model: nil, messages: nil, onMac: true).contains("the model you chose"))
        #expect(AppCopy.HandoffDecision.question(model: "", messages: 0, onMac: true).hasSuffix("No message is sent."))
        for words in [
            AppCopy.HandoffDecision.question(model: "M", messages: 3, onMac: false), AppCopy.SheetActions.review,
            AppCopy.SheetActions.attach,
        ] {
            #expect(!words.contains("route class") && !words.contains("fingerprint") && BannedWords.isClean(words))
        }
        #expect(AppCopy.SheetActions.review.count < AppCopy.TerminalCommand.review.count)
        #expect(AppCopy.SheetActions.attach.count < AppCopy.WebSource.attach.count)
    }

    // MARK: - Fix 7: Settings as the Mac's

    @Test func settingsIsTheMacsSettingsWithItsIPhoneSection() {
        // U-35 and the lead's 23:03 decision: the fourth tab is Settings, Pebble's sections in the Mac's order and
        // words, with one "iPhone" section where the Mac has its iPhone tab (no separate "This iPhone").
        #expect(AppCopy.Tabs.control == "Settings" && AppCopy.Control.title == "Settings")
        #expect(
            AppCopy.SettingsTab.order == [
                "Models", "Permissions", "Memory", "Skills & connectors", "Views", "Data & storage", "Privacy & Stealth",
                "iPhone", "Appearance", "General",
            ])
        #expect(AppCopy.Devices.title == "Paired iPhones", "Pebble's word (RemoteSettings.vue)")
        // The Mac's unlock label with only the place changed, and Pebble's own words for its choices.
        #expect(
            AppCopy.SettingsTab.unlockFor
                == AppCopy.SettingsTab.unlockForPebble.replacingOccurrences(of: "your iPhone", with: "this iPhone"))
        #expect(AppCopy.SettingsTab.unlockTime(minutes: 15) == "15 minutes")
        #expect(AppCopy.SettingsTab.unlockTime(minutes: 60) == "1 hour")
        // U-39: the Mac's notifications say so; U-37: a model on the Mac is "On your Mac", only the place changes.
        #expect(AppCopy.SettingsTab.notificationsOnYourMac == "Notifications on Your Mac")
        #expect(AppCopy.ModelPlace.provider("On this device") == "On your Mac")
        #expect(AppCopy.ModelPlace.provider("on this device") == "On your Mac")
        #expect(AppCopy.ModelPlace.provider("ChatGPT") == "ChatGPT")
        #expect(AppCopy.ModelPlace.provider(nil) == nil && AppCopy.ModelPlace.provider(" ") == nil)
        for words in [
            AppCopy.SettingsTab.connectModelNote, AppCopy.SettingsTab.skillsNote, AppCopy.SettingsTab.storageNote,
            AppCopy.SettingsTab.acrossConversationsNote, AppCopy.SettingsTab.iPhoneNote,
        ] {
            #expect(words.lowercased().contains("on your mac") && BannedWords.isClean(words), "\(words)")
        }
    }
}

/// The fixed phrases lane W takes from Pebble are Pebble's own, in its files (when the checkout is on this Mac).
@Suite(.enabled(if: PebbleCheckout.url != nil))
struct StateWordsParityTests {
    @Test func theWaitingAndHeldPhrasesArePebbles() throws {
        let goals = try PebbleParityTests.read("backend/pebble/goals.py")
        for phrase in StatusCopy.fixedWords.values {
            #expect(goals.contains("'\(phrase)'"), "\(phrase) is Pebble's")
        }
        let companion = try PebbleParityTests.read("src/components/PetRunSummary.vue")
        #expect(companion.contains("\"\(AppCopy.Held.needsVerification.lowercased())\""))
        let runPanel = try PebbleParityTests.read("src/components/RunPanel.vue")
        #expect(runPanel.contains(AppCopy.Held.label.replacingOccurrences(of: "\u{2019}", with: "'")))
    }

    @Test func theStepNamesArePebblesActivityWords() throws {
        let app = try PebbleParityTests.read("backend/pebble/app.py")
        // The tools whose line Pebble writes without a file or an app keep Pebble's words exactly.
        for tool in ["ScreenAct", "ScreenObserve", "AppAction", "OpenURL", "WriteFile", "EditFile", "Shell", "Grep"] {
            let words = try #require(AppCopy.Steps.toolWords[tool])
            #expect(app.contains("'\(tool)': '\(words)'") || app.contains("\"\(tool)\": \"\(words)\""), "\(tool)")
        }
    }

    @Test func theSettingsSectionsArePebblesSidebar() throws {
        // Fix 7: the section names and their order are Pebble's (AdvancedSettings.vue `TAB_LABELS`), its iPhone tab
        // included (the lead's 23:03 decision: one "iPhone" section in the Mac's place).
        let settings = try PebbleParityTests.read("src/components/AdvancedSettings.vue")
        let ids = [
            "models", "permissions", "memory", "extensions", "mods", "storage", "privacy", "iphone", "appearance", "general",
        ]
        #expect(ids.count == AppCopy.SettingsTab.order.count)
        // TAB_LABELS lists the tabs in the sidebar's order, one line each.
        let positions = zip(ids, AppCopy.SettingsTab.order).compactMap { id, label in
            settings.range(of: "  \(id): \"\(label)\",")?.lowerBound
        }
        #expect(positions.count == ids.count, "every section's name is Pebble's")
        #expect(positions == positions.sorted(), "in the Mac's order")
        // The iPhone section's words are the Mac's iPhone tab's (RemoteSettings.vue).
        let remote = try PebbleParityTests.read("src/components/RemoteSettings.vue")
        for words in [AppCopy.Devices.title, AppCopy.SettingsTab.whatYourIPhoneDid, AppCopy.SettingsTab.unlockForPebble] {
            #expect(remote.contains(words), "\(words) is Pebble's")
        }
        #expect(remote.contains("v === 60 ? '1 hour' : v + ' minutes'"), "the unlock time's words")
        let providers = try PebbleParityTests.read("backend/pebble/providers.py")
        #expect(providers.contains("'\(AppCopy.ModelPlace.onThisDevicePebble)'"))
    }

    @Test func anAppDemosFeedbackIsPebblesWords() throws {
        #expect(AppCopy.Views.feedbackDraft(revision: 3, screen: "home") == "Feedback on the app demo (revision 3, screen home): ")
        let window = try PebbleParityTests.read("src/App.vue")
        #expect(window.contains("`Feedback on the app demo (revision ${payload.revision}, screen ${payload.screen_id}): `"))
    }

    @Test func theFullAccessQuestionIsPebblesWords() throws {
        // U-50: the two sentences come from the warning Pebble's Settings show while Full access is on, which wraps over
        // lines in the template: what Pebble does (up to the warning's semicolon), then the risk.
        let settings = try PebbleParityTests.read("src/components/AdvancedSettings.vue")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        #expect(settings.contains(String(AppCopy.Modes.fullAccessSummaryPebble.dropLast()) + ";"))
        #expect(settings.contains(AppCopy.Modes.fullAccessRiskPebble))
    }
}
