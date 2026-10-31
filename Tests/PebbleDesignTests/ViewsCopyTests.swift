import Foundation
import PebbleDesign
import PebbleProtocol
import Testing

/// Lane G: the words of Pebble's views on the phone, as Pebble's window builds them (src/workView.ts: `round`,
/// `summaryWords`, `commandWords`, `testWords`, `cardTitle`, `STATE_WORDS`, `runWord`).
struct ViewsCopyTests {
    @Test func countsAreRoundedAsPebbleRoundsThem() {
        #expect(AppCopy.Views.compact(980) == "980")
        #expect(AppCopy.Views.compact(1234) == "1.2K")
        #expect(AppCopy.Views.compact(3120) == "3.1K")
        #expect(AppCopy.Views.compact(9950) == "10K")
        #expect(AppCopy.Views.compact(52310) == "52K")
        #expect(AppCopy.Views.compact(1_300_000) == "1.3M")
        #expect(AppCopy.Views.compact(2_000_000) == "2M")
    }

    @Test func theSummaryReadsAsPebblesChips() throws {
        let summary = try #require(
            WorkSummary(json: [
                "files": ["count": 1, "added": 4, "removed": 2], "commands": ["count": 2, "failed": 1],
                "tests": ["passed": 41, "failed": 1], "checks": "A check asked for more evidence", "seconds": 95.2,
                "tokens": ["input": 52310, "cached": 28770, "output": 3120],
            ]))
        #expect(
            AppCopy.Views.summaryChips(summary) == [
                "1 file changed +4 \u{2212}2", "2 commands \u{00B7} 1 failed", "Tests 41 passed \u{00B7} 1 failed",
                "A check asked for more evidence", "1 min 35 s", "52K in \u{00B7} 3.1K out",
            ])
    }

    @Test func cardsSayWhatPebblesWindowSays() {
        #expect(AppCopy.Views.commandOutcome(state: .done, exit: 0, seconds: 4.6) == "exit 0 \u{00B7} 5 s")
        #expect(AppCopy.Views.commandOutcome(state: .waiting, exit: nil, seconds: nil) == "Waiting for you")
        #expect(AppCopy.Views.testCounts(passed: 41, failed: 1, skipped: 0, errors: 0) == "41 passed \u{00B7} 1 failed")
        #expect(AppCopy.Views.testCounts(passed: 3, failed: 0, skipped: 2, errors: 1) == "3 passed \u{00B7} 2 skipped \u{00B7} 1 error")
        #expect(AppCopy.Views.explored(reads: 2, searches: 1) == "Read 2 files \u{00B7} 1 search")
        #expect(AppCopy.Views.explored(reads: 0, searches: 0) == "Explored")
        #expect(AppCopy.Views.state(.held) == "Held by Pebble")
        #expect(AppCopy.Views.runWord("budget_exhausted") == "Reached its limit")
        #expect(AppCopy.Views.runWord("something_new") == "Working")
        #expect(AppCopy.Views.headerLine(state: "running", seconds: 72.4, plan: nil) == "Working \u{00B7} 1 min 12 s")
    }

    @Test func noViewWordUsesABannedWord() {
        let words = [
            AppCopy.Views.updateTheApp, AppCopy.Views.waitingForData, AppCopy.Views.citedStep, AppCopy.Views.dashboardFootnote,
            AppCopy.Views.pageOnMacNote, AppCopy.Views.quizIntro, AppCopy.Views.shareNote, AppCopy.Views.answersBecomeInput,
            AppCopy.Views.invalidAttempt, AppCopy.Views.otherView, AppCopy.Views.otherConversation,
            AppCopy.Views.shareNotConfirmed,
        ]
        for word in words {
            let lower = word.lowercased()
            #expect(!["host", "receipt", "runtime", "inference", "capacity"].contains { lower.contains($0) }, "\(word)")
        }
    }

    /// Lane Q: a quiz's clock, letters and counts as Pebble's window writes them (QuizRenderer.vue `clock`, the choice
    /// letters, the review's state line).
    @Test func aQuizSaysWhatPebblesWindowSays() {
        #expect(AppCopy.Views.timeLeft(271) == "04:31 left")
        #expect(AppCopy.Views.timeLeft(600) == "10:00 left")
        #expect(AppCopy.Views.timeLeft(180 * 60) == "180:00 left")
        #expect(AppCopy.Views.timeLeft(-3) == "00:00 left")
        #expect(AppCopy.Views.timeLeftSpoken(271).hasSuffix(" left") && !AppCopy.Views.timeLeftSpoken(271).contains(":"))
        #expect((0..<6).map(AppCopy.Views.choiceLetter) == ["A", "B", "C", "D", "E", "F"])
        #expect(AppCopy.Views.questionInList(3, answered: true) == "Question 3, answered")
        #expect(AppCopy.Views.questionInList(3, answered: false) == "Question 3")
        #expect(AppCopy.Views.reviewHeading(2, AppCopy.Views.incorrect) == "Question 2 \u{00B7} Incorrect")
        #expect(AppCopy.Views.answeredCount(1, of: 12) == "1 of 12 answered")
        #expect(AppCopy.Views.score(2, of: 3) == "2 / 3" && AppCopy.Views.scoreSpoken(2, of: 3) == "2 of 3 correct")
        #expect(AppCopy.Views.quizIs("stopped") == "This quiz is stopped.")
    }
}
