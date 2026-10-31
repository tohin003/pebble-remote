import Foundation
import PebbleProtocol
import Testing

@testable import PebbleDesign

/// The words and colours ported from Pebble equal Pebble's own sources, read (read-only) from the Pebble checkout that
/// `PEBBLE_CHECKOUT` names; without it these tests are skipped. When Pebble changes a word or a token, these fail until
/// PebbleDesign changes with it.
/// Where Pebble's checkout is, if `PEBBLE_CHECKOUT` names one.
nonisolated enum PebbleCheckout {
    static let url: URL? = {
        guard let path = ProcessInfo.processInfo.environment["PEBBLE_CHECKOUT"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("src/statusWords.ts").path) ? url : nil
    }()
}

@Suite(.enabled(if: PebbleCheckout.url != nil))
struct PebbleParityTests {
    static func read(_ relative: String) throws -> String {
        try String(contentsOf: try #require(PebbleCheckout.url).appendingPathComponent(relative), encoding: .utf8)
    }

    /// The double-quoted JS string literals in `text`, unescaped, outside `//` comments.
    static func jsStrings(_ text: String) -> [String] {
        var out: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var code = String(line)
            if let comment = code.range(of: #"(^|\s)//"#, options: .regularExpression) { code = String(code[..<comment.lowerBound]) }
            let regex = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                guard let r = Range(match.range(at: 1), in: code) else { continue }
                out.append(String(code[r]).replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\\"#, with: "\\"))
            }
        }
        return out
    }

    /// The text between `start` and the next `end` after it.
    static func block(_ text: String, from start: String, to end: String) throws -> String {
        let s = try #require(text.range(of: start))
        let e = try #require(text.range(of: end, range: s.upperBound..<text.endIndex))
        return String(text[s.upperBound..<e.lowerBound])
    }

    static func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    @Test func statusWordsAndLabelsAreWordForWord() throws {
        let source = try Self.read("src/statusWords.ts")
        let words = try Self.block(source, from: "export const STATUS_WORDS", to: "});")
        var parsedWords: [String: [String]] = [:]
        for line in words.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^[a-z]+:\s*\["#, options: .regularExpression) != nil,
                let colon = trimmed.firstIndex(of: ":")
            else { continue }
            parsedWords[String(trimmed[..<colon])] = Self.jsStrings(String(trimmed[colon...]))
        }
        #expect(parsedWords.count == StatusKey.allCases.count)
        for key in StatusKey.allCases {
            #expect(StatusCopy.words[key] == parsedWords[key.rawValue], "STATUS_WORDS.\(key)")
        }
        let labels = try Self.block(source, from: "export const STATUS_LABELS", to: "});")
        var parsedLabels: [String: String] = [:]
        for line in labels.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^[a-z]+:\s*""#, options: .regularExpression) != nil,
                let colon = trimmed.firstIndex(of: ":"), let text = Self.jsStrings(String(trimmed[colon...])).first
            else { continue }
            parsedLabels[String(trimmed[..<colon])] = text
        }
        for key in StatusKey.allCases {
            #expect(StatusCopy.labels[key] == parsedLabels[key.rawValue], "STATUS_LABELS.\(key)")
        }
        #expect(source.contains("export const FINISHED_LABEL = \"\(StatusCopy.finishedLabel)\";"))
        #expect(source.contains("export const ROTATE_MS = 3000;") && source.contains("export const ANNOUNCE_MS = 10000;"))
        #expect(source.contains("if (!isStatusKey(key)) return \"\(StatusCopy.fallbackWord)\";"))
    }

    @Test func permissionModesAreWordForWord() throws {
        let source = try Self.read("src/permissionModes.ts")
        let modes = try Self.block(source, from: "export const MODES", to: "export const MODE_IDS")
        let regex = try NSRegularExpression(
            pattern: #"mode\(\s*"(\w+)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",?\s*\)"#)
        let matches = regex.matches(in: modes, range: NSRange(modes.startIndex..., in: modes))
        #expect(matches.count == 3)
        for match in matches {
            let field = { (i: Int) in String(modes[Range(match.range(at: i), in: modes)!]) }
            let mode = try #require(PermissionMode(rawValue: field(1)))
            let copy = ModeCopy.for(mode)
            #expect(copy.name == field(2))
            #expect(copy.runsWithoutAsking == field(3))
            #expect(copy.alwaysAsks == field(4))
        }
        let every = try Self.block(source, from: "export const EVERY_MODE =", to: ";\n")
        #expect(Self.jsStrings(every).first == ModeCopy.everyMode)
        #expect(source.contains(#"MODE_IDS: readonly PermissionMode[] = Object.freeze(["ask", "auto", "full"]"#))
    }

    @Test func tokensEqualTokensCSS() throws {
        let css = try Self.read("src/tokens.css")
        func tokens(_ selector: String) throws -> [String: String] {
            let body = try Self.block(css, from: selector + " {", to: "}")
            var out: [String: String] = [:]
            let regex = try NSRegularExpression(pattern: #"--([a-z0-9-]+):\s*([^;]+);"#)
            for m in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                out[String(body[Range(m.range(at: 1), in: body)!])] = String(body[Range(m.range(at: 2), in: body)!])
                    .trimmingCharacters(in: .whitespaces)
            }
            return out
        }
        let light = try tokens(":root")
        let dark = light.merging(try tokens(#":root[data-theme="dark"]"#)) { $1 }
        func resolve(_ theme: [String: String], _ name: String, depth: Int = 0) -> PebbleRGB? {
            guard depth < 8, let value = theme[name] else { return nil }
            if value.hasPrefix("var(--") { return resolve(theme, String(value.dropFirst(6).dropLast()), depth: depth + 1) }
            return PebbleRGB(css: value)
        }
        for token in PebbleToken.allCases {
            #expect(resolve(light, token.cssName) == token.light, "light --\(token.cssName)")
            #expect(resolve(dark, token.cssName) == token.dark, "dark --\(token.cssName)")
        }
        // every colour token in tokens.css is ported (a new one fails here until it is added)
        let colours = light.keys.filter { resolve(light, $0) != nil }
        let ported = Set(PebbleToken.allCases.map(\.cssName))
        #expect(Set(colours).subtracting(ported).isEmpty, "\(Set(colours).subtracting(ported))")
        #expect(light["space-1"] == "4px" && light["radius-lg"] == "12px")
    }

    @Test func stealthWordsAreWordForWord() throws {
        let veil = try Self.read("src/stealthVeil.ts")
        #expect(Self.jsStrings(try Self.block(veil, from: "export const STEALTH_HONEST =", to: ";\n")).first == AppCopy.Stealth.honest)
        #expect(Self.jsStrings(try Self.block(veil, from: "export const STEALTH_ON_TEXT =", to: ";\n")).first == AppCopy.Stealth.onText)
        #expect(Self.jsStrings(try Self.block(veil, from: "export const STEALTH_OFF_TEXT =", to: ";\n")).first == AppCopy.Stealth.offText)
        #expect(veil.contains("export const ACTIVATE = 1.25;") && veil.contains("export const RELEASE = 0.65;"))
        #expect(veil.contains("export const GLASS_OPACITY = 0.7;") && veil.contains("export const SHIMMER_EVERY = 6;"))
        let app = try Self.read("src/App.vue")
        #expect(app.contains(AppCopy.Stealth.description))
    }

    @Test func reviewWordsAreWordForWord() throws {
        let app = try Self.read("src/App.vue")
        let review = try Self.read("src/components/ActionReview.vue")
        // ActionReview.vue's kind labels
        let pairs: [(String, CardKind)] = [
            ("git", .git), ("worktree", .worktree), ("install", .install), ("tests", .tests), ("command", .command),
            ("shell", .shell), ("file", .file), ("screen", .screen), ("screen_grant", .screenGrant), ("url", .url),
            ("screen_raise", .screenRaise), ("app_action", .appAction), ("browser_grant", .browserGrant),
        ]
        for (key, kind) in pairs {
            #expect(review.contains("\(key): '\(ReviewCopy.kindLabel(kind))'"), "labels.\(key)")
        }
        // ACTION_STATES
        for status in ["pending", "applied", "rejected", "undone", "running", "failed", "expired", "superseded", "approved", "held"] {
            #expect(app.contains("\(status): \"\(ReviewCopy.state(status))\""), "ACTION_STATES.\(status)")
        }
        // actionLead's sentences (static ones in full; built ones by their fixed parts)
        let leads = [
            ReviewCopy.leadEdit(newFile: false), ReviewCopy.leadEdit(newFile: true),
            ReviewCopy.leadTests(check: true, checkRun: true), ReviewCopy.leadTests(check: true, checkRun: false),
            ReviewCopy.leadTests(check: false, checkRun: false), ReviewCopy.leadCommand(writable: true),
            ReviewCopy.leadCommand(writable: false), ReviewCopy.leadPlugin, ReviewCopy.leadGit(undo: true),
            ReviewCopy.leadGit(undo: false), ReviewCopy.leadWorktree(retire: true), ReviewCopy.leadWorktree(retire: false),
            ReviewCopy.leadInstall, ReviewCopy.leadApp(background: true), ReviewCopy.leadApp(background: false),
            ReviewCopy.leadShell, ReviewCopy.leadFile, ReviewCopy.leadScreen(sending: true, typing: false),
            ReviewCopy.leadScreen(sending: false, typing: true), ReviewCopy.leadScreen(sending: false, typing: false),
            ReviewCopy.leadURL, ReviewCopy.leadScreenRaise, ReviewCopy.leadAppAction,
            ReviewCopy.leadBrowserGrant(window: false),
        ]
        for lead in leads { #expect(app.contains(lead), "actionLead: \(lead)") }
        for part in [
            "Lets Pebble see and use this one window in this conversation, for up to 15 minutes",
            "In Full access Pebble runs the presses your messages ask for; anything that may spend money still asks.",
            "Most presses still ask you first.", ReviewCopy.leadScreenGrant(filePanel: true, screenshots: false, fullAccess: false),
            " If macOS asks whether Pebble may bypass its window picker, choose Allow for the pictures.",
        ] {
            #expect(app.contains(part), "screen_grant: \(part)")
        }
        // the approve buttons' words, title-cased here
        for word in ["Apply edit", "Run tests", "Run command", "Call plugin", "Run Git plan", "Retire worktree",
                     "Create worktree", "Install from lockfile", "Write file", "Do it", "Allow", "Open link",
                     "Bring forward", "Open app", "Don't allow"] {
            #expect(app.contains(word), "button: \(word)")
        }
    }

    @Test func settingsWordsAreWordForWord() throws {
        let settings = try Self.read("src/components/AdvancedSettings.vue")
        for value in FastReplies.allCases {
            #expect(settings.contains("name: \"\(AppCopy.Control.fastRepliesName(value))\", detail: \"\(AppCopy.Control.fastRepliesDetail(value))\""))
        }
        let collapsed = Self.collapse(settings)
        #expect(collapsed.contains(AppCopy.Control.fastRepliesNote))
        #expect(collapsed.contains(AppCopy.Control.fullAccessWarning))
        #expect(settings.contains("Runs without asking: {{") && settings.contains("Always asks: {{"))
        #expect(settings.contains("HOW PEBBLE ACTS"))
    }

    /// Pebble's settings words, found in Pebble's sources (whitespace collapsed, as a template wraps lines).
    @Test func pebbleSettingsWordsAreWordForWord() throws {
        let sources: [String: String] = try [
            "settings": Self.collapse(Self.read("src/components/AdvancedSettings.vue")),
            "app": Self.collapse(Self.read("src/App.vue")),
            "notify": Self.collapse(Self.read("src/components/NotificationSettings.vue")),
            "storage": Self.collapse(Self.read("src/components/StorageSettings.vue")),
            "screens": Self.collapse(Self.read("src/components/ScreenSessions.vue")),
            "workflows": Self.collapse(Self.read("src/components/CompanionWorkflows.vue")),
            "memory": Self.collapse(Self.read("backend/pebble/memory.py")),
        ]
        typealias P = SettingsCopy.Permissions
        var expected: [(String, String)] = [
            ("settings", P.webDestination), ("settings", P.terminalNote), ("settings", P.captureNote),
            ("settings", P.screenNote), ("settings", P.protectedPlaces), ("settings", P.toolsNoteOnMac),
            ("settings", SettingsCopy.Memory.enabled), ("settings", SettingsCopy.Memory.enabledDetailOnMac),
            ("settings", SettingsCopy.Memory.layersNote), ("settings", SettingsCopy.Memory.layerSwitch),
            ("settings", SettingsCopy.Memory.candidatesNote), ("settings", SettingsCopy.Memory.nothingSaved),
            ("app", SettingsCopy.Memory.forgetNote),
            ("settings", SettingsCopy.Toolbox.workshopNote), ("settings", SettingsCopy.Toolbox.note),
            ("app", SettingsCopy.Models.noEffortControl),
            ("app", SettingsCopy.Models.effortControls),
            ("app", SettingsCopy.Appearance.reduceMotion), ("app", SettingsCopy.Appearance.reduceMotionDetail),
            ("app", SettingsCopy.Appearance.followPointer), ("app", SettingsCopy.Appearance.followPointerDetail),
            ("app", SettingsCopy.Appearance.followPointerOffDetail), ("app", SettingsCopy.Appearance.reactions),
            ("app", SettingsCopy.Appearance.reactionsDetail), ("app", SettingsCopy.Appearance.reactionsOffDetail),
            ("app", SettingsCopy.Appearance.statusWords), ("app", SettingsCopy.Appearance.statusWordsDetail),
            ("app", SettingsCopy.Appearance.uiGuidance), ("app", SettingsCopy.Appearance.uiGuidanceDetail),
            ("app", SettingsCopy.Conversations.moveConfirmOnMac("TITLE").replacingOccurrences(of: "“TITLE” ", with: "")),
            ("notify", SettingsCopy.Notifications.enabled), ("notify", SettingsCopy.Notifications.replies),
            ("notify", SettingsCopy.Notifications.quiet), ("notify", SettingsCopy.Notifications.quietNote),
            ("notify", SettingsCopy.Notifications.groupingNoteOnMac), ("notify", SettingsCopy.Notifications.unsaved),
            ("notify", SettingsCopy.Notifications.saved), ("notify", SettingsCopy.Notifications.quietTimesInvalid),
            ("notify", SettingsCopy.Notifications.quietTimesSame),
            ("storage", SettingsCopy.Conversations.emptyOnMac),
            ("screens", SettingsCopy.ScreenSessions.note), ("screens", SettingsCopy.ScreenSessions.empty),
            ("screens", SettingsCopy.ScreenSessions.waitingForMessage),
            ("workflows", SettingsCopy.Schedules.note),
        ]
        for key in P.toolOrder { expected.append(("settings", "\(key): \"\(P.toolName(key))\"")) }
        for key in SettingsCopy.Memory.layerOrder {
            expected.append(("memory", "\"\(key)\": \"\(SettingsCopy.Memory.layerName(key))\""))
        }
        for level in ["default", "quick", "think", "none", "minimal", "low", "medium", "high", "xhigh", "max"] {
            expected.append(("app", "\(level): \"\(SettingsCopy.Models.effortName(level))\""))
        }
        for key in SettingsCopy.Notifications.kindOrder {
            expected.append(("notify", "['\(key)', '\(SettingsCopy.Notifications.kind(key))']"))
        }
        for key in SettingsCopy.Notifications.previewOrder {
            expected.append(("notify", "['\(key)', '\(SettingsCopy.Notifications.preview(key))', '\(SettingsCopy.Notifications.previewNote(key))']"))
        }
        for key in ["active", "handoff", "interrupted", "revoked", "expired", "restarted"] {
            expected.append(("screens", "\(key): '\(SettingsCopy.ScreenSessions.state(key))'"))
        }
        for key in ["look", "fill", "press"] {
            expected.append(("screens", "label: '\(SettingsCopy.ScreenSessions.abilityName(key))', actions:"))
            expected.append(("screens", "note: '\(SettingsCopy.ScreenSessions.abilityNote(key) ?? "")'"))
        }
        for key in ["secure_field", "two_factor", "captcha", "login_form", "cross_origin", "paused"] {
            expected.append(("screens", "\(key): '\(SettingsCopy.ScreenSessions.reason(key) ?? "")'"))
        }
        for (source, text) in expected {
            // templates write "&" as "&amp;"
            let shown = try #require(sources[source]).replacingOccurrences(of: "&amp;", with: "&")
            #expect(shown.contains(Self.collapse(text)), "\(source): \(text)")
        }
    }

    /// The words ported for lane E's P1 screens that are Pebble's own.
    @Test func screenWordsThatArePebblesAreWordForWord() throws {
        // Python joins adjacent string literals: drop the quotes between them
        let schema = Self.collapse(try Self.read("backend/pebble/settings_file.py"))
            .replacingOccurrences(of: #"["']\s*["']"#, with: "", options: .regularExpression).lowercased()
        for key in SettingsCopy.GitDecisions.order {
            if let detail = SettingsCopy.GitDecisions.detail(key) {
                #expect(schema.contains(detail.lowercased()), "git_decisions \(key): \(detail)")
            }
        }
        #expect(schema.contains("git actions that are your decision, each on unless you turn it off"))
        #expect(schema.contains("forced pushes, deletions and cleans still wait for your review each time."))
        let app = Self.collapse(try Self.read("src/App.vue"))
        for text in [
            AppCopy.Toolbox.removeConfirm, AppCopy.Toolbox.keepConfirm, AppCopy.Toolbox.kept, AppCopy.Toolbox.keptNote,
            AppCopy.Toolbox.removeNote, AppCopy.Toolbox.keptDone, AppCopy.Toolbox.discarded, "Pebble asks because",
        ] {
            #expect(app.contains(text), "toolbox: \(text)")
        }
        let thinking = try Self.read("src/components/ThinkingDisclosure.vue")
        #expect(thinking.contains(AppCopy.RunDetails.reasoning))
        #expect(thinking.contains("'\(AppCopy.RunDetails.doing)'") && thinking.contains("'\(AppCopy.RunDetails.did)'"))
        let storage = Self.collapse(try Self.read("src/components/StorageSettings.vue"))
        #expect(storage.contains("for good? " + AppCopy.Deleted.confirmMessage))
        #expect(storage.contains("deleted for good after"))
        let notify = Self.collapse(try Self.read("src/components/NotificationSettings.vue"))
        #expect(notify.contains(AppCopy.Notifications.note))
    }
}

extension PebbleParityTests {
    /// The chat's effort menu names each level as Pebble's window does (App.vue `effortLabel`).
    @Test func effortNamesAreWordForWord() throws {
        let app = try Self.read("src/App.vue")
        let start = try #require(app.range(of: "const effortLabel"))
        let end = try #require(app.range(of: "})[level]", range: start.upperBound..<app.endIndex))
        let pairs = app[start.upperBound..<end.lowerBound].matches(of: /(\w+): "([^"]+)"/)
            .map { (level: String($0.output.1), name: String($0.output.2)) }
        #expect(pairs.count >= 10)
        for pair in pairs {
            #expect(AppCopy.Control.effortName(pair.level) == pair.name, "\(pair.level)")
        }
        #expect(AppCopy.Control.effortName("future_level") == "future_level")
    }
}
