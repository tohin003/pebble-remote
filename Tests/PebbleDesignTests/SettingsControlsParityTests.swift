import Foundation
import PebbleProtocol
import Testing

@testable import PebbleDesign

/// Lane S: the words of the Settings controls that were "On your Mac" rows are Pebble's own, found in its Settings
/// sources when the Pebble checkout is on this Mac (whitespace collapsed, as a template wraps its lines). A button in
/// Apple's title style keeps the Mac's sentence-case label beside it, and the two differ only in case.
@Suite(.enabled(if: PebbleCheckout.url != nil))
struct SettingsControlsParityTests {
    static func source(_ path: String) throws -> String {
        PebbleParityTests.collapse(try PebbleParityTests.read(path)).replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `name: "words"` pairs between `start` and the first `end` after it, in the source as written.
    static func pairs(in path: String, from start: String, to end: String) throws -> [String: String] {
        let block = try PebbleParityTests.block(try PebbleParityTests.read(path), from: start, to: end)
        var found: [String: String] = [:]
        for match in block.matches(of: /(\w+): "([^"]*)"/) { found[String(match.output.1)] = String(match.output.2) }
        return found
    }

    static func sameButCase(_ title: String, _ onMac: String) -> Bool {
        title != onMac && title.lowercased() == onMac.lowercased()
    }

    // MARK: Settings › Memory (SY-12, SY-13, SY-16, SY-19)

    @Test func theMemoryControlsWordsArePebbles() throws {
        typealias L = AppCopy.Learning
        let path = "src/components/AdvancedSettings.vue"
        let settings = try Self.source(path)
        let states = try Self.pairs(in: path, from: "const CANDIDATE_STATES", to: "};")
        #expect(states.count == 3)
        for (status, words) in states { #expect(L.state(status) == words, "CANDIDATE_STATES.\(status)") }
        #expect(settings.contains("CANDIDATE_STATES[candidate.status] || \"\(L.state("anything else"))\""))
        let reasons = try Self.pairs(in: path, from: "const CANDIDATE_REASONS", to: "};")
        #expect(reasons.count >= 19)
        for (code, words) in reasons { #expect(L.reason(code) == words, "CANDIDATE_REASONS.\(code)") }
        #expect(L.reason("a_code_pebble_adds_later") == nil)
        #expect(
            L.line(status: "conflict", reason: "active_value_differs")
                == "Disagrees with a saved memory: " + L.unknownReason)
        #expect(L.line(status: "pending", reason: nil) == "Waiting for evidence")
        for text in [
            L.unknownReason, L.testRecipe, "aria-label=\"Learning candidates\"", ">\(L.useValueOnMac)<",
            ">\(L.keepCurrentOnMac)<", ">\(L.checkNowOnMac)<", "placeholder=\"\(L.placeholder)\"",
            ">\(L.recallScope)<", ">\(L.personal)<", "> \(L.currentProjectOnMac) <", ">\(L.expiresAt)<",
            "/>\(L.saveOnMac) <", ">Add {{", "?.name.toLowerCase()", " \(L.forgetAllOnMac) <",
            "<p> \(L.forgetAllQuestion) \(L.forgetAllNote) </p>", " \(L.keepThemOnMac)</button", " \(L.forgetPermanentlyOnMac) <",
            "\"\(L.forgotAll)\"", L.idleOnly,
        ] {
            #expect(settings.contains(text), "AdvancedSettings.vue: \(text)")
        }
        #expect(L.title.lowercased() == "learning candidates")
        for (title, onMac) in [
            (L.useValue, L.useValueOnMac), (L.keepCurrent, L.keepCurrentOnMac), (L.checkNow, L.checkNowOnMac),
            (L.save, L.saveOnMac), (L.forgetAll, L.forgetAllOnMac), (L.keepThem, L.keepThemOnMac),
            (L.forgetPermanently, L.forgetPermanentlyOnMac),
        ] {
            #expect(Self.sameButCase(title, onMac), "\(title)")
        }
        #expect(L.addLayer("Your preferences") == "Add your preferences")
        #expect(L.count(0) == "None" && L.count(3) == "3")
    }

    // MARK: Settings › Skills & connectors (SK-04 to SK-09)

    @Test func theSkillsAndConnectorsWordsArePebbles() throws {
        typealias S = AppCopy.Skills
        let path = "src/components/AdvancedSettings.vue"
        let settings = try Self.source(path)
        let nouns = try Self.pairs(in: path, from: "const extensionNouns", to: "};")
        #expect(nouns.count == 3)
        for (kind, noun) in nouns { #expect(S.noun(kind) == noun, "extensionNouns.\(kind)") }
        #expect(S.noun("theme") == "theme", "another kind shows as Pebble names it")
        for text in [
            S.note, "x.enabled ? \"\(S.enabled)\" : \"\(S.disabled)\"", "\" · \" + x.capabilities.join(\", \")",
            "Review {{ (extensionNouns[x.kind] || 'extension').toLowerCase() }}",
            "{{ x.enabled ? \"\(S.disable)\" : \"\(S.enable)\" }}",
            S.destination(
                transport: "{{ x.config.transport || 'http' }}", era: "{{ x.config.protocol_era || 'legacy' }}",
                address: "{{ x.config.url || x.config.command }}"),
            S.reviewedVersion("{{ x.config.catalogue_digest }}", protocolVersion: "{{ x.config.protocol }}"),
            S.accessOnMac("{{ connectorInfo[x.id]?.state || 'disconnected' }}"),
            S.packageChecksum("{{ x.config.package_digest }}"),
            S.snapshot("{{ x.config.bundle_digest }}", name: "{{ x.name }}"),
            "{{ file.path }} · {{ file.bytes }} bytes · {{ file.sha256 }}", ">\(S.viewTextOnMac)<",
            S.textNote("{{ extensionPreview[x.id].path }}"), ">\(S.loadNextPageOnMac)<",
            "/\\.(md|txt|json|yaml|yml|py|js|ts|svg)$/i.test(file.path)",
        ] {
            #expect(settings.contains(text), "AdvancedSettings.vue: \(text)")
        }
        #expect(settings.contains("SKILLS AND CONNECTORS") && S.title == "Skills and Connectors")
        #expect(S.startsOff.count > 40 && S.note.contains(S.startsOff))
        #expect(S.line(kind: "plugin", enabled: false, capabilities: ["a", "b"]) == "Connector · Disabled · a, b")
        #expect(S.line(kind: "skill", enabled: true, capabilities: []) == "Skill · Enabled")
        #expect(S.review("plugin") == "Review connector" && S.review("theme") == "Review extension")
        #expect(S.access(grantConfigured: false) == S.accessOnMac("disconnected"))
        #expect(S.access(grantConfigured: true) == "Connector access: granted. Credential values are withheld.")
        #expect(S.fileLine(bytes: 12, sha256: "ab") == "12 bytes · ab")
        #expect(Self.sameButCase(S.viewText, S.viewTextOnMac) && Self.sameButCase(S.loadNextPage, S.loadNextPageOnMac))
        #expect(S.onYourMacNote.contains("on your Mac"))
    }

    // MARK: Settings › Data & storage (SD-11, SD-12, SD-14, SD-15)

    @Test func theDataAndStorageWordsArePebbles() throws {
        typealias D = AppCopy.DataStorage
        let storage = try Self.source("src/components/StorageSettings.vue")
        let checking =
            " in your Documents copies. It acts once a deletion has lasted a minute, or at once when you choose Update copies now."
        for text in [
            "'\(D.upToDate)'", "<summary>\(D.recentChangesOnMac)</summary>", "'\(D.updateCopiesOnMac)'",
            "Pebble is checking {{ plural(checking, 'deletion', 'deletions') }}" + checking,
            ">\(D.recentlyDeleted)<", ">\(D.deleteAllNowOnMac)<", ">\(D.deleteAllConversationsOnMac)<",
            "in Recently deleted for good? \(D.purgeAllNote)", ">\(D.purgeAllButtonOnMac)<",
            "\(D.trashAllQuestion) \(D.trashAllNoteOnMac)", ">\(D.trashAllButtonOnMac)<", ">\(D.keep)<",
            "'Moved ' + plural(count(result?.moved), 'conversation', 'conversations') + ' to Recently deleted.'",
            "' ' + plural(kept, 'conversation stays', 'conversations stay') + ' because a task or schedule uses it.'",
            "'Deleted ' + plural(count(result?.deleted), 'conversation', 'conversations') + ' for good.'",
            "rpc<{ moved?: number; kept?: { title?: string; reason?: string }[] }>('storage_trash_all', { confirm: true })",
            "rpc<{ deleted?: number; kept?: unknown[] }>('storage_purge_all', { confirm: true })",
            "rpc<Summary>('storage_refresh')", "rpc<Summary>('storage_summary')",
        ] {
            #expect(storage.contains(text), "StorageSettings.vue: \(text)")
        }
        #expect(D.checking(1).hasPrefix("Pebble is checking 1 deletion in") && D.checking(2).hasSuffix(checking))
        #expect(D.purgeAllQuestion(1) == "Delete all 1 conversation in Recently deleted for good?")
        #expect(D.trashAllNote == D.trashAllNoteOnMac.replacingOccurrences(of: "here", with: "in Recently Deleted"))
        let moved =
            "Moved 3 conversations to Recently deleted. 1 conversation stays because a task or schedule uses it."
        #expect(D.moved(3, kept: 1) == moved)
        #expect(D.moved(1, kept: 0) == "Moved 1 conversation to Recently deleted.")
        #expect(D.purged(2) == "Deleted 2 conversations for good.")
        for (title, onMac) in [
            (D.recentChanges, D.recentChangesOnMac), (D.updateCopies, D.updateCopiesOnMac),
            (D.deleteAllNow, D.deleteAllNowOnMac), (D.deleteAllConversations, D.deleteAllConversationsOnMac),
            (D.purgeAllButton, D.purgeAllButtonOnMac), (D.trashAllButton, D.trashAllButtonOnMac),
        ] {
            #expect(Self.sameButCase(title, onMac), "\(title)")
        }
        #expect(D.onYourMacNote.contains("on your Mac"))
    }

    // MARK: Settings › Privacy & Stealth: usage telemetry (SS-03, SS-06)

    @Test func theTelemetryWordsArePebbles() throws {
        typealias T = AppCopy.Telemetry
        let source = try Self.source("src/components/TelemetrySettings.vue")
        let app = try Self.source("src/App.vue")
        #expect(app.contains("USAGE TELEMETRY") && T.title.lowercased() == T.titleOnMac.lowercased())
        for text in [
            ">\(T.titleOnMac)<", "{{ enabled ? '\(T.on)' : '\(T.off)' }}",
            "> since {{ since }} · {{ plural(count(status?.events), 'event') }} kept<", "> · nothing is collected<",
            T.keptOnThisMac.trimmingCharacters(in: .whitespaces),
            "n + ' ' + word + (n === 1 ? '' : 's')", ": 'unknown';",
            "Limits: {{ limits.events }} events or {{ limits.kb }} KB, for {{ limits.days }} days; the oldest are removed first.",
            "<summary>\(T.whatEachEventHoldsOnMac)</summary>", "{{ item.kind }}: {{ item.names }}", ".join(', ')",
            "kind.replace(/_/g, ' ')", T.agree, ">\(T.turnOnOnMac)<",
            "Removed: {{ count(status?.dropped) }} over the limit, {{ count(status?.expired) }} expired, {{ count(status?.refused) }} refused.",
            "Random ID {{ text(status?.install_id) }}; it changes when you clear the log.", ">\(T.turnOffOnMac)<",
            "'\(T.turnedOnOnMac)'", "'\(T.turnedOff)'",
            "rpc<Status>('telemetry_set', { enabled: true, consent_version: version.value })",
            "rpc<Status>('telemetry_set', { enabled: false })", "rpc<Status>('telemetry_get')",
            "text(status.value?.current_consent_version)", ">Save a copy…<", ">Clear log<",
        ] {
            #expect(source.contains(text), "TelemetrySettings.vue: \(text)")
        }
        #expect(T.statusOff == "Off · nothing is collected · kept only on your Mac; nothing is uploaded.")
        #expect(
            T.statusOn(since: "today", events: 1)
                == "On since today · 1 event kept · kept only on your Mac; nothing is uploaded.")
        #expect(
            T.limits(events: 1000, kilobytes: 256, days: 30)
                == "Limits: 1000 events or 256 KB, for 30 days; the oldest are removed first.")
        #expect(T.turnedOn == T.turnedOnOnMac.replacingOccurrences(of: "this Mac", with: "your Mac"))
        #expect(T.field("run settled", ["steps", "tools"]) == "run settled: steps, tools")
        for (title, onMac) in [
            (T.whatEachEventHolds, T.whatEachEventHoldsOnMac), (T.turnOn, T.turnOnOnMac), (T.turnOff, T.turnOffOnMac),
        ] {
            #expect(Self.sameButCase(title, onMac), "\(title)")
        }
        #expect(T.onYourMacNote.contains("on your Mac"))
    }

    // MARK: Settings › Permissions: Pebble's Shell (SP-14)

    @Test func theShellWordsArePebbles() throws {
        typealias A = AppCopy.ShellAccess
        let settings = try Self.source("src/components/AdvancedSettings.vue")
        let line =
            "{{ kind === 'hosts' ? '\(A.website)' : '\(A.folder)' }} · {{ scope === 'always' ? '\(A.always)' : '\(A.untilQuit)' }}"
        for text in [
            "PEBBLE'S SHELL", line, A.empty, ">\(A.remove)<", "{{ PROTECTED_PLACES }}", "rpc(\"shell_grants\", {})",
            "rpc(\"shell_grant_remove\", { kind, value })",
            ":disabled=\"disabled || busy\" @click=\"removeShellGrant(kind, String(value))\"",
        ] {
            #expect(settings.contains(text), "AdvancedSettings.vue: \(text)")
        }
        #expect(A.section.replacingOccurrences(of: "\u{2019}", with: "'").uppercased() == "PEBBLE'S SHELL")
        #expect(A.line(website: true, always: false) == "Website · allowed until Pebble quits")
        #expect(A.line(website: false, always: true) == "Folder Pebble may write in · always allowed")
    }

    // MARK: Settings › General: notification delivery (SG-13)

    @Test func theDeliveryWordsArePebbles() throws {
        typealias D = AppCopy.Delivery
        let path = "src/components/NotificationSettings.vue"
        let notify = try Self.source(path)
        let block = try PebbleParityTests.block(try PebbleParityTests.read(path), from: "const failureText", to: "};")
        var problems: [String: String] = [:]
        for match in block.matches(of: /(\w+): '([^']*)'/) { problems[String(match.output.1)] = String(match.output.2) }
        #expect(problems.count == 6)
        for (code, words) in problems { #expect(D.problem(code) == "Last problem: " + words, "failureText.\(code)") }
        for text in [
            "'Waiting ' + count('pending') + ' · Shown ' + count('delivered') + ' · Not shown ' + count('suppressed') + ' · Failed ' + count('failed')",
            "<template v-if=\"status.deferred\"> · Held for quiet hours {{ status.deferred }}</template>",
            D.quietNow,
            "Last problem: {{ failureText[status.last_failure.reason] ?? 'A notification could not be shown.' }}",
            "job.muted ? ' · banners muted' : ' · banners on'", "job.muted ? 'Unmute' : 'Mute'",
            "(job.muted ? 'Unmute banners for ' : 'Mute banners for ') + job.label",
            "'Banners for “' + job.label + '” are back on.'",
            "'Banners for “' + job.label + '” are muted. Its updates stay in the app.'", D.noSchedules,
            "<strong>\(D.section)</strong>", "rpc('notification_mute', { job_id: job.job_id, muted: !job.muted })",
        ] {
            #expect(notify.contains(text), "NotificationSettings.vue: \(text)")
        }
        let outbox = D.outbox(waiting: 0, shown: 4, notShown: 1, failed: 0, held: 0)
        #expect(outbox == "Waiting 0 · Shown 4 · Not shown 1 · Failed 0")
        #expect(D.outbox(waiting: 2, shown: 0, notShown: 0, failed: 0, held: 2).hasSuffix(" · Held for quiet hours 2"))
        #expect(D.problem("something_new") == "Last problem: A notification could not be shown.")
        #expect(D.state(muted: true) == " · banners muted")
        #expect(D.label("Weekly", muted: false) == "Mute banners for Weekly")
        #expect(D.muted("Weekly") == "Banners for “Weekly” are muted. Its updates stay in the app.")
        #expect(D.unmuted("Weekly") == "Banners for “Weekly” are back on.")
    }

    // MARK: Settings › Models: Rest model and Load now (SM-10)

    @Test func theModelFilesButtonsArePebbles() throws {
        typealias M = AppCopy.LocalModel
        let settings = try Self.source("src/components/AdvancedSettings.vue")
        for text in [
            "{{ state.model.state === \"ready\" ? \"\(M.restOnMac)\" : \"\(M.loadOnMac)\" }}",
            "v-if=\"state.model.kind === 'gguf' && state.model.configured\"",
            ":disabled=\"disabled || busy || state.model.state === 'loading'\"",
            "props.state.model.state === \"ready\" ? \"model_unload\" : \"model_load\",",
        ] {
            #expect(settings.contains(text), "AdvancedSettings.vue: \(text)")
        }
        #expect(Self.sameButCase(M.rest, M.restOnMac) && Self.sameButCase(M.load, M.loadOnMac))
    }
}
