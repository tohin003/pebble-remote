import XCTest

/// Lane U's UX audit of Pebble Remote (`docs/lanes/U-brief.md`, the yardstick is `docs/parity/IA.md`).
///
/// XCUITest drives the Debug app on the person's iPhone, launched with `-PebbleUIAudit 1`: the in-app demo only, so
/// nothing reaches a Mac and nothing asks for Face ID. Like a curious first-time user it visits every tab, screen,
/// sheet, menu and button it can reach, photographs every state (`NNN-screen-state`), and runs
/// `performAccessibilityAudit()` on each, recording every issue without failing. Then it repeats the key screens at the
/// largest accessibility text size and in dark mode (both for this app only, through launch arguments).
///
/// Each area is its own test, starting from a fresh demo, so one area's trouble never stops the others. Findings and
/// accessibility issues are attached to each area as JSON (`findings-<area>.json`, `accessibility-<area>.json`).
///
/// Nothing here fails the run: every XCTest issue is turned into a warning plus a finding (`record(_:)`), so the run
/// always reaches the end and the result bundle holds everything it saw.
final class PebbleRemoteUIAudit: XCTestCase {
    private static let log = AuditLog()

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// An element that vanished between a check and a tap, a query that failed: recorded as a finding and kept in the
    /// results as a warning, never a failure.
    override func record(_ issue: XCTIssue) {
        var issue = issue
        if issue.severity == .error {
            Self.log.add(
                AuditLog.Finding(
                    shot: 0, area: Self.log.area, screen: name, kind: "harness", detail: issue.compactDescription))
            issue.severity = .warning
        }
        super.record(issue)
    }

    /// The Pebble tab: what Pebble is doing now, the Mac (Keep Awake, and Mac Screen since round 2), the mode chip (and
    /// Full access's question, always cancelled), Ask Pebble's bar and three ways to close its keyboard; the bottom
    /// accessory, which shows on Chats.
    @MainActor func test01PebbleTab() {
        run("pebble", minutes: 3) { $0.tourPebbleTab() }
    }

    /// Chats: Your Space, Connect a project and the folder browser, search, swipe actions, Recently Deleted, a new
    /// conversation before its first message; the keyboard in search, Rename, a new conversation and a short and a long
    /// conversation.
    @MainActor func test02Chats() {
        run("chats", minutes: 4) { $0.tourChats() }
    }

    /// A conversation: the menus while Pebble works (the model menu left open 5 s, U-53), the ⋯ menu, the title menu,
    /// the run bar, Jump to Latest, model and effort, the + menu and its sheets (the terminal command's keyboard), Rename's
    /// keyboard, a long press on a message.
    @MainActor func test03Conversation() {
        run("conversation", minutes: 4) { $0.tourConversation() }
    }

    /// Reviews: every waiting card, question (and its written answer's keyboard) and task decision, their details, and
    /// the empty state.
    @MainActor func test04Reviews() {
        run("reviews", minutes: 3) { $0.tourReviews() }
    }

    /// The demo's walkthroughs (lane R): a held change, an uncertain step in Mail, a running command, a failed task
    /// that resumes or continues on another model (the model menu left open 5 s, U-53, then the handoff, U-34); the
    /// keyboard in Type into the Command, the inspection note and Uncertain Outcomes' note.
    @MainActor func test05Walkthroughs() {
        run("walkthroughs", minutes: 3) { $0.tourWalkthroughs() }
    }

    /// Settings (round 2: once Control; the test keeps its name): Pebble's settings in the Mac's order, Toolbox,
    /// schedules (New Schedule's keyboard), shared windows, Stop Everything, the iPhone section (Connection, Paired
    /// iPhones), Recently Deleted's shortcut, then leaving the demo.
    @MainActor func test06Control() {
        run("settings", minutes: 5) { $0.tourControl() }
    }

    /// The key screens again at the largest accessibility text size (Back before a tab where a conversation hides the
    /// tab bar; ⋯ with Model and Effort, U-52; a conversation's keyboard).
    @MainActor func test07LargestText() {
        run("largest-text", minutes: 2) { $0.tourKeyScreens(look: .largestText) }
    }

    /// The key screens again in the other appearance: light when the phone is dark (the person's is), else dark.
    @MainActor func test08OtherAppearance() {
        run("other-appearance", minutes: 2) { $0.tourKeyScreens(look: .otherAppearance) }
    }

    /// Details (lane Y, fix 8): ⋯ › Details in every demo conversation; Activity's count against its list (U-45);
    /// Task, Context, Changes, Tools, Browser and More sections; every confirmation opened and declined, never given.
    /// No sweep: a sweep would tap Rewind, Compact now or a grant.
    @MainActor func test09Details() {
        run("details", minutes: 1) { $0.tourDetails() }
    }

    /// Pebble's views (lane G, contract 3.12): the login run's work view (the plan line above its first card, a card
    /// opened and closed), every view card full screen and closed with Done (Chart data, Refresh Data, the app demo's
    /// screens; the rows only the Mac acts on are only photographed), the waiting form (its row on Reviews, Cancel,
    /// Return in its text field, Submit answers, the reply going on), the charts in the other appearance and the cards
    /// at the largest text size. No sweep.
    @MainActor func test10Views() {
        run("views", minutes: 1) { $0.tourViews() }
    }

    @MainActor private func run(_ area: String, minutes: Double, _ tour: (AuditSession) -> Void) {
        Self.log.area = area
        let session = AuditSession(self, area: area, log: Self.log, minutes: minutes)
        // The area's findings and accessibility file are attached in a teardown block, which runs even when XCTest stops
        // the test part-way (the re-check lost Chats' files when its test stopped at 038 and skipped `finish()`).
        addTeardownBlock { @MainActor in
            session.finish()
        }
        tour(session)
    }
}
