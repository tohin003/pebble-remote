import Foundation
import Testing
@testable import RenewerCore

struct RenewScriptTests {
    func outcome(_ status: Int32, _ lines: [String], timedOut: Bool = false, couldNotStart: Bool = false)
        -> RenewOutcome
    {
        RenewScript.outcome(
            status: status, output: RenewOutput(lines: lines), timedOut: timedOut, couldNotStart: couldNotStart,
            timeZone: Fixture.zone)
    }

    let building = "renew.sh: building for iOS (this renews the signing profile)..."
    let installing = "renew.sh: installing on 1A2B3C4D-1111-2222-3333-444455556666..."

    @Test func successCarriesTheNewEndDate() {
        let lines = [
            "renew.sh: preparing the clean worktree at commit 563c2b9...",
            building,
            "** BUILD SUCCEEDED **",
            installing,
            "renew.sh: installed. This build expires Fri 06 Nov 2026, 02:07 (in 5.7 days). Run scripts/renew.sh again "
                + "before then.",
            "renew.sh: recorded this build for the menu-bar renewer in /state.json.",
        ]
        #expect(outcome(0, lines) == .renewed(expires: Fixture.date("2026-11-05T20:37:00Z")))
        #expect(outcome(0, lines).succeeded)
        #expect(outcome(0, ["renew.sh: installed."]) == .renewed(expires: nil))
    }

    @Test func everyExitCodeInPlainTerms() {
        #expect(outcome(75, ["renew.sh: a Pebble HOLD is active (timed benchmarks), so nothing was built."]) == .hold)
        #expect(outcome(75, ["renew.sh: another renewal is using the clean worktree (pid 4242); try again later."])
            == .busy)
        #expect(outcome(69, ["renew.sh: Xcode is not installed or not selected (xcode-select -p)."]) == .noXcode)
        #expect(outcome(69, [
            building, "no paired iPhone found. Connect it by cable once, turn on Developer Mode and trust this Mac.",
            "renew.sh: could not choose an iPhone (see above).",
        ]) == .noIPhone)
        #expect(outcome(66, ["renew.sh: PebbleRemote.xcodeproj is missing."]) == .noProject)
        #expect(outcome(73, ["renew.sh: commit 0badc0de is not in this repository."]) == .commitMissing)
        #expect(outcome(73, ["renew.sh: could not prepare the clean worktree (see above)."]) == .worktreeFailed)
        #expect(outcome(64, ["renew.sh: unknown option: --nope (see --help)"]) == .usage)
        #expect(outcome(1, [building, "renew.sh: the build finished, but no PebbleRemote.app was found."])
            == .noAppOrDate)
        #expect(outcome(1, [building, installing, "renew.sh: installed, but the expiry date could not be read."])
            == .noAppOrDate)
        #expect(outcome(2, []) == .failed(code: 2))
        #expect(outcome(0, [], timedOut: true) == .timedOut)
        #expect(outcome(-1, [], couldNotStart: true) == .couldNotStart)
    }

    @Test func buildFailuresTellSigningFromCode() {
        #expect(outcome(65, [
            building,
            #"error: No Account for Team "AB12CD34EF". Add a new account in Accounts settings."#,
            "** BUILD FAILED **",
        ]) == .signingFailed)
        #expect(outcome(65, [
            building, "/tmp/w/Sources/Thing.swift:10:5: error: cannot find 'x' in scope", "** BUILD FAILED **",
        ]) == .buildFailed)
    }

    @Test func installFailuresSayWhetherTheIPhoneWasLocked() {
        let retry = "renew.sh: the install failed; trying once more in 10 seconds."
        #expect(outcome(1, [building, installing, "ERROR: The device is locked.", retry])
            == .installFailed(locked: true))
        #expect(outcome(1, [building, installing, "ERROR: IXRemoteErrorDomain error 6.", retry])
            == .installFailed(locked: false))
    }

    @Test func onlyTheEndOfLongOutputIsKept() {
        var output = RenewOutput()
        for index in 0..<500 { output.add("SwiftCompile normal arm64 File\(index).swift") }
        for index in 0..<100 { output.add("File.swift:\(index): error: something") }
        output.add(building)
        output.add("   ")
        #expect(output.tail.count == RenewOutput.tailLimit)
        #expect(output.errorLines.count == RenewOutput.errorLimit)
        #expect(output.scriptLines == [building])
        #expect(output.tail.last == "File.swift:99: error: something")
    }

    @Test func worthANotice() {
        #expect(!RenewOutcome.hold.worthANotice)
        #expect(!RenewOutcome.busy.worthANotice)
        #expect(!RenewOutcome.renewed(expires: nil).worthANotice)
        #expect(RenewOutcome.signingFailed.worthANotice)
        #expect(RenewOutcome.noIPhone.worthANotice)
    }
}
