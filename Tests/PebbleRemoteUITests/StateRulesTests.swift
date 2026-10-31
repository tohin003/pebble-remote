import Foundation
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Lane W's state rules (UX audit 2026-10-30): one state, one place; the words a row shows; what a sheet reads.
struct StateRulesTests {
    static func run(_ id: String, chat: String, state: RunState, status: StatusKey) -> LiveRun {
        LiveRun(id: id, chatID: chat, chatTitle: chat, state: state, status: status)
    }

    static func question(in chat: String) -> WaitingItem {
        .question(
            QuestionCard(
                chatID: chat, chatTitle: chat, questionID: "q-\(chat)", runID: "r-\(chat)", revision: 1, required: true,
                prompts: []))
    }

    // MARK: - U-06: Working Now lists only working runs

    @Test func workingNowLeavesAWaitingRunToTheWaitingList() {
        let working = Self.run("r1", chat: "c1", state: .running, status: .thinking)
        let paused = Self.run("r2", chat: "c2", state: .paused, status: .paused)
        let asking = Self.run("r3", chat: "c3", state: .waitingInput, status: .question)
        let reviewing = Self.run("r4", chat: "c4", state: .waitingApproval, status: .review)
        let live = [working, paused, asking, reviewing]
        // Both decisions are under "Needs your review": only the working and the paused run stay.
        let decided = [Self.question(in: "c3"), Self.question(in: "c4")]
        #expect(WorkingNow.runs(live, waiting: decided).map(\.id) == ["r1", "r2"])
        // A decision the phone hasn't read yet: the run stays, so it never drops off the tab.
        #expect(WorkingNow.runs(live, waiting: [Self.question(in: "c3")]).map(\.id) == ["r1", "r2", "r4"])
        #expect(WorkingNow.runs(live, waiting: []).map(\.id) == ["r1", "r2", "r3", "r4"])
    }

    // MARK: - U-17: "1 waiting" only where the pill doesn't say it

    @Test func aChatRowSaysWaitingOnce() {
        #expect(!ChatRow.showsCount(waiting: 1, status: .review))
        #expect(!ChatRow.showsCount(waiting: 1, status: .question))
        #expect(!ChatRow.showsCount(waiting: 1, status: .blocked))
        #expect(!ChatRow.showsCount(waiting: 1, status: .uncertain))
        #expect(ChatRow.showsCount(waiting: 2, status: .review), "a count above one still says something")
        #expect(ChatRow.showsCount(waiting: 1, status: .thinking), "the pill says it works; the count says what waits")
        #expect(ChatRow.showsCount(waiting: 1, status: nil))
        #expect(!ChatRow.showsCount(waiting: 0, status: nil))
    }

    // MARK: - U-29, U-28: the step's app; Shared Windows by name

    @Test func theUncertainStepsAppIsTheOnePausedWindowsApp() {
        let mail = ScreenSession(id: "s1", chatID: "c1", bundleID: "com.apple.mail", state: "interrupted")
        let notes = ScreenSession(id: "s2", chatID: "c1", bundleID: "com.apple.Notes", state: "interrupted")
        let tab = ScreenSession(id: "s3", chatID: "c1", kind: "browser", origins: ["https://docs.github.com"])
        #expect(UncertainOutcomesSheet.pausedApp([mail]) == "Mail")
        #expect(UncertainOutcomesSheet.pausedApp([mail, tab]) == "Mail")
        #expect(UncertainOutcomesSheet.pausedApp([mail, notes]) == nil, "two apps: Pebble doesn't say which")
        #expect(UncertainOutcomesSheet.pausedApp([tab]) == nil)
        #expect(UncertainOutcomesSheet.pausedApp([]) == nil)
    }

    @Test func sharedWindowsShowASiteByNameAndAnAppWithItsCapitals() {
        let tab = ScreenSession(
            id: "s1", chatID: "c1", kind: "browser", profile: "chrome", origins: ["https://docs.github.com"])
        let item = ScreenSessionsView.item(tab)
        #expect(item.title == "docs.github.com")
        #expect(item.detail == AppCopy.Places.chromeTab)
        let window = ScreenSessionsView.item(ScreenSession(id: "s2", chatID: "c1", bundleID: "com.apple.mail"))
        #expect(window.title == "Mail" && window.detail == nil)
        let textEdit = ScreenSessionsView.item(ScreenSession(id: "s3", chatID: "c1", bundleID: "com.apple.TextEdit"))
        #expect(textEdit.title == "TextEdit", "never \"Textedit\"")
        let unnamed = ScreenSessionsView.item(ScreenSession(id: "s4", chatID: "c1"))
        #expect(unnamed.title == AppCopy.Places.appWindow)
    }

    // MARK: - U-32: what the command asks

    @Test func typingIntoACommandShowsItsLastLines() {
        let output = "> vite\n\n  ready in 412 ms\n\n  Local:   http://localhost:5173/\n\nOpen the site in your browser? (y/N) \n\n"
        let shown = TypeIntoCommandSheet.lastLines(of: output, count: 3)
        #expect(shown == "  Local:   http://localhost:5173/\n\nOpen the site in your browser? (y/N) ")
        #expect(TypeIntoCommandSheet.lastLines(of: "", count: 6).isEmpty)
        #expect(TypeIntoCommandSheet.lastLines(of: "one\r\ntwo", count: 6) == "one\ntwo")
    }

    // MARK: - U-51: the controls stay above the keyboard

    @Test func theCommandsLinesNeverPushTheFieldDown() {
        // The block is as tall as its lines, at most three; more scroll inside it.
        #expect(TypeIntoCommandSheet.visibleLineCount(of: "") == 1)
        #expect(TypeIntoCommandSheet.visibleLineCount(of: "Open the site in your browser? (y/N) ") == 1)
        #expect(TypeIntoCommandSheet.visibleLineCount(of: "a\nb") == 2)
        #expect(TypeIntoCommandSheet.visibleLineCount(of: "a\nb\nc\nd\ne\nf") == TypeIntoCommandSheet.visibleLines)
        #expect(TypeIntoCommandSheet.visibleLines <= 3)
        // The bar's one-word Send keeps Pebble's words for VoiceOver (and the tour, which taps "Send Line").
        #expect(AppCopy.CommandState.send.count < RecoveryCopy.Command.sendLine.count)
    }

    // MARK: - U-44: a note, said rather than dimmed

    @Test func anInspectionWithoutWordsAsksForThem() {
        #expect(InspectCommandSheet.isBlank("  \n "))
        #expect(!InspectCommandSheet.isBlank("Checked the folder"))
    }

    // MARK: - U-41: Pebble's reason as a sentence

    @Test func theToolboxSaysWhyInPebblesSentence() {
        #expect(
            ToolDecisionRow.sentence("it has not been used successfully in this task yet")
                == "Pebble asks because it has not been used successfully in this task yet.")
        #expect(ToolDecisionRow.sentence(" it changes files. ") == "Pebble asks because it changes files.")
    }

    // MARK: - U-38: Face ID said once, still heard per switch

    @Test func aSwitchStillSaysFaceIDToVoiceOver() {
        #expect(RemoteToggle.nextAsksFaceID(.always, isOn: true))
        #expect(RemoteToggle.nextAsksFaceID(.whenTurningOn, isOn: false))
        #expect(!RemoteToggle.nextAsksFaceID(.whenTurningOn, isOn: true))
        #expect(!RemoteToggle.nextAsksFaceID(.never, isOn: false))
    }

    // MARK: - The keyboard always closes without sending (the lead's rule, 22:58)

    @Test func returnInAnEmptyFieldClosesTheKeyboard() {
        #expect(KeyboardRules.isEmptyReturn("\n"))
        #expect(KeyboardRules.isEmptyReturn("  \n"))
        #expect(KeyboardRules.isEmptyReturn("\n\n"))
        #expect(!KeyboardRules.isEmptyReturn(""), "nothing typed yet: no Return pressed")
        #expect(!KeyboardRules.isEmptyReturn(" "))
        #expect(!KeyboardRules.isEmptyReturn("ls\n"), "a line with words keeps its new line")
    }

    // MARK: - Fix 7: Settings as the Mac's

    @Test func appearanceNamesTheThemeAsPebbleDoes() {
        #expect(PebbleControlsSection.themeName("light") == AppCopy.Settings.appearanceLight)
        #expect(PebbleControlsSection.themeName("dark") == AppCopy.Settings.appearanceDark)
        #expect(PebbleControlsSection.themeName("system") == AppCopy.Settings.appearanceSystem)
        #expect(PebbleControlsSection.themeName("something new") == AppCopy.Settings.appearanceSystem)
    }
}
