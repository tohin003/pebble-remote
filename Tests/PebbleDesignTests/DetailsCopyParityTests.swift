import Foundation
import Testing

@testable import PebbleDesign

/// Lane Y (fix 8): the Details screen's words that are Pebble's own appear word for word in Pebble's sources (read from
/// the Pebble checkout when it is on this Mac), so a change in Pebble's drawer fails here until the phone follows.
@Suite(.enabled(if: PebbleCheckout.url != nil))
struct DetailsCopyParityTests {
    typealias D = AppCopy.Details

    static let pebbles: [String: [String]] = [
        "src/App.vue": [
            D.moreTask, D.moreChanges, D.moreTools, D.moreBrowser, D.emptyTitle, D.emptyNote, D.filesFromLatestTask,
            D.scheduleNotices, D.plan,
        ],
        "src/components/DetailsDrawer.vue": [D.moreSections, D.sections],
        "src/components/ThinkingDisclosure.vue": [D.reasoning, D.noStepYet, D.noStepDetails, D.doing],
        "src/components/ContextPanel.vue": [
            D.contextNote, D.compactNow, D.compactMessage, D.contextBasis("last_request", live: false),
            D.compactUnavailable("not_latest"), D.contextCategory("tool_schemas"), D.contextCategory("framing"),
        ],
        "src/components/RewindPanel.vue": [
            D.rewindIntro, D.rewindTo, D.rewindPoint(0), D.undoesLastRewind, D.notReverted, D.reviewUndoRewind,
            D.reviewAgain, D.rewindNothing, D.rewindReview, D.diffCut, D.noFiles, D.noEffects, D.rewindNotReady,
            D.fileStatus("revert"), D.fileStatus("kept"),
        ],
        "src/components/GoalPanel.vue": [
            D.goalNote, D.goalPlaceholder, D.noGoal, D.setGoal, D.startGoal, D.continueGoal, D.markDone, D.markMet,
            D.markNotMet, D.noCriteria, D.goalAbandoned, D.keepGoal, D.earlierGoals, D.proposedAccepted,
            D.criterionPlaceholder, D.abandonConfirm, D.addCriterion, D.goalStarted,
        ],
        "src/components/AgentPanel.vue": [
            D.noAgents, D.cancelAgent, D.sendInput, D.agentInput, D.inputSent, D.cancelRequested, D.readOnlyAgent,
        ],
        "src/components/PebbleBrowser.vue": [
            D.chromeNote, D.stopInChrome, D.pausedNotice, D.resumedNotice, D.pebbleBrowserNote, D.checkAgain, D.noTabs, D.lookAround, D.lookAroundNote, D.fillIn, D.fillInNote,
            D.pressButtons, D.pressButtonsNote, D.grantThisTab, D.turnOnScreenAndGrant, D.grantSites, D.grantWhat,
            D.forHowLong, D.screenshotsToggle, D.titleNote, D.tabScope("tab"), D.tabScope("site"),
            D.sharedTabState("handback", acting: false, granted: false), D.browserNotAvailable,
        ],
        "src/components/CompanionWorkflows.vue": [D.schedulesNote, D.noSchedules],
        "src/components/ScreenSessions.vue": [
            D.noWindows, D.endAccess, D.sessionState("interrupted", pending: false), D.sessionState("active", pending: true),
        ],
    ]

    @Test func detailsWordsArePebblesWordForWord() throws {
        for (file, words) in Self.pebbles {
            let text = try PebbleParityTests.read(file)
            for word in words {
                #expect(text.contains(word), "\(file) no longer says: \(word)")
            }
        }
    }

    @Test func theRingSaysWhatTheMacsRingSays() throws {
        #expect(D.contextUsed(62) == "62% of context used")
        #expect(try PebbleParityTests.read("src/App.vue").contains("% of context used"))
    }

    @Test func theDrawersTabsKeepPebblesNamesAndOrder() throws {
        let app = try PebbleParityTests.read("src/App.vue")
        #expect(app.contains(#"const DRAWER_TABS = ["activity", "task", "context", "changes", "tools", "browser"];"#))
        for (id, name) in [("activity", D.activity), ("task", D.task), ("context", D.context), ("changes", D.changes),
            ("tools", D.tools), ("browser", D.browser)]
        {
            #expect(app.contains("\(id): \"\(name)\""), "TAB_LABELS no longer names \(id) \(name)")
        }
    }
}
