import Foundation
import PebbleProtocol

// Lane G (2026-10-31): Pebble's views on the phone (contract 3.12, pebble-ui-spec v1). Pebble's own words come from its
// window, word for word (read-only Pebble checkout: src/workView.ts, src/components/WorkCard.vue, WorkView.vue,
// NativeArtifactRenderer.vue, DashboardRenderer.vue, PrototypeRenderer.vue, QuizRenderer.vue, VisualChart.vue,
// VisualDiagram.vue and App.vue's view links). Where Pebble's words name an internal thing ("Tool receipt", "host
// data") or a place on the Mac, the phone says the same in plain words and says so beside the constant.
extension AppCopy {
    nonisolated public enum Views {
        // MARK: The fallback (spec rule 1)

        /// Under a view this version can't draw (the spec's iPhone line).
        public static let updateTheApp = "Update the app to see this view"

        // MARK: States, as the work view's chips say them (workView.ts `STATE_WORDS`)

        public static func state(_ state: WorkState) -> String {
            switch state {
            case .waiting: "Waiting for you"
            case .running: "Running"
            case .done: "Done"
            case .failed: "Failed"
            case .declined: "Declined"
            case .held: "Held by Pebble"
            case .undone: "Undone"
            case .stopped: "Stopped"
            }
        }

        /// The run's state in a word or two, for the header (workView.ts `runWord`).
        public static func runWord(_ state: String?) -> String {
            switch state {
            case "queued": "Starting"
            case "running": "Working"
            case "retry_wait": "Reconnecting"
            case "waiting_approval", "waiting_input": "Waiting for you"
            case "completed": "Done"
            case "paused": "Paused"
            case "stopped": "Stopped"
            case "failed": "Hit a problem"
            case "interrupted": "Interrupted"
            case "budget_exhausted": "Reached its limit"
            case "needs_reconciliation": "Needs a check"
            case "verification_required": "Not verified"
            default: "Working"
            }
        }

        /// A card still under way (WorkCard.vue), a card with a failed step, and a step left running in a run that ended.
        public static let inProgress = "In progress"
        public static let failed = "Failed"
        public static let unfinished = "Unfinished"

        // MARK: Cards' titles (workView.ts `cardTitle`)

        public static func explored(reads: Int, searches: Int) -> String {
            let words = [
                reads > 0 ? "Read \(reads) \(reads == 1 ? "file" : "files")" : "",
                searches > 0 ? "\(searches) \(searches == 1 ? "search" : "searches")" : "",
            ].filter { !$0.isEmpty }
            return words.isEmpty ? "Explored" : words.joined(separator: " \u{00B7} ")
        }
        public static let searchedTheWeb = "Searched the web"
        public static func changedFiles(_ count: Int) -> String { "Changed \(count) \(count == 1 ? "file" : "files")" }
        public static let aCommand = "A command"
        public static func tests(recipe: String?) -> String { recipe.map { "Tests \u{00B7} \($0)" } ?? "Tests" }
        public static func onBranch(_ branch: String) -> String { "On \(branch)" }
        public static let git = "Git"
        public static let anAppWindow = "An app window"
        public static func agents(_ count: Int) -> String { "\(count) \(count == 1 ? "agent" : "agents")" }
        public static let whatYourRequestRequires = "What your request requires"

        // MARK: Inside the cards (WorkCard.vue)

        public static let aPrivateFile = "A private file"
        public static func lines(_ total: Int) -> String { "\(compact(Double(total))) lines" }
        public static func found(_ hits: Int) -> String { "\(hits) found" }
        public static let search = "Search"
        public static let new = "new"
        /// A file's bar, read out.
        public static func linesChanged(added: Int, removed: Int) -> String { "\(added) lines added, \(removed) removed" }
        public static func diff(added: Int, removed: Int) -> String { "+\(added) \u{2212}\(removed)" }
        public static let withNetwork = "with network"
        public static let noNetwork = "no network"
        public static let outputWasLonger = "The output was longer; these are its last lines."
        public static let lastLines = "Last lines of output"
        /// A command's outcome (workView.ts `commandWords`): "exit 0 · 5 s", or its state while it waits or runs.
        public static func commandOutcome(state: WorkState?, exit: Int?, seconds: Double?) -> String {
            if let state, [.waiting, .running, .declined, .held].contains(state) { return Self.state(state) }
            let first = exit.map { "exit \($0)" } ?? state.map(Self.state) ?? ""
            return [first, RunCopy.formatDuration(seconds) ?? ""].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }
        /// A test run's counts (workView.ts `testWords`): skipped and errors only when there are some.
        public static func testCounts(passed: Int, failed: Int, skipped: Int, errors: Int) -> String {
            [
                "\(passed) passed", failed > 0 ? "\(failed) failed" : "", skipped > 0 ? "\(skipped) skipped" : "",
                errors > 0 ? "\(errors) \(errors == 1 ? "error" : "errors")" : "",
            ].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }
        public static let failingTests = "Failing tests"
        public static func aheadBehind(ahead: Int, behind: Int) -> String { "\(ahead) ahead \u{00B7} \(behind) behind" }
        public static func changed(_ count: Int) -> String { "\(count) changed" }
        public static func pushTo(_ remote: String) -> String { "Push to \(remote)" }
        public static let changesHistory = "Changes history"
        public static let publishes = "Publishes"
        public static func verdict(_ verdict: WorkView.Window.Verdict) -> String {
            switch verdict {
            case .happened: "Happened"
            case .nothingChanged: "Nothing changed"
            case .uncertain: "Not sure"
            case .refused: "Not done"
            }
        }
        public static let wherePebblePressed = "Where Pebble pressed in the window"
        public static func tokens(_ count: Int) -> String { "\(compact(Double(count))) tokens" }
        public static let notAllMet = "Not all met"
        public static let allMet = "All met"
        public static let met = "Met"
        public static let notConfirmedYet = "Not confirmed yet"
        public static let metAfterRepair = "Met after Pebble repaired its work."
        public static func notMetYet(_ count: Int) -> String {
            "\(count) \(count == 1 ? "issue" : "issues") not met yet; the reply says which."
        }
        public static func checkTests(runner: String?, passed: Int, failed: Int, current: Bool) -> String {
            var words = [runner, "\(passed) passed"].compactMap { $0 }.joined(separator: " ")
            if failed > 0 { words += " \u{00B7} \(failed) failed" }
            return current ? words + " on current files" : words
        }
        public static func showMore(_ count: Int) -> String { "Show \(count) More" }
        public static let showLess = "Show Less"
        /// The card's own button opens what it holds; it never acts (spec rule 4).
        public static let showDetails = "Shows what this step did"
        public static let hideDetails = "Hides what this step did"

        // MARK: The header, the plan and the summary (WorkView.vue)

        public static let whatPebbleIsDoing = "What Pebble is doing"
        public static let whatPebbleDid = "What Pebble did"
        public static let plan = "Plan"
        public static let showsPlan = "Shows the plan's steps"
        public static let untitledStep = "Step"
        public static func planSteps(done: Int, total: Int) -> String { "\(done) of \(total) steps" }
        public static func planStepsDone(done: Int, total: Int) -> String { "\(done) of \(total) plan steps done" }
        public static func planStatus(_ status: WorkPlan.Status) -> String {
            switch status {
            case .completed: "Done"
            case .inProgress: "In progress"
            case .blocked: "Blocked"
            case .pending: "Not started"
            }
        }
        /// "Working · 1 min 05 s · 2 of 5 steps".
        public static func headerLine(state: String?, seconds: Double?, plan: WorkPlan?) -> String {
            [runWord(state), RunCopy.formatDuration(seconds) ?? "", plan.map { planSteps(done: $0.done, total: $0.total) } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }
        public static let summary = "Summary"
        /// The summary's chips (workView.ts `summaryWords`).
        public static func summaryChips(_ summary: WorkSummary) -> [String] {
            var out: [String] = []
            if let files = summary.files {
                out.append("\(files.count) \(files.count == 1 ? "file" : "files") changed +\(files.added) \u{2212}\(files.removed)")
            }
            if let commands = summary.commands {
                out.append(
                    "\(commands.count) \(commands.count == 1 ? "command" : "commands")"
                        + (commands.failed > 0 ? " \u{00B7} \(commands.failed) failed" : ""))
            }
            if let tests = summary.tests {
                out.append("Tests \(tests.passed) passed" + (tests.failed > 0 ? " \u{00B7} \(tests.failed) failed" : ""))
            }
            if let checks = summary.checks { out.append(checks) }
            if let took = RunCopy.formatDuration(summary.seconds) { out.append(took) }
            if let tokens = summary.tokens {
                out.append("\(compact(Double(tokens.input))) in \u{00B7} \(compact(Double(tokens.output))) out")
            }
            return out
        }

        /// Rounded counts (workView.ts `round`): 980, 1.2K, 52K, 1.3M.
        public static func compact(_ value: Double) -> String {
            guard value.isFinite else { return "" }
            func trimmed(_ tenths: Double) -> String {
                tenths.rounded() == tenths ? String(Int(tenths)) : String(format: "%.1f", tenths)
            }
            if value < 1000 { return String(Int(value.rounded())) }
            if value < 10_000 { return trimmed((value / 100).rounded() / 10) + "K" }
            if value < 1_000_000 { return String(Int((value / 1000).rounded())) + "K" }
            return trimmed((value / 100_000).rounded() / 10) + "M"
        }

        // MARK: A view in the conversation (App.vue's view links, ArtifactPanel.vue)

        /// The kind, in a word, under the view's title.
        public static func kind(_ kind: String) -> String {
            switch kind {
            case "form": "Form"
            case "table": "Table"
            case "chart": "Chart"
            case "plan": "Plan"
            case "evidence": "Evidence"
            case "quiz": "Quiz"
            case "diagram": "Diagram"
            case "dashboard": "Dashboard"
            case "prototype": "App demo"
            case "html": "Page"
            default: "View"
            }
        }
        /// A view without a title.
        public static let untitledView = "Untitled view"
        /// The card's hint: it opens the view.
        public static let opensTheView = "Opens the view"
        public static let waitingForAnswers = "Waiting for your answers"
        public static let answered = "Answered"
        public static let cancelled = "Cancelled"
        public static let stopped = "Stopped"
        public static let expired = "Expired"
        /// ArtifactPanel.vue's "Version N".
        public static func version(_ revision: Int) -> String { "Version \(revision)" }
        public static let close = "Done"
        public static let refresh = "Refresh"
        public static let couldNotRead = "Pebble couldn't show this view."

        // MARK: Forms (NativeArtifactRenderer.vue)

        public static let submitAnswers = "Submit answers"
        public static let answersBecomeInput = "Answers become task input in this conversation."
        public static let saving = "Saving…"
        public static let completeEveryField = "Complete every required field."
        public static let required = "Required"
        /// NativeArtifactRenderer.vue's "This form is {status}." for a stopped or expired form.
        public static func formIs(stopped: Bool) -> String { stopped ? "This form is stopped." : "This form is expired." }
        public static let noActiveRequest = "This form has no active input request."
        /// The waiting form in the conversation and on Reviews.
        public static let pebblesForm = "Pebble's form"
        public static let answerForm = "Answer…"
        public static let answerFormHint = "Opens the form to answer it"
        public static let yourAnswers = "Your answers"
        /// The form's sheet: Cancel closes it and sends nothing.
        public static let cancel = "Cancel"
        public static let answerSent = "Answers sent"
        public static let chooseOne = "Choose one"
        public static let writeHere = "Write here"

        // MARK: Tables, charts, plans, evidence, diagrams

        public static let noRows = "No rows."
        public static let emptyCell = "\u{2014}"
        public static func rows(_ count: Int) -> String { "\(count) \(count == 1 ? "row" : "rows")" }
        public static let chartData = "Chart data"
        public static func chartSummary(points: Int, series: Int) -> String {
            "\(points) \(points == 1 ? "point" : "points") in \(series) \(series == 1 ? "series" : "series")"
        }
        public static let diagramAsText = "Diagram as text"
        public static func edge(from: String, to: String, label: String?) -> String {
            label.map { "\(from) \u{2192} \(to): \($0)" } ?? "\(from) \u{2192} \(to)"
        }
        /// Pebble shows the step a fact came from as a "Tool receipt"; the phone names it plainly.
        public static let citedStep = "From the step"
        public static func evidenceCount(_ count: Int) -> String { "\(count) \(count == 1 ? "step" : "steps") cited" }

        // MARK: Dashboards (DashboardRenderer.vue)

        public static let dashboard = "Dashboard"
        public static func panels(_ count: Int, live: Int) -> String {
            let panels = "\(count) \(count == 1 ? "panel" : "panels")"
            return live > 0 ? "\(panels) \u{00B7} \(live) live" : panels
        }
        public static let refreshData = "Refresh Data"
        public static let refreshing = "Refreshing…"
        public static let live = "Live"
        public static let snapshot = "Snapshot"
        /// Pebble's "Waiting for host data. Use Refresh data to load it.", in the phone's words.
        public static let waitingForData = "Waiting for Pebble's data. Use Refresh Data to load it."
        public static func noLongerRefreshed(stopped: Bool) -> String {
            stopped
                ? "This dashboard is stopped. Its data is no longer refreshed."
                : "This dashboard is expired. Its data is no longer refreshed."
        }
        public static let panelUnavailable = "Pebble couldn't read this panel's data."
        public static let panelInvalid = "This panel can't be shown."
        public static let untitledPanel = "Untitled panel"
        public static let dashboardFootnote =
            "Live panels read counts from this conversation on your Mac. Snapshot panels show what Pebble wrote."
        public static func asOf(_ time: String) -> String { "as of \(time)" }
        public static func source(_ source: String) -> String {
            switch source {
            case "runs.recent": "Recent runs"
            case "runs.usage": "Run usage"
            case "jobs.fires": "Scheduled job fires"
            case "agents.tree": "Helper agents"
            case "artifacts.revisions": "View revisions"
            case "memory.stats": "Memory layer counts"
            case "git.summary": "Git summary"
            case "goals.progress": "Goal progress"
            default: "Pebble's data"
            }
        }
        public static func delta(_ value: Double) -> String { value > 0 ? "+" + number(value) : number(value) }
        /// A metric's value: at most two decimals, compact from a million (Intl.NumberFormat in Pebble's window).
        public static func number(_ value: Double) -> String {
            if abs(value) >= 1_000_000 { return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...2))) }
            return value.formatted(.number.precision(.fractionLength(0...2)))
        }

        // MARK: Quizzes (QuizRenderer.vue; lane Q, taking one on the phone)

        public static let quizLead = "Quiz \u{00B7} checked by Pebble"
        public static func quizSize(questions: Int, minutes: Int) -> String {
            "\(questions) \(questions == 1 ? "question" : "questions") \u{00B7} \(minutes) min"
        }
        public static let generatedByAI = "Questions are generated by AI. Read the explanations after you submit."
        public static let invalidQuiz = "This quiz contains invalid display data."
        public static let historicalQuiz = "Historical revision. Return to the current revision to take this quiz."
        public static let loadingAttempt = "Loading your attempt\u{2026}"

        // The intro
        public static let quizIntro =
            "Answer at your own pace within the time limit. Pebble checks your answers; the answer key is not part of "
            + "this view. Your result stays here unless you share it."
        public static func quizChanged(after revision: Int) -> String {
            "This quiz changed after revision \(revision), so your earlier attempt was closed without a grade."
        }
        public static let quizChangedWhileAnswering =
            "This quiz changed while you were answering, so that attempt was closed without a grade."
        public static let timeRanOut = "Time ran out before that attempt was submitted."
        /// "This quiz is stopped." or "This quiz is expired." (the view's status, as Pebble's window prints it).
        public static func quizIs(_ status: String) -> String { "This quiz is \(status)." }
        /// Where the bridge doesn't take quizzes from the phone (Pebble's window says it in a browser preview).
        public static let openDesktopApp = "Open the desktop app to take this quiz."
        public static let startQuiz = "Start quiz"
        public static let startAgain = "Start again"
        public static let starting = "Starting\u{2026}"

        // A question
        /// "04:31 left" (minutes and seconds, at least two digits each).
        public static func timeLeft(_ seconds: Int) -> String {
            let left = max(0, seconds)
            return "\(twoDigits(left / 60)):\(twoDigits(left % 60)) left"
        }
        /// The same for VoiceOver, which reads "04:31" as a time of day.
        public static func timeLeftSpoken(_ seconds: Int) -> String {
            let left = Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
            return "\(left) left"
        }
        public static let questionsAnswered = "Questions answered"
        public static func answeredCount(_ answered: Int, of count: Int) -> String { "\(answered) of \(count) answered" }
        public static func questionOf(_ number: Int, _ count: Int) -> String { "Question \(number) of \(count)" }
        /// The list for moving between questions (Pebble's numbered buttons say the same to VoiceOver).
        public static let jumpToQuestion = "Jump to question"
        public static func questionInList(_ number: Int, answered: Bool) -> String {
            "Question \(number)" + (answered ? ", answered" : "")
        }
        /// A choice's letter, A to F.
        public static func choiceLetter(_ index: Int) -> String {
            let letters = ["A", "B", "C", "D", "E", "F"]
            return letters.indices.contains(index) ? letters[index] : "\(index + 1)"
        }
        public static let draftSaved = "Draft saved"
        public static let draftNotSaved = "Draft not saved"
        public static func draftNotSavedBecause(_ reason: String) -> String { "Draft not saved: \(reason)" }
        public static let timeIsUp = "Time is up. Submit to see how you did."
        public static let back = "Back"
        public static let next = "Next"
        public static let checking = "Checking\u{2026}"

        // The result
        public static func score(_ score: Int, of total: Int) -> String { "\(score) / \(total)" }
        /// The score for VoiceOver, in Pebble's own words for it (quiz_grading.py `_compose`).
        public static func scoreSpoken(_ score: Int, of total: Int) -> String { "\(score) of \(total) correct" }
        public static let gradedByPebble = "Graded by Pebble."
        public static let gradedWhenTimeRanOut = "Graded when time ran out."
        public static let correct = "Correct"
        public static let incorrect = "Incorrect"
        public static let unanswered = "Unanswered"
        public static let notGraded = "Not graded"
        public static func reviewHeading(_ number: Int, _ state: String) -> String { "Question \(number) \u{00B7} \(state)" }
        public static func yourAnswer(_ choice: String) -> String { "Your answer: \(choice)" }
        public static func correctAnswer(_ choice: String) -> String { "Correct answer: \(choice)" }
        public static let shareResult = "Share result with Pebble"
        public static let sharing = "Sharing\u{2026}"
        public static let sharedWithPebble = "Shared with Pebble"
        public static let shareNote = "Pebble sees your score and each question's result only after you share them."
        public static let retakeQuiz = "Retake quiz"

        // Pebble's window says what "the app" (its own desktop app) returned. On the phone, "the app" would read as
        // Pebble Remote, so the phone names Pebble; Pebble's words stay in the `…Pebble` constants (parity-tested).
        public static let invalidAttemptPebble = "The app returned an invalid quiz attempt."
        public static let invalidAttempt = "Pebble returned an invalid quiz attempt."
        public static let otherViewPebble = "The app returned an attempt for another view."
        public static let otherView = "Pebble returned an attempt for another view."
        public static let otherConversationPebble = "The app returned an attempt for another conversation."
        public static let otherConversation = "Pebble returned an attempt for another conversation."
        public static let shareNotConfirmedPebble = "The app did not confirm the share."
        public static let shareNotConfirmed = "Pebble did not confirm the share."

        private static func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

        // MARK: App demos (PrototypeRenderer.vue)

        public static let appDemo = "App demo"
        public static let mockUpNote = "Interactive mock-up \u{00B7} controls only navigate this demo"
        public static let screen = "Screen"
        public static let previousScreen = "Previous Screen"
        public static let restartDemo = "Restart Demo"
        public static func position(_ index: Int, of count: Int) -> String { "\(index) of \(count)" }
        public static let nothingSaved = "Typing and switches stay in this preview; nothing is saved or sent."
        public static let sendFeedback = "Send Feedback"
        public static func feedbackDraft(revision: Int, screen: String) -> String {
            "Feedback on the app demo (revision \(revision), screen \(screen)): "
        }
        public static let feedbackNote = "Your words go in the message box; sending stays yours."
        public static func imagePlaceholder(_ label: String) -> String { "Image placeholder: \(label)" }
        public static func demoScreen(_ title: String) -> String { "Demo screen: \(title)" }

        // MARK: Mac-only pages (spec: html is drawn only on the Mac)

        public static let onYourMac = "Open on Your Mac"
        public static let pageOnMacNote =
            "This page is drawn only on your Mac. Open the conversation in Pebble on your Mac to see it."
    }
}
