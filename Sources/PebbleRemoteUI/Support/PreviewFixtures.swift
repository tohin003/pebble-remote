import Foundation
import PebbleProtocol
import PebbleRemoteKit

/// Small sample values for previews of the views that take plain values (rows, lines, cards). Screens that read the
/// store preview against lane A's demo store instead. Not shown anywhere in the app.
enum PreviewFixtures {
    static let started = Date.now.addingTimeInterval(-125)

    static let idleChat = ChatSummary(
        id: "c1", title: "Plan the garden beds", project: "garden", updated: .now.addingTimeInterval(-3600))
    static let liveChat = ChatSummary(
        id: "c2", title: "Fix login", project: "web-app", updated: .now.addingTimeInterval(-40), status: .editing)
    static let waitingChat = ChatSummary(
        id: "c3", title: "Tidy the test suite", project: "web-app", updated: .now.addingTimeInterval(-300),
        status: .review, waitingCount: 1)

    static let run = LiveRun(
        id: "r2", chatID: "c2", chatTitle: "Fix login", state: .running, status: .editing,
        activity: "Editing LoginForm.vue", started: started, steps: 6)

    static let review = ReviewItem(
        chatID: "c3", chatTitle: "Tidy the test suite", actionID: "a9", kind: .command,
        title: "Run npm test in web-app", detail: "npm test", created: .now.addingTimeInterval(-300))

    static let question = QuestionCard(
        chatID: "c1", chatTitle: "Plan the garden beds", questionID: "q1", runID: "r1", revision: 1, required: true,
        prompts: [
            .init(
                id: "p1", title: "Which bed should come first?",
                options: [
                    .init(id: "north", label: "North bed", detail: "Gets the morning sun"),
                    .init(id: "south", label: "South bed"),
                ], allowsFreeText: true)
        ])
}
