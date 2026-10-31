import Foundation
import PebbleProtocol
import Testing

@testable import PebbleDesign

/// StatusCopy, ModeCopy and RunCopy behave exactly as Pebble's statusWords.ts, permissionModes.ts and activity.ts.
/// (The tables themselves are compared with Pebble's sources in PebbleParityTests.)
struct StatusCopyTests {
    @Test func everyKeyHasWordsAndALabel() {
        for key in StatusKey.allCases {
            let words = StatusCopy.words[key] ?? []
            #expect(!words.isEmpty, "\(key) has words")
            #expect(words.allSatisfy { !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespaces) })
            #expect(!(StatusCopy.labels[key] ?? "").isEmpty, "\(key) has a label")
        }
        #expect(StatusCopy.words.count == StatusKey.allCases.count)
        #expect(StatusCopy.labels.count == StatusKey.allCases.count)
        #expect(StatusCopy.finishedLabel == "Reply finished")
    }

    @Test func statusWordRotatesInsideOneKeyOnly() {
        #expect(StatusCopy.word(for: .thinking) == "Thinking")
        #expect(StatusCopy.word(for: .thinking, tick: 1) == "Reasoning it through")
        #expect(StatusCopy.word(for: .thinking, tick: 6) == "Thinking")  // wraps
        #expect(StatusCopy.word(for: .thinking, tick: -1) == "Reasoning it through")  // Math.abs
        #expect(StatusCopy.word(for: .thinking, tick: 1, rotate: false) == "Thinking")
        #expect(StatusCopy.word(for: nil) == "Working")
        #expect(StatusCopy.label(for: nil) == "Pebble is working")
        // one step per 3 s
        #expect(StatusCopy.word(for: .editing, shownFor: 2.9) == "Editing")
        #expect(StatusCopy.word(for: .editing, shownFor: 3) == "Drafting changes")
        #expect(StatusCopy.word(for: .editing, shownFor: .infinity) == "Editing")
        // every word of a working key is shown by some tick, and never another key's; a key that waits for the person
        // keeps one of its own words (UX audit U-13)
        for key in StatusKey.allCases {
            let words = StatusCopy.words[key]!
            let shown = Set((0..<words.count).map { StatusCopy.word(for: key, tick: $0) })
            if let fixed = StatusCopy.fixedWords[key] {
                #expect(shown == [fixed])
                #expect(words.contains(fixed), "\(key)'s fixed word is one of Pebble's")
            } else {
                #expect(shown == Set(words))
            }
        }
    }

    @Test func onlyReconnectingShowsAnAttemptFrom1To99() {
        #expect(StatusCopy.word(for: .reconnecting, attempt: 2) == "Reconnecting (try 2)")
        #expect(StatusCopy.word(for: .reconnecting, attempt: 99) == "Reconnecting (try 99)")
        #expect(StatusCopy.word(for: .reconnecting, attempt: 0) == "Reconnecting")
        #expect(StatusCopy.word(for: .reconnecting, attempt: 100) == "Reconnecting")
        #expect(StatusCopy.word(for: .thinking, attempt: 2) == "Thinking")
    }

    @Test func exactElapsedMatchesPebble() {
        #expect(StatusCopy.formatExactElapsed(milliseconds: 999) == nil)
        #expect(StatusCopy.formatExactElapsed(milliseconds: .nan) == nil)
        #expect(StatusCopy.formatExactElapsed(milliseconds: -5000) == nil)
        #expect(StatusCopy.formatExactElapsed(milliseconds: 1000) == "1 s")
        #expect(StatusCopy.formatExactElapsed(milliseconds: 12_400) == "12 s")
        #expect(StatusCopy.formatExactElapsed(milliseconds: 59_999) == "59 s")
        #expect(StatusCopy.formatExactElapsed(milliseconds: 60_000) == "1 min 00 s")
        #expect(StatusCopy.formatExactElapsed(milliseconds: 65_000) == "1 min 05 s")
        #expect(StatusCopy.formatExactElapsed(125) == "2 min 05 s")
        #expect(StatusCopy.formatExactElapsed(milliseconds: 3_599_999) == "59 min 59 s")
        #expect(StatusCopy.formatExactElapsed(milliseconds: 3_600_000) == "1 h 00 min")
        #expect(StatusCopy.formatExactElapsed(milliseconds: 3_725_000) == "1 h 02 min")
        #expect(StatusCopy.formatExactElapsed(milliseconds: 1e300) != nil)  // no overflow trap
    }

    @Test func approximateElapsedMatchesPebble() {
        #expect(StatusCopy.formatElapsed(milliseconds: 999) == nil)
        #expect(StatusCopy.formatElapsed(milliseconds: 12_000) == "12s")
        #expect(StatusCopy.formatElapsed(milliseconds: 60_000) == "1 min")
        #expect(StatusCopy.formatElapsed(milliseconds: 3_599_000) == "59 min")
        #expect(StatusCopy.formatElapsed(milliseconds: 3_900_000) == "1 h 05 min")
        #expect(StatusCopy.approximate("12s") == "~12s")
    }

    @Test func changeTimersMatchPebble() {
        #expect(StatusCopy.exactChangeIn(milliseconds: 1250) == 750)
        #expect(StatusCopy.exactChangeIn(milliseconds: 3_600_000) == 60_000)
        #expect(StatusCopy.exactChangeIn(milliseconds: -1) == 1000)
        #expect(StatusCopy.elapsedChangeIn(milliseconds: 59_500) == 500)
        #expect(StatusCopy.elapsedChangeIn(milliseconds: 61_000) == 59_000)
    }

    @Test func tonesGroupTheKeys() {
        #expect(StatusCopy.tone(of: .review) == .needsYou)
        #expect(StatusCopy.tone(of: .question) == .needsYou)
        #expect(StatusCopy.tone(of: .error) == .problem)
        #expect(StatusCopy.tone(of: .offline) == .problem)
        #expect(StatusCopy.tone(of: .paused) == .waiting)
        #expect(StatusCopy.tone(of: .editing) == .working)
        #expect(StatusCopy.tone(of: .sending) == .working)
    }
}

struct ModeCopyTests {
    @Test func threeModesInPebblesOrder() {
        #expect(ModeCopy.order == [.ask, .auto, .full])
        #expect(ModeCopy.all.map(\.name) == ["Ask for approval", "Auto in project", "Full access"])
        #expect(Set(ModeCopy.all.map(\.name)).count == 3)
        for mode in PermissionMode.allCases {
            let copy = ModeCopy.for(mode)
            #expect(copy.mode == mode)
            #expect(mode.copy == copy)
            for text in [copy.name, copy.runsWithoutAsking, copy.alwaysAsks] {
                #expect(!text.isEmpty && text.count <= 200 && !text.contains("<") && !text.contains(">"))
            }
        }
    }

    @Test func unknownModeNamesAreAskForApproval() {
        #expect(ModeCopy.name(of: "auto") == "Auto in project")
        #expect(ModeCopy.name(of: "constructor") == "Ask for approval")
        #expect(ModeCopy.name(of: nil) == "Ask for approval")
    }

    @Test func settingsLinesUsePebblesHeadings() {
        #expect(AppCopy.Control.runsWithoutAskingLine(.ask) == "Runs without asking: Nothing that changes your project or your Mac.")
        #expect(AppCopy.Control.alwaysAsksLine(.ask).hasPrefix("Always asks: Every edit"))
        #expect(AppCopy.Control.permissionsLabel(.full) == "Permissions: Full access")
    }
}

struct RunCopyTests {
    @Test func durationsMatchPebble() {
        #expect(RunCopy.formatDuration(nil) == nil)
        #expect(RunCopy.formatDuration(-1) == nil)
        #expect(RunCopy.formatDuration(0.4) == "<1 s")
        #expect(RunCopy.formatDuration(11.5) == "12 s")
        #expect(RunCopy.formatDuration(60) == "1 min")
        #expect(RunCopy.formatDuration(65) == "1 min 05 s")
        #expect(RunCopy.formatDuration(7380) == "2 h 03 min")
    }

    @Test func endLinesMatchPebbleSummaries() {
        #expect(RunCopy.endLine(state: .completed, seconds: 11) == "Thought for 11 s")
        #expect(RunCopy.endLine(state: .completed, seconds: 0.6) == nil)  // a "hi" gets no chrome
        #expect(RunCopy.endLine(state: .completed, seconds: nil) == nil)
        #expect(RunCopy.endLine(state: .completed, seconds: 42, steps: 6) == "Worked for 42 s · 6 steps")
        #expect(
            RunCopy.endLine(state: .completed, seconds: 42, steps: 6, retries: 1, waitedSeconds: 60)
                == "Worked for 42 s · 6 steps · waited 1 min for you · 1 retry")
        #expect(RunCopy.endLine(state: .completed, seconds: 42, steps: 1, retries: 2) == "Worked for 42 s · 1 step · 2 retries")
        #expect(RunCopy.endLine(state: .stopped, seconds: 12) == "Stopped after 12 s")
        #expect(RunCopy.endLine(state: .failed, seconds: 30) == "Hit a problem after 30 s")
        #expect(RunCopy.endLine(state: .failed, seconds: nil) == "Hit a problem")
        #expect(RunCopy.endLine(state: .completed, seconds: nil, steps: 3) == "Worked · 3 steps")
        #expect(RunCopy.endLine(state: .completed, seconds: 9, countsKnown: false) == "Took 9 s")
        #expect(RunCopy.endLine(state: .budgetExhausted, seconds: 5) == "Reached its limit after 5 s")
    }
}
