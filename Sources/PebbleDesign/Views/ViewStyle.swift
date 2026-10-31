import PebbleProtocol
import SwiftUI

// Lane G (2026-10-31): how Pebble's views look on the phone (pebble-ui-spec v1, rule 5): flat surfaces with hairlines,
// two weights, sentence case; colour carries meaning (done in green, failed in red, waiting or open in amber) and the
// same words always sit beside it, so nothing is said by colour alone.

/// SF Symbols for the views (all in SF Symbols 5, so on iOS 26).
nonisolated public enum ViewSymbol {
    /// A native view's kind.
    public static func kind(_ kind: String) -> String {
        switch kind {
        case "form": "list.bullet.rectangle"
        case "table": "tablecells"
        case "chart": "chart.bar"
        case "plan": "list.number"
        case "evidence": "checkmark.seal"
        case "quiz": "graduationcap"
        case "diagram": "point.3.connected.trianglepath.dotted"
        case "dashboard": "square.grid.2x2"
        case "prototype": "iphone"
        case "html": "doc.richtext"
        default: "questionmark.square"
        }
    }

    /// A work-view card's kind.
    public static func card(_ kind: WorkCardKind) -> String {
        switch kind {
        case .explored: "eyeglasses"
        case .web: "globe"
        case .files: "pencil"
        case .command: "terminal"
        case .tests: "testtube.2"
        case .git: "arrow.triangle.branch"
        case .window: "cursorarrow.click.2"
        case .agents: "person.2"
        case .checks: "checkmark.shield"
        }
    }

    /// The mark beside a tone's words.
    public static func tone(_ tone: WorkTone) -> String {
        switch tone {
        case .good: "checkmark.circle"
        case .bad: "exclamationmark.triangle"
        case .open: "clock"
        case .neutral: "circle.dotted"
        }
    }

    /// A plan step's mark.
    public static func step(_ status: WorkPlan.Status) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .inProgress: "circle.lefthalf.filled"
        case .blocked: "exclamationmark.circle"
        case .pending: "circle"
        }
    }

    public static let onYourMac = "laptopcomputer"
    public static let update = "arrow.down.app"
    public static let back = "chevron.backward"
    public static let restart = "arrow.counterclockwise"
    public static let refresh = "arrow.clockwise"
    public static let disclosure = "chevron.right"

    // Lane Q: a quiz (QuizRenderer.vue's Phosphor icons, in SF Symbols).
    public static let forward = "chevron.forward"
    public static let startQuiz = "play.fill"
    /// The button that lists the questions.
    public static let questionList = "chevron.up.chevron.down"
    /// A question in that list: answered, or not yet.
    public static let answered = "circle.inset.filled"
    public static let unanswered = "circle"
    public static let score = "checkmark.circle"
    public static let shareResult = "paperplane"
    public static let shared = "checkmark.circle.fill"
    /// A reviewed question's mark beside its words.
    public static let reviewCorrect = "checkmark.circle.fill"
    public static let reviewIncorrect = "xmark.circle.fill"
    public static let reviewUnanswered = "minus.circle"
    public static let reviewNotGraded = "questionmark.circle"
}

extension WorkTone {
    /// The tone's colour: Pebble's `--ok`, `--danger` and `--warn`, and secondary text when it means nothing.
    public var color: Color {
        switch self {
        case .good: PebbleColor.ok
        case .bad: PebbleColor.danger
        case .open: PebbleColor.warn
        case .neutral: PebbleColor.secondaryText
        }
    }
}

extension WorkPlan.Status {
    /// Done is good, blocked is open, the rest say nothing by colour.
    public var tone: WorkTone {
        switch self {
        case .completed: .good
        case .blocked: .open
        case .inProgress, .pending: .neutral
        }
    }
}
