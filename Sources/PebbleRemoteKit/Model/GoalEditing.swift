import Foundation
import PebbleProtocol

// Lane T (2026-10-31): what Details › Task needs to edit a goal as Pebble's goal panel does (GoalPanel.vue; goals.py
// `_snapshot`, `_blockers` and the human routes). Read tolerantly: an item without its kind is left out.

/// What blocks one step (goals.py `_snapshot`: `{kind, ref, active}`): the person's own note (`text`, with the note as
/// `ref`), a failed outcome, a question or a review. `active` is false once what blocked it is settled.
public struct StepBlocker: Sendable, Hashable {
    public var kind: String
    public var ref: String?
    public var isActive: Bool

    public init(kind: String, ref: String? = nil, isActive: Bool = true) {
        self.kind = kind
        self.ref = ref
        self.isActive = isActive
    }

    public init?(json: JSONValue?) {
        guard let json, let kind = json["kind"]?.string, !kind.isEmpty else { return nil }
        self.init(kind: kind, ref: json["ref"]?.string, isActive: json["active"]?.bool ?? true)
    }
}

/// One of what holds a goal up (goals.py `_blockers`), as GoalPanel.vue's Blockers table lists it.
public struct GoalBlocker: Sendable, Hashable, Identifiable {
    /// question, approval, failure or text (the person's own note on a step).
    public var kind: String
    /// What it names: the question's or the card's id, a failed step, or the blocked step (for `text`).
    public var ref: String
    /// Pebble's words ("Needs your review").
    public var label: String
    public var runID: RunID?
    public var stepID: String?
    /// The note, or the question's words.
    public var detail: String?
    /// human or agent: who wrote `detail` (a question's words are Pebble's).
    public var detailOrigin: String?

    public var id: String { [kind, ref, runID ?? ""].joined(separator: ":") }

    public init(
        kind: String, ref: String, label: String, runID: RunID? = nil, stepID: String? = nil, detail: String? = nil,
        detailOrigin: String? = nil
    ) {
        self.kind = kind
        self.ref = ref
        self.label = label
        self.runID = runID
        self.stepID = stepID
        self.detail = detail
        self.detailOrigin = detailOrigin
    }

    public init?(json: JSONValue) {
        guard let kind = json["kind"]?.string, !kind.isEmpty, let label = json["label"]?.string else { return nil }
        self.init(
            kind: kind, ref: json["ref"]?.string ?? "", label: label, runID: json["run_id"]?.string,
            stepID: json["step_id"]?.string, detail: json["detail"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            detailOrigin: json["detail_origin"]?.string)
    }

    /// A card that waits for the person's review: GoalPanel.vue's "Review" opens it.
    public var waitsForReview: Bool { kind == "approval" }
}

/// Pebble's limits on what a person writes into a goal (goals.py `TITLE`, `TEXT`, `BLOCKER_TEXT`, `MAX_STEPS`,
/// `MAX_DEPENDS`); the Mac's fields stop at the same lengths (GoalPanel.vue `maxlength`).
public enum GoalLimits {
    public static let stepTitle = 240
    public static let criterion = 500
    public static let blockReason = 300
    public static let steps = 20
    public static let after = 8
}

extension GoalRecord {
    /// Steps a person may block: neither completed nor already blocked (GoalPanel.vue `blockable`).
    public var blockableSteps: [Step] { steps.filter { !["completed", "blocked"].contains($0.status) } }

    /// The steps a step may come after: every other step (Pebble refuses a loop in its own words).
    public func possibleAfter(for step: Step?) -> [Step] { steps.filter { $0.id != step?.id } }
}
