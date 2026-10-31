import Foundation
import Testing
@testable import RenewerCore

struct RedactionTests {
    @Test func takesOutWhatMustNeverBeLogged() {
        let identity = Redactor.redact(#"Signing Identity:     "Apple Development: Jane Doe (AB12CD34EF)""#)
        #expect(!identity.contains("Jane"))
        #expect(!identity.contains("AB12CD34EF"))
        #expect(identity.contains("Apple Development: <name>"))
        #expect(Redactor.redact("Apple ID jane.doe@example.com signed in") == "Apple ID <e-mail> signed in")
        #expect(!Redactor.redact(#"error: No Account for Team "AB12CD34EF"."#).contains("AB12CD34EF"))
        #expect(Redactor.redact("DEVELOPMENT_TEAM=AB12CD34EF") == "DEVELOPMENT_TEAM=<team>")
        #expect(Redactor.redact("AB12CD34EF.io.github.tohin003.PebbleRemote") == "<team>.io.github.tohin003.PebbleRemote")
        #expect(!Redactor.redact("Team: Jane Doe (Personal Team)").contains("Jane"))
        #expect(Redactor.redact("token=abc123") == "token: <hidden>")
        #expect(!Redactor.redact("codesign --sign 3F2A9C1B7D4E6F8A0B1C2D3E4F5A6B7C8D9E0F1A app").contains("3F2A9C1B"))
    }

    @Test func leavesOrdinaryLinesAlone() {
        let lines = [
            "renew.sh: building for iOS (this renews the signing profile)...",
            "renew.sh: installing on 1A2B3C4D-1111-2222-3333-444455556666...",
            "renew.sh: installed. This build expires Fri 06 Nov 2026, 02:07 (in 5.7 days). Run scripts/renew.sh again "
                + "before then.",
            "Renewing (automatic): build 563c2b9 on iPhone 00008150-0000000000000000.",
            "Check: due; renew on 1A2B3C4D-1111-2222-3333-444455556666; iPhone reachable by cable as 1A2B3C4D-1111-2222-3333-444455556666",
        ]
        for line in lines {
            #expect(Redactor.redact(line) == line)
        }
    }
}

struct LogFileTests {
    @Test func linesAreRedactedOwnerOnlyAndRotated() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appending(path: "renewer-log-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: folder) }
        let url = folder.appending(path: "PebbleRemoteRenewer.log")
        let log = FileLog(url: url, limit: 400)
        log.write("Apple ID jane.doe@example.com")
        log.flush()
        let first = try String(contentsOf: url, encoding: .utf8)
        #expect(first.contains("<e-mail>"))
        #expect(!first.contains("jane.doe"))
        let mode = try manager.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions]
        #expect((mode as? NSNumber)?.intValue == 0o600)

        for index in 0..<20 { log.write("line \(index) with some words to fill the log quickly") }
        log.flush()
        let older = folder.appending(path: "PebbleRemoteRenewer.log.1")
        #expect(manager.fileExists(atPath: older.path(percentEncoded: false)))
        let size = try manager.attributesOfItem(atPath: url.path(percentEncoded: false))[.size]
        #expect(((size as? NSNumber)?.intValue ?? 0) <= 400)
        let last = try String(contentsOf: url, encoding: .utf8)
        #expect(last.contains("line 19 with"))
    }

    @Test func oneLinePerMessage() {
        let line = LogLine.format("first\nsecond", at: Fixture.expires)
        #expect(line.hasSuffix(" first | second\n"))
        #expect(line.filter { $0 == "\n" }.count == 1)
    }

    @Test func rotationThreshold() {
        #expect(!LogLine.needsRotation(size: 0, adding: 5_000, limit: 1_000))
        #expect(LogLine.needsRotation(size: 900, adding: 200, limit: 1_000))
        #expect(!LogLine.needsRotation(size: 700, adding: 200, limit: 1_000))
    }
}

struct CopyTests {
    /// Pebble's banned words and the app-internal ones (scripts/lint_copy.py's lists).
    static let internalWords = [
        "inference", "receipt", "receipts", "host", "runtime", "capacity", "E-B1", "bridge", "payload", "endpoint",
        "endpoints", "epoch", "RPC", "JSON", "idempotency",
    ]

    static var everyString: [String] {
        let outcomes: [RenewOutcome] = [
            .renewed(expires: nil), .hold, .busy, .noIPhone, .noXcode, .noProject, .commitMissing, .worktreeFailed,
            .signingFailed, .buildFailed, .installFailed(locked: true), .installFailed(locked: false), .noAppOrDate,
            .usage, .timedOut, .couldNotStart, .failed(code: 2),
        ]
        let refusals: [Refusal] = [.hold, .holdUnknown, .noIPhone, .severalPhones, .noBuild]
        var strings = [
            Copy.renewNow, Copy.renewAutomatically, Copy.quit, Copy.barRenewing, Copy.barNoDate, Copy.barExpired,
            Copy.noEndDate, Copy.fromXcode, Copy.planRenewing, Copy.planNoDate, Copy.planNoBuild, Copy.planOff,
            Copy.planAfterExpiry, Copy.planDue, Copy.planWaitHold, Copy.planHoldUnknown, Copy.planWaitPhone,
            Copy.planSeveral, Copy.notRenewedYet, Copy.seeLog, Copy.unreachable, Copy.stillExpired,
            Copy.expires("x"), Copy.expired("x"), Copy.planIn("x"), Copy.planRetry("x"), Copy.renewed("x"),
            Copy.renewedUnmoved("x"), Copy.couldNotRenew("x"), Copy.installed("x"),
        ]
        strings += outcomes.map { Copy.reason($0) }
        strings += refusals.map { Copy.reason($0) }
        let notices = [
            Copy.unreachableNotice(when: "x", expired: false), Copy.unreachableNotice(when: "x", expired: true),
            Copy.failedNotice(reason: "x", when: "x", expired: false), Copy.noBuildNotice(when: "x", expired: true),
        ]
        for notice in notices { strings += [notice.title, notice.body] }
        return strings
    }

    @Test func noInternalWordsOnScreen() {
        for text in Self.everyString {
            for word in Self.internalWords {
                let found = text.range(of: "\\b\(word)\\b", options: [.regularExpression, .caseInsensitive])
                #expect(found == nil, "\"\(word)\" in \"\(text)\"")
            }
        }
    }

    @Test func theBriefsOwnWords() {
        #expect(Copy.planIn(TimeWords.span(2.5 * 86_400)) == "Renews in 2 days")
        #expect(Copy.reason(RenewOutcome.noIPhone) == "Your iPhone wasn't reachable. Connect it, then choose Renew Now.")
        #expect(Copy.reason(Refusal.noIPhone) == Copy.reason(RenewOutcome.noIPhone))
    }
}
