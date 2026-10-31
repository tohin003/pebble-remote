import Foundation
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI
import Testing

@testable import PebbleRemoteUI

/// Lane Y (fix 8): the conversation's Details screen. Which tabs show (Pebble's drawer rules), which task it opens on,
/// how the steps fold and count (U-45), how a step's name and time stay apart (U-46).
struct DetailsRulesTests {
    static func item(
        _ seq: Int, _ kind: String, _ label: String, at: Double = 1, duration: Double? = nil, status: String = "done",
        activity: StatusKey? = nil
    ) -> RunActivityItem {
        RunActivityItem(seq: seq, at: at, kind: kind, label: label, duration: duration, status: status, activity: activity)
    }

    static func steps(_ items: [RunActivityItem], state: RunState = .completed, counted: Int? = nil, complete: Bool = true)
        -> RunSteps
    {
        RunSteps(
            details: RunDetails(run: LiveRunRecord(id: "r1", chatID: "c1", state: state, steps: 99, elapsed: 38), items: items),
            pebbleCount: counted, isComplete: complete)
    }

    // MARK: - Item 1: the tabs (App.vue drawerTabs, moreTabs)

    @Test func aTabWithSomethingIsListedAndTheRestWaitInMoreSections() {
        let listing = DetailsListing(has: [.activity, .context, .changes], revealed: [], hasRun: true, offers: { _ in true })
        #expect(listing.listed == [.activity, .context, .changes])
        #expect(listing.more == [.task, .tools, .browser])
    }

    @Test func aTabOpenedFromMoreSectionsStaysListedInPebblesOrder() {
        let listing = DetailsListing(has: [.activity], revealed: [.browser, .task], hasRun: true, offers: { _ in true })
        #expect(listing.listed == [.activity, .task, .browser])
        #expect(!listing.more.contains(.browser) && !listing.more.contains(.task))
    }

    @Test func activityIsNeverInMoreSectionsAndContextOnlyOnceThereIsATask() {
        let noRun = DetailsListing(has: [], revealed: [.activity, .context], hasRun: false, offers: { _ in true })
        #expect(noRun.listed.isEmpty)
        #expect(!noRun.more.contains(.activity) && !noRun.more.contains(.context))
        let withRun = DetailsListing(has: [], revealed: [], hasRun: true, offers: { _ in true })
        #expect(withRun.more.contains(.context) && !withRun.more.contains(.activity))
    }

    @Test func aTabTheBridgeDoesntOfferNeverShows() {
        let listing = DetailsListing(
            has: [.activity, .browser], revealed: [.tools], hasRun: true, offers: { $0 != .browser && $0 != .tools })
        #expect(!listing.listed.contains(.browser) && !listing.more.contains(.browser))
        #expect(!listing.listed.contains(.tools) && !listing.more.contains(.tools))
    }

    @Test func theTabShownFallsBackToTheFirstListed() {
        let listing = DetailsListing(has: [.task, .tools], revealed: [], hasRun: false, offers: { _ in true })
        #expect(listing.showing(.activity) == .task)
        #expect(listing.showing(.tools) == .tools)
        #expect(DetailsListing(has: [], revealed: [], hasRun: false, offers: { _ in true }).showing(.activity) == nil)
    }

    @Test func theTabsUsePebblesNamesAndMethods() {
        #expect(DetailsTab.allCases.map(\.title) == ["Activity", "Task", "Context", "Changes", "Tools", "Browser"])
        #expect(DetailsTab.task.moreTitle == "Goal, plan and agents")
        #expect(DetailsTab.browser.moreTitle == "Browser and Pebble for Chrome")
        #expect(DetailsTab.changes.methods == ["rewind_preview"] && DetailsTab.context.methods == ["context_inspect"])
    }

    @Test func detailsOpensOnTheWorkingTaskElseTheWaitingOneElseTheNewest() {
        let items: [TranscriptItem] = [
            .runEnd(id: "e1", runID: "r-old", state: .completed, seconds: 3, note: nil),
            .message(MessageItem(id: "m2", role: .assistant, text: "Hi", runID: "r-new")),
        ]
        #expect(DetailsOpening.run(live: "r-live", task: "r-held", items: items) == "r-live")
        #expect(DetailsOpening.run(live: nil, task: "r-held", items: items) == "r-held")
        #expect(DetailsOpening.run(live: nil, task: nil, items: items) == "r-new")
        #expect(DetailsOpening.run(live: nil, task: nil, items: []) == nil)
    }

    // MARK: - Item 2: Activity

    @Test func readsAndSearchesFoldAsPebbleFoldsThem() {
        let entries = ActivityEntry.entries([
            Self.item(64, "tool", "Reading a.ts", activity: .reading),
            Self.item(128, "tool", "Searching for x", activity: .searching),
            Self.item(192, "tool", "Reading b.ts", activity: .reading),
            Self.item(256, "tool", "Editing a.ts", activity: .editing),
        ])
        #expect(entries.count == 2)
        guard case .group(_, let folded, let label) = entries[0] else {
            Issue.record("expected a folded group")
            return
        }
        #expect(folded.count == 3 && label == "Explored \u{00B7} read 2 files, 1 search")
        #expect(entries[1] == .row(Self.item(256, "tool", "Editing a.ts", activity: .editing)))
    }

    @Test func aModelTurnFoldsUnderItsReplyAndFailuresNeverFold() {
        let entries = ActivityEntry.entries([
            Self.item(64, "context", "Recalled 2 memories"),
            Self.item(128, "model", "ChatGPT responded"),
            Self.item(192, "tool", "Reading a.ts", status: "failed", activity: .reading),
            Self.item(256, "tool", "Reading b.ts", activity: .reading),
        ])
        #expect(entries.count == 3)
        if case .group(_, _, let label) = entries[0] { #expect(label == "ChatGPT responded \u{00B7} 2 steps") } else {
            Issue.record("expected the model turn folded")
        }
        if case .row(let failed) = entries[1] { #expect(failed.status == "failed") } else { Issue.record("a failure stays a row") }
    }

    @Test func theCountAboveTheStepsEqualsTheStepsListed() {
        // U-45: the run's own counter said 99; the list has two steps (a tool and a check) and two other rows.
        let steps = Self.steps([
            Self.item(64, "context", "Context ready"), Self.item(128, "tool", "Reading a.ts"),
            Self.item(192, "check", "Checked the reply"), Self.item(256, "model", "ChatGPT responded"),
        ])
        #expect(steps.listedSteps == 2)
        #expect(ActivityReceipt.line(steps) == "Worked for 38 s \u{00B7} 2 steps")
        #expect(ActivityReceipt.countNote(steps) == nil)
    }

    @Test func whenPebbleCountedMoreStepsTheScreenSaysSo() {
        let steps = Self.steps([Self.item(64, "tool", "Reading a.ts")], counted: 6)
        #expect(steps.missingSteps == 5)
        #expect(ActivityReceipt.countNote(steps) == "Pebble counted 6 steps; 1 is listed here.")
        #expect(AppCopy.Details.countedMore(pebble: 3, listed: 0) == "Pebble counted 3 steps; none of them reached this iPhone.")
        #expect(ActivityReceipt.countNote(Self.steps([Self.item(64, "tool", "A")], complete: false)) == AppCopy.Details.moreThanListed)
    }

    @Test func withNoStepsTheLineUsesPebblesCountOrSaysTook() {
        #expect(ActivityReceipt.line(Self.steps([], counted: 4)) == "Worked for 38 s \u{00B7} 4 steps")
        #expect(ActivityReceipt.line(Self.steps([])) == "Took 38 s")
    }

    @Test func aStepsNameNeverCarriesItsTime() {
        // U-46: the name and the time are two texts with a gap, stacked at accessibility sizes.
        #expect(AppCopy.Details.stepName("Reading README.md", took: 3.2) == "Reading README.md \u{00B7} 3 s")
        #expect(AppCopy.Details.stepName("Reading README.md", took: 0.4) == "Reading README.md")
        #expect(StepLine.gap >= 8)
        #expect(StepLine.arrangement(for: .large) == .sideBySide)
        #expect(StepLine.arrangement(for: .accessibility1) == .stacked)
    }

    @Test func aStepsTimeIsPebblesOffsetFromTheRunsStart() {
        #expect(AppCopy.Details.offset(3.25) == "+3.3 s")
        #expect(AppCopy.Details.offset(0) == "+0.0 s")
        #expect(AppCopy.Details.offset(65) == "+1 min 05 s")
        #expect(AppCopy.Details.offset(-1) == nil)
    }

    @Test func aStepLeftRunningInAnEndedTaskReadsUnfinished() {
        #expect(StepPhase(status: "running", runIsLive: true) == .running)
        #expect(StepPhase(status: "running", runIsLive: false) == .unfinished)
        #expect(StepPhase(status: "failed", runIsLive: false).word == "Failed")
        #expect(StepPhase(status: "done", runIsLive: true).word == "Done")
    }

    @Test func longStepWordsFoldBehindShowMore() {
        #expect(ActivityStepRow.isLong(String(repeating: "a", count: 161)))
        #expect(ActivityStepRow.isLong("1\n2\n3\n4"))
        #expect(!ActivityStepRow.isLong("Port 4173 is already in use by another program."))
    }

    // MARK: - U-58: a working task's line counts on, as the run bar does

    @Test func aWorkingTasksLineSaysItsStatusAndCountsOnFromItsStart() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let running = Self.steps([Self.item(64, "tool", "Reading a.ts")], state: .running)
        let word = StatusCopy.word(for: .testing)
        #expect(
            ActivityReceipt.liveLine(running, status: .testing, since: now.addingTimeInterval(-85), at: now)
                == "\(word) \u{00B7} 1 min 25 s \u{00B7} 1 step so far")
        #expect(
            ActivityReceipt.liveLine(running, status: .testing, since: now.addingTimeInterval(-86), at: now.addingTimeInterval(1))
                == "\(word) \u{00B7} 1 min 27 s \u{00B7} 1 step so far")
        // Without a start, the word alone; with no steps listed, Pebble's count or none.
        #expect(ActivityReceipt.liveLine(Self.steps([], state: .running), status: nil, since: nil, at: now)
            == StatusCopy.word(for: .working))
        #expect(AppCopy.Details.liveLine(word: "Working", elapsed: "12 s", steps: 6) == "Working \u{00B7} 12 s \u{00B7} 6 steps so far")
        // Never a settled run's words for a live one.
        #expect(!ActivityReceipt.liveLine(running, status: .working, since: now, at: now).contains("Worked"))
    }

    @Test func aWorkingTasksTimeCountsFromTheRunBarsStartElsePebblesOwnCount() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let record = LiveRunRecord(id: "r1", chatID: "c1", state: .running, elapsed: 2, updated: now.addingTimeInterval(-40))
        let bar = LiveRun(
            id: "r1", chatID: "c1", chatTitle: "Fix the login", state: .running, status: .working,
            started: now.addingTimeInterval(-85))
        #expect(ActivityReceipt.liveStart(record, liveRun: bar) == now.addingTimeInterval(-85))
        // Pebble's own count (run_activity.py `_elapsed`): the last update less the active seconds.
        #expect(ActivityReceipt.liveStart(record, liveRun: nil) == now.addingTimeInterval(-42))
        var other = bar
        other.id = "r2"
        #expect(ActivityReceipt.liveStart(record, liveRun: other) == now.addingTimeInterval(-42))
        #expect(ActivityReceipt.liveStart(LiveRunRecord(id: "r1", state: .running), liveRun: nil) == nil)
    }
}
