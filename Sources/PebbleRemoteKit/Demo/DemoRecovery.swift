import Foundation
import PebbleProtocol

/// The demo Pebble's commands, uncertain outcomes and model handoffs, in Pebble's shapes (process_jobs.py,
/// reconcile.py, app.py `model_handoff_*`). DemoClient owns one; DemoClient+Recovery answers with it.
struct DemoRecovery: Sendable {
    struct Process: Sendable, Hashable {
        var id: String
        var chatID: String
        var runID: String
        /// admitted, running, succeeded, failed, stopped, unknown.
        var state: String
        var uncertain: Bool
        var inspected: Bool
        var interactive: Bool
        /// What the command printed so far.
        var output: String
        /// What the person typed since the last Enter.
        var typed = ""

        var isLive: Bool { state == "admitted" || state == "running" }

        /// process_list's row.
        var json: JSONValue {
            [
                "id": .string(id), "run_id": .string(runID), "state": .string(state), "outcome_uncertain": .int(uncertain ? 1 : 0),
                "inspection_recorded": .int(inspected ? 1 : 0),
            ]
        }
    }

    struct Handoff: Sendable, Hashable {
        var chatID: String
        var runID: String
        var profile: String
        var approved = false
    }

    /// Oldest first; process_list answers newest first, as Pebble does.
    var processes: [Process] = [
        Process(
            id: DemoData.siteSync, chatID: DemoData.siteChat, runID: DemoData.siteRun, state: "unknown", uncertain: true,
            inspected: false, interactive: false,
            output: "> pebble-docs@2.0.0 sync\n> node scripts/sync-images.js\n\nCopying 14 images to public/…\n"),
        Process(
            id: DemoData.siteServer, chatID: DemoData.siteChat, runID: DemoData.siteRun, state: "running", uncertain: false,
            inspected: false, interactive: true,
            output: "> pebble-docs@2.0.0 dev\n> vite\n\n  VITE v6.0.0  ready in 412 ms\n\n  Local:   http://localhost:5173/\n\nOpen the site in your browser? (y/N) "),
    ]

    /// Each run's uncertain outcomes, as `run_readback` lists them (identifiers, verdict and basis only).
    var uncertain: [String: [JSONValue]] = [
        DemoData.mailRun: [
            [
                "call_id": "4:write-message", "tool": "AppAction", "action_id": "a-mail-draft", "kind": "app_action",
                "process_id": .null, "verdict": "occurred", "basis": "after_present", "authorization": "none",
            ],
            [
                "call_id": "6:press-send", "tool": "ScreenAct", "action_id": .null, "kind": .null, "process_id": .null,
                "verdict": "unknown", "basis": "no_broker_action", "authorization": "none",
            ],
        ]
    ]

    /// Previews by fingerprint.
    var handoffs: [String: Handoff] = [:]
}
