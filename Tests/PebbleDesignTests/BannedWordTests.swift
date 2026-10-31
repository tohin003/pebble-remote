import Foundation
import PebbleProtocol
import Testing

@testable import PebbleDesign

/// No internal word reaches the screen (Pebble's jargon.test.mjs, ported). Two checks: every string literal in the
/// files that hold on-screen words (this module, lane A's CardWords and StoreWords, every screen), and the output of
/// every copy function for sample inputs.
struct BannedWordTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func theDetectorMatchesPebbles() {
        #expect(BannedWords.violations(in: "The host said so") == ["host"])
        #expect(BannedWords.violations(in: "Receipts and a Receipt") == ["Receipts", "Receipt"])
        #expect(BannedWords.violations(in: "runtime capacity inference E-B1") == ["runtime", "capacity", "inference", "E-B1"])
        #expect(BannedWords.violations(in: "See Activity & review") == ["Activity & review"])
        #expect(BannedWords.violations(in: "Open Settings → Mods") == ["Settings → Mods"])
        // whole words only
        #expect(BannedWords.isClean("hostname ghost capacitor runtimes receipted"))
        #expect(BannedWords.isClean("Pebble is reading"))
    }

    /// Files whose string literals are words a person can see.
    static func copyFiles() -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for folder in ["Sources/PebbleDesign", "Sources/PebbleRemoteUI"] {
            let url = root.appendingPathComponent(folder)
            guard let walk = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walk where file.pathExtension == "swift" {
                if file.lastPathComponent == "BannedWords.swift" { continue }  // the list itself
                files.append(file)
            }
        }
        for single in ["Sources/PebbleProtocol/CardWords.swift", "Sources/PebbleRemoteKit/Store/StoreWords.swift"] {
            let file = root.appendingPathComponent(single)
            if fm.fileExists(atPath: file.path) { files.append(file) }
        }
        return files
    }

    @Test func noBannedWordInAnyOnScreenLiteral() throws {
        let files = Self.copyFiles()
        #expect(files.count > 20, "the scan found the sources")
        var hits: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for literal in SwiftLiterals.extract(from: source) {
                // As in scripts/lint_copy.py: a literal that must keep such a word (Pebble's field value, never shown)
                // carries `// lint-copy: allow` on its line.
                if lines.indices.contains(literal.line - 1), lines[literal.line - 1].contains("lint-copy: allow") {
                    continue
                }
                let found = BannedWords.violations(in: literal.text)
                if !found.isEmpty {
                    hits.append("\(file.lastPathComponent):\(literal.line): \(found) in \(literal.text.prefix(80))")
                }
            }
        }
        #expect(hits.isEmpty, "plain words needed:\n\(hits.joined(separator: "\n"))")
    }

    @Test func theLexerSeesWhatAPersonSees() {
        let source = #"""
            // host in a comment
            /* runtime /* nested */ capacity */
            let host = "Pebble is \(host) reading"
            let raw = #"a "quoted" word"#
            let multi = """
                Line one
                "quote" inside
                """
            let escaped = "tab\there \u{2192} arrow"
            """#
        let texts = SwiftLiterals.extract(from: source).map(\.text)
        #expect(texts.contains("Pebble is   reading"))
        #expect(texts.contains(#"a "quoted" word"#))
        #expect(texts.contains { $0.contains("Line one") && $0.contains("\"quote\" inside") })
        #expect(texts.contains("tab\there → arrow"))
        #expect(!texts.contains { BannedWords.violations(in: $0).count > 0 })
    }

    @Test func copyFunctionsSayNoBannedWordForAnyInput() {
        var outputs: [String] = []
        for key in StatusKey.allCases {
            outputs += (0..<8).map { StatusCopy.word(for: key, tick: $0, attempt: 2) }
            outputs.append(StatusCopy.label(for: key))
        }
        for mode in PermissionMode.allCases {
            let copy = ModeCopy.for(mode)
            outputs += [copy.name, copy.runsWithoutAsking, copy.alwaysAsks, AppCopy.Control.runsWithoutAskingLine(mode),
                        AppCopy.Control.alwaysAsksLine(mode), AppCopy.Control.permissionsLabel(mode),
                        AppCopy.FaceID.changeMode(to: mode)]
        }
        let kinds: [CardKind] = [
            .edit, .tests, .app, .command, .plugin, .git, .worktree, .install, .shell, .file, .screen, .screenGrant,
            .url, .screenRaise, .appAction, .browserGrant, CardKind(rawValue: "new_kind"),
        ]
        for kind in kinds {
            outputs += [ReviewCopy.kindLabel(kind), AppCopy.Reviews.approve(kind), AppCopy.FaceID.approve(kind, detail: "npm test")]
        }
        for flag in [false, true] {
            outputs += [
                ReviewCopy.leadEdit(newFile: flag, scopeReview: flag ? "A test file your request didn't name." : nil),
                ReviewCopy.leadTests(check: flag, checkRun: flag), ReviewCopy.leadTests(check: flag, checkRun: !flag),
                ReviewCopy.leadCommand(writable: flag), ReviewCopy.leadGit(undo: flag), ReviewCopy.leadWorktree(retire: flag),
                ReviewCopy.leadApp(document: flag ? "notes.txt" : nil, background: flag), ReviewCopy.leadApp(background: !flag),
                ReviewCopy.leadScreen(sending: flag, typing: !flag), ReviewCopy.leadScreen(sending: false, typing: flag),
                ReviewCopy.leadScreenGrant(filePanel: flag, screenshots: flag, fullAccess: !flag),
                ReviewCopy.leadScreenGrant(filePanel: false, screenshots: !flag, fullAccess: flag),
                ReviewCopy.leadBrowserGrant(window: flag, browserName: flag ? "Comet" : nil),
            ]
        }
        outputs += [ReviewCopy.leadPlugin, ReviewCopy.leadInstall, ReviewCopy.leadShell, ReviewCopy.leadFile,
                    ReviewCopy.leadURL, ReviewCopy.leadScreenRaise, ReviewCopy.leadAppAction]
        for status in ["pending", "applied", "rejected", "undone", "running", "failed", "expired", "superseded",
                       "approved", "held", "something_new"] {
            outputs.append(ReviewCopy.state(status))
        }
        for state in [RunState.completed, .stopped, .failed, .interrupted, .paused, .budgetExhausted, .needsReconciliation] {
            outputs.append(RunCopy.endLine(state: state, seconds: 42, steps: 3, retries: 1, waitedSeconds: 61) ?? "")
            outputs.append(RunCopy.endLine(state: state, seconds: nil, countsKnown: false) ?? "")
        }
        for code in ["connection_lost", "bridge_restarted", "too_large", "bad_params", "unreachable", "pin_mismatch",
                     "wrong_bridge", "bad_version", "biometry_unavailable", "keys_unavailable", "protocol",
                     "unknown_device", "revoked", "bad_signature", "replaced", "busy", "bad_code", "unlock_required",
                     "proof_required", "bad_proof", "not_allowed", "pebble_offline"] {
            let words = AppCopy.Errors.forCode(code)
            #expect(words != nil, "words for \(code)")
            outputs.append(words ?? "")
        }
        for value in FastReplies.allCases {
            outputs += [AppCopy.Control.fastRepliesName(value), AppCopy.Control.fastRepliesDetail(value)]
        }
        outputs += [
            AppCopy.Home.waitingCount(1), AppCopy.Home.waitingCount(3), AppCopy.Mac.batteryLine(percent: 80, charging: true, onPower: true),
            AppCopy.Mac.batteryLine(percent: nil, charging: nil, onPower: nil), AppCopy.Connection.reconnecting(attempt: 3),
            AppCopy.Connection.milliseconds(6.2), AppCopy.Settings.expiresIn(days: 3), AppCopy.Unlock.explanation(minutes: 15),
            AppCopy.Unlock.remaining(minutes: 12), AppCopy.Accessibility.waitingItems(2), AppCopy.Pairing.confirm("Studio"),
        ]
        // the P1 screens' functions
        for id in SettingsCopy.Permissions.toolOrder + ["new_tool"] {
            outputs += [AppCopy.PebbleSettings.tool(id), AppCopy.PebbleSettings.toolNote(id) ?? "",
                        SettingsCopy.Permissions.enableReason(id)]
        }
        for id in SettingsCopy.GitDecisions.order {
            outputs += [AppCopy.PebbleSettings.gitDecision(id), AppCopy.PebbleSettings.gitDecisionDetail(id) ?? ""]
        }
        for id in SettingsCopy.Memory.layerOrder { outputs.append(AppCopy.PebbleSettings.layer(id)) }
        for id in ["rotate", "fixed", "off", "light", "dark", "system"] {
            outputs += [AppCopy.PebbleSettings.statusWordsChoice(id), AppCopy.PebbleSettings.themeChoice(id)]
        }
        for id in SettingsCopy.Notifications.kindOrder + SettingsCopy.Notifications.previewOrder {
            outputs += [AppCopy.Notifications.kind(id), AppCopy.Notifications.previewName(id),
                        AppCopy.Notifications.previewNote(id) ?? ""]
        }
        for level in ["default", "quick", "think", "high", "xhigh", "max"] {
            outputs.append(SettingsCopy.Models.effortChoice(level, recommended: true))
        }
        for key in ["active", "handoff", "interrupted", "revoked", "expired", "restarted", "gone"] {
            outputs.append(SettingsCopy.ScreenSessions.state(key))
        }
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        outputs += [
            AppCopy.MacScreen.display(2), AppCopy.MacScreen.takenAt("09:12"), AppCopy.Deleted.deletesOn("27 Nov"),
            AppCopy.NewSchedule.everyHours(1), AppCopy.NewSchedule.everyHours(3), AppCopy.Sessions.until("09:30"),
            AppCopy.Toolbox.asksBecause("it reads files"), AppCopy.Schedules.next("tomorrow"),
            AppCopy.Schedules.resumeTitle("Morning check"), AppCopy.Schedules.deleteTitle("Morning check"),
            AppCopy.Schedules.resumeMessage(mode: .ask, modelName: "A model", nextRun: day),
            AppCopy.Schedules.resumeMessage(mode: nil, modelName: nil, nextRun: nil), AppCopy.Devices.thisPhone("iPhone"),
            AppCopy.Devices.lastSeen("now"), AppCopy.Devices.remove("iPhone"),
            SettingsCopy.ScreenSessions.abilities(["look", "press"]), SettingsCopy.ScreenSessions.remaining(minutes: 3),
            SettingsCopy.ScreenSessions.turn(reasons: ["secure_field", "captcha"], tab: true),
            SettingsCopy.Toolbox.toolLine(purpose: "Converts units", keptByPebble: true, uses: 1, needsAttention: true),
            SettingsCopy.Toolbox.removedLine(minutesLeft: 4), SettingsCopy.Conversations.purgeConfirm("Fix login"),
            SettingsCopy.Conversations.moveConfirm("Fix login"), SettingsCopy.Screenshot.imageLabel(display: 0, taken: day),
            AppCopy.Conversation.open,
        ]
        let hits = outputs.filter { !BannedWords.isClean($0) }
        #expect(hits.isEmpty, "\(hits)")
        // no stray spaces, except Pebble's suffixes that follow a state (" · Ends in about 3 minutes")
        #expect(outputs.allSatisfy { $0.hasPrefix(" · ") || $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
}
