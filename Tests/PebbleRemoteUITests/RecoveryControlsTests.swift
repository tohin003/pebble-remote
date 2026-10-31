import Foundation
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Lane R: when each of Pebble's task, command and card controls shows on the phone, and when it doesn't (RunPanel.vue,
/// ExecutionOutput.vue, App.vue's conditions, plus what the bridge offers).
struct RecoveryControlsTests {
    static let everything: (String) -> Bool = { _ in true }
    static func only(_ methods: Set<String>) -> (String) -> Bool { { methods.contains($0) } }

    static func task(_ state: RunState, project: Bool = true, windows: [ScreenSession] = []) -> TaskAttention {
        TaskAttention(chatID: "c1", chatTitle: "Fix", runID: "r1", state: state, hasProject: project, pausedWindows: windows)
    }

    static let mail = ScreenSession(id: "s1", chatID: "c1", runID: "r1", bundleID: "com.apple.mail", state: "interrupted")

    // MARK: - The task (RunPanel, view "conversation")

    @Test func aFailedOrInterruptedTaskOffersResumeAndDetails() {
        for state in [RunState.failed, .interrupted] {
            let controls = TaskControls(task: Self.task(state), offers: Self.everything, inConversation: true, showsRunDetails: true)
            #expect(controls.resume && !controls.resumeAsksLimits && controls.details == .run && !controls.holdsDecisions)
        }
    }

    @Test func aTaskAtItsLimitAsksForNewLimitsFirst() {
        let controls = TaskControls(
            task: Self.task(.budgetExhausted), offers: Self.everything, inConversation: true, showsRunDetails: false)
        #expect(controls.resume && controls.resumeAsksLimits && controls.details == nil)
    }

    @Test func aHeldTaskOffersItsThreeDecisionsAndTestsOnlyInAProject() {
        let project = TaskControls(task: Self.task(.verificationRequired), offers: Self.everything, inConversation: true, showsRunDetails: true)
        #expect(project.runTests && project.askToFinish && project.accept && !project.resume)
        let companion = TaskControls(
            task: Self.task(.verificationRequired, project: false), offers: Self.everything, inConversation: true,
            showsRunDetails: true)
        #expect(!companion.runTests && companion.askToFinish && companion.accept)
        let older = TaskControls(
            task: Self.task(.verificationRequired), offers: Self.only(["run_held_finish"]), inConversation: true,
            showsRunDetails: true)
        #expect(!older.runTests && older.askToFinish && !older.accept)  // what the bridge doesn't offer stays hidden
    }

    @Test func anUncertainStepOffersItsOutcomesAndItsPausedWindows() {
        let withWindow = TaskControls(
            task: Self.task(.needsReconciliation, windows: [Self.mail]), offers: Self.everything, inConversation: true,
            showsRunDetails: true)
        #expect(withWindow.details == .outcomes && withWindow.windowDone && withWindow.endAccess && !withWindow.resume)
        let without = TaskControls(
            task: Self.task(.needsReconciliation), offers: Self.everything, inConversation: true, showsRunDetails: true)
        #expect(!without.windowDone && !without.endAccess && without.details == .outcomes)
        let noReadback = TaskControls(
            task: Self.task(.needsReconciliation), offers: Self.only(["screen_handoff_done"]), inConversation: true,
            showsRunDetails: true)
        #expect(noReadback.details == nil)
    }

    @Test func thePausedTaskLeavesResumeToTheRunBarAndReviewsNeverResume() {
        let paused = TaskControls(task: Self.task(.paused), offers: Self.everything, inConversation: true, showsRunDetails: true)
        #expect(!paused.resume)
        let onReviews = TaskControls(task: Self.task(.failed), offers: Self.everything, inConversation: false, showsRunDetails: false)
        #expect(!onReviews.resume && onReviews.details == nil)
        let noResume = TaskControls(task: Self.task(.failed), offers: Self.only([]), inConversation: true, showsRunDetails: false)
        #expect(!noResume.resume)
    }

    @Test func theMenuResumesWhatTheRunBarDoesNot() {
        #expect(TaskControls.menuResumes(Self.task(.stopped), hasRunBar: false, offers: Self.everything))
        #expect(TaskControls.menuResumes(Self.task(.budgetExhausted), hasRunBar: false, offers: Self.everything))
        #expect(!TaskControls.menuResumes(Self.task(.paused), hasRunBar: false, offers: Self.everything))
        #expect(!TaskControls.menuResumes(Self.task(.stopped), hasRunBar: true, offers: Self.everything))
        #expect(!TaskControls.menuResumes(Self.task(.verificationRequired), hasRunBar: false, offers: Self.everything))
        #expect(!TaskControls.menuResumes(nil, hasRunBar: false, offers: Self.everything))
        #expect(!TaskControls.menuResumes(Self.task(.stopped), hasRunBar: false, offers: Self.only([])))
    }

    // MARK: - A command (ExecutionOutput)

    static func job(_ state: String, uncertain: Bool = false, inspected: Bool = false) -> ProcessJob {
        ProcessJob(id: "p1", chatID: "c1", runID: "r1", state: state, outcomeUncertain: uncertain, inspectionRecorded: inspected)
    }

    @Test func typingShowsWhenTheCommandTakesIt() {
        let waiting = ProcessTerminal(interactive: true, live: true, echo: true)
        let plain = ProcessTerminal(interactive: false, live: true)
        #expect(CommandControls(job: Self.job("running"), offers: Self.everything, readsTerminals: true, terminal: waiting).typeInto)
        #expect(!CommandControls(job: Self.job("running"), offers: Self.everything, readsTerminals: true, terminal: plain).typeInto)
        #expect(!CommandControls(job: Self.job("running"), offers: Self.everything, readsTerminals: true, terminal: nil).typeInto)
        // A bridge that wants Face ID to read the terminal: the button shows, and the sheet checks on the tap.
        #expect(CommandControls(job: Self.job("running"), offers: Self.everything, readsTerminals: false, terminal: nil).typeInto)
        #expect(!CommandControls(job: Self.job("stopped"), offers: Self.everything, readsTerminals: false, terminal: nil).typeInto)
        #expect(
            !CommandControls(job: Self.job("running"), offers: Self.only(["process_terminal"]), readsTerminals: true, terminal: waiting)
                .typeInto)
    }

    @Test func aRunningCommandStopsAndAnUncertainOneIsInspectedBeforeItIsForgotten() {
        let running = CommandControls(job: Self.job("running"), offers: Self.everything, readsTerminals: true, terminal: nil)
        #expect(running.stop && running.readOutput && !running.inspect && !running.forget)
        let unknown = CommandControls(
            job: Self.job("unknown", uncertain: true), offers: Self.everything, readsTerminals: true, terminal: nil)
        #expect(!unknown.stop && unknown.inspect && !unknown.forget)
        let inspected = CommandControls(
            job: Self.job("unknown", uncertain: true, inspected: true), offers: Self.everything, readsTerminals: true,
            terminal: nil)
        #expect(!inspected.inspect && inspected.forget)
        let finished = CommandControls(job: Self.job("succeeded"), offers: Self.everything, readsTerminals: true, terminal: nil)
        #expect(finished.forget && !finished.stop)
    }

    // MARK: - A card (App.vue)

    static func card(_ kind: CardKind, _ payload: JSONValue) -> ReviewItem {
        ReviewItem(chatID: "c1", chatTitle: "Fix", actionID: "a1", kind: kind, title: "Card", payload: payload)
    }

    @Test func aCardOffersWhatItHoldsAndAlwaysAllowWherePebbleDoes() {
        let edit = CardExtras(item: Self.card(.edit, ["path": "a.txt", "diff": "+a"]), offers: Self.everything, canPresent: true)
        #expect(edit.details == "View Diff" && !edit.alwaysAllow)
        let shell = CardExtras(
            item: Self.card(.shell, ["command": "ls", "always_offered": true, "hosts": ["a.example"]]), offers: Self.everything,
            canPresent: true)
        #expect(shell.details == "Details" && shell.alwaysAllow)
        let noGrants = CardExtras(
            item: Self.card(.shell, ["command": "ls", "always_offered": true]), offers: Self.only(["approve"]), canPresent: true)
        #expect(!noGrants.alwaysAllow)
        let app = CardExtras(item: Self.card(.app, ["name": "Notes"]), offers: Self.everything, canPresent: true)
        #expect(app.details == nil && !app.alwaysAllow)
        let nowhere = CardExtras(item: Self.card(.git, ["operation": "commit"]), offers: Self.everything, canPresent: false)
        #expect(nowhere.details == nil)
    }

    @Test func undoButtonsArePebblesAndAskFaceIDWhenTheyPutFilesBack() {
        #expect(ActionRecordRow.label(.edit) == "Undo This Edit")
        #expect(ActionRecordRow.label(.change(snapshotID: "s")) == "Undo This Change")
        #expect(ActionRecordRow.label(.gitPlan(receiptID: "r")) == "Propose Undo (New Reviewed Plan)")
        #expect(ActionRecordRow.asksFaceID(.command) && !ActionRecordRow.asksFaceID(.gitPlan(receiptID: "r")))
        #expect(ActionRecordRow.notice(.someChangesNotUndone) == "Some changes could not be undone")
        #expect(ActionRecordRow.offered(.change(snapshotID: "s"), by: Self.only(["shell_undo"])))
        #expect(!ActionRecordRow.offered(.edit, by: Self.only(["shell_undo"])))
        #expect(ActionRecordRow.offered(.gitPlan(receiptID: "r"), by: Self.only(["git_plan_propose"])))
    }

    @Test func eachRecoverySheetHasItsOwnIdentity() {
        let task = Self.task(.needsReconciliation)
        let sheets: [RecoverySheet] = [
            .outcomes(task), .limits(task), .cardDetails(Self.card(.edit, [:])), .typeInto(Self.job("running")),
            .inspect(Self.job("running")), .output(Self.job("running")),
        ]
        #expect(Set(sheets.map(\.id)).count == sheets.count)
    }

    @Test func aDiffKeepsItsSignsAndItsLines() {
        let colored = CardDetailBlocks.colored("@@ -1 +1 @@\n-old\n+new")
        #expect(String(colored.characters) == "@@ -1 +1 @@\n-old\n+new")
    }
}
