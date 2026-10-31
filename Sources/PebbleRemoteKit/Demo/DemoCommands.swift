import Foundation
import PebbleProtocol

/// Pebble's typed commands in the demo (lane Z, item 3): `command_catalogue` answers with Pebble's own catalogue, word
/// for word (runtime_commands.py CATALOGUE), and a sent command gets a reply shaped like Pebble's for the few the demo
/// can answer honestly. Others say what Pebble would need: the demo has no Mac behind it.
enum DemoCommands {
    /// runtime_commands.py CATALOGUE, in Pebble's order.
    static let catalogue: [(name: String, arguments: String, description: String)] = [
        ("jobs", "", "List this conversation's schedules and waiting notifications."),
        ("git", "", "Show which files changed in this project's Git repository."),
        ("agents", "", "List the agents working on the latest task and what they have used."),
        ("agent", "agent-id", "Show one agent's task, progress and result."),
        ("views", "", "List the views saved in this conversation."),
        ("mods", "", "List installed display code (mods), a developer feature."),
        ("help", "", "List the commands you can type here."),
        ("status", "", "Show how the latest task in this conversation is going."),
        ("runs", "", "List recent tasks in this conversation."),
        ("pause", "", "Pause the running task at a safe point."),
        ("resume", "[run-id] [--steps N] [--seconds N]", "Resume a paused or stopped task, optionally with more steps or time."),
        ("cancel", "", "Stop this conversation's running task."),
        ("steer", "text", "Send a follow-up to the running task."),
        ("plan", "", "Show the task's plan and what supports each step."),
        ("questions", "", "List questions waiting for your answer."),
        ("context", "[run-id]", "Show how much the model sees for a task and which files need a fresh read."),
        ("handoff", "[run-id]", "Save what a task needs to continue later, and show what it holds."),
        ("compact", "[run-id]", "Make room by archiving older context between steps; no model is asked."),
        ("memory", "[status|candidates|maintain]", "Show memory counts or waiting memories, or check waiting memories now."),
        ("skills", "", "List installed skills and whether each is on."),
        ("skill", "\"name or ID\" task", "Start a new task with complete pinned instructions from one enabled skill."),
        ("plugins", "", "List the connectors you have enabled and their tools."),
        ("hooks", "", "List the hook checks recorded in this conversation."),
        ("goal", "[\"title\"|done|pause|resume|abandon]", "Start, show or settle this conversation's goal; done needs every criterion met."),
        ("criteria", "[add [--evidence] \"text\"|check|uncheck|accept|reject criterion-id]", "List or change the goal's completion criteria; evidence criteria need current results of finished steps."),
        ("blockers", "", "List what holds up the goal or task: questions, reviews, failed or unclear results."),
        ("exports", "", "List this conversation's export files and whether each was checked; nothing is published."),
        ("export", "view-id docx|xlsx|csv|html", "Plan an export of a view; saving needs the Save dialog and nothing is published."),
    ]

    /// `command_catalogue`'s answer.
    static var catalogueJSON: JSONValue {
        .array(catalogue.map { ["name": .string($0.name), "arguments": .string($0.arguments), "description": .string($0.description)] })
    }

    /// Whether Pebble knows the command (its name after "/", lowercased).
    static func knows(_ text: String) -> Bool {
        catalogue.contains { $0.name == name(of: text) }
    }

    static func name(of text: String) -> String {
        String(text.dropFirst().split(whereSeparator: \.isWhitespace).first ?? "").lowercased()
    }

    /// Pebble's refusal of a name it doesn't know (runtime_commands.py `command`).
    static let unknown = "Unknown command. Type /help to see the commands you can use."

    /// The reply to a command, in the shape of Pebble's; `memory` gives the demo's memory counts.
    static func reply(_ text: String, memory: DemoMemory) -> String {
        switch name(of: text) {
        case "help":
            return "Commands you can type:\n\n" + catalogue.map { "- /\($0.name) \($0.arguments) \u{2014} \($0.description)" }
                .joined(separator: "\n")
        case "memory":
            return memory.statusReply()
        case "goal":
            return "This conversation has no current goal. Start one with /goal \"title\"."
        case "criteria", "blockers":
            return "This conversation has no goal or runs yet."
        case "jobs":
            return "This conversation has no schedules or waiting notifications."
        case "views":
            return "This conversation has no saved views."
        case "hooks":
            return "No hook checks were recorded in this conversation."
        default:
            return "This is the demo, so there's no Mac to answer /\(name(of: text)). With your Mac paired, Pebble answers it here at once."
        }
    }
}
