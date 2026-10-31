import Foundation
import PebbleProtocol

/// One of Pebble's typed commands, as `command_catalogue` lists them (runtime_commands.py CATALOGUE): the name after
/// "/", the arguments as Pebble writes them ("[run-id]", "text"), and its one-line description. Sent as an ordinary
/// message (`send`); Pebble answers at once, without a task.
public struct PebbleCommand: Sendable, Hashable, Identifiable {
    public var name: String
    public var arguments: String
    public var description: String
    public var id: String { name }

    public init(name: String, arguments: String = "", description: String) {
        self.name = name
        self.arguments = arguments
        self.description = description
    }

    /// The commands of a `command_catalogue` answer, by Pebble's window's rule (slashCommands.ts `validHost`): a name of
    /// lowercase letters, digits, "_" or "-" that starts with a letter, at most 32; arguments of at most 160 characters;
    /// a description of at most 400; each name once; at most 200 commands. Anything else is left out.
    public static func catalogue(_ json: JSONValue) -> [PebbleCommand] {
        var seen: Set<String> = []
        var commands: [PebbleCommand] = []
        for item in json.array ?? [] {
            guard let name = item["name"]?.string, isName(name), !seen.contains(name),
                let arguments = item["arguments"]?.string, arguments.count <= 160,
                let description = item["description"]?.string, description.count <= 400
            else { continue }
            seen.insert(name)
            commands.append(PebbleCommand(name: name, arguments: arguments, description: description))
            if commands.count >= 200 { break }
        }
        return commands
    }

    /// slashCommands.ts `NAME`: `^[a-z][a-z0-9_-]{0,31}$`.
    static func isName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, ("a"..."z").contains(first), name.unicodeScalars.count <= 32 else {
            return false
        }
        return name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }
    }

    /// Choosing it leaves the person something to type: an argument it needs ("text", "agent-id"), not an optional one
    /// ("[run-id]") (slashCommands.ts `needsArguments`).
    public var needsArguments: Bool {
        let wanted = arguments.trimmingCharacters(in: .whitespaces)
        return !wanted.isEmpty && !wanted.hasPrefix("[")
    }

    /// Pebble refuses these while a task runs; the window lists them dimmed with the reason (slashCommands.ts IDLE_ONLY).
    public static let idleOnly: Set<String> = ["compact", "handoff", "skill"]

    /// The window's first rows, in order, where Pebble offers them (slashCommands.ts STARTER without the window's own
    /// actions /new, /model and /rewind); then the rest of the catalogue in Pebble's order.
    public static let starters = ["goal", "status", "compact", "memory", "skill"]
}

/// The composer's text read as a command being typed (slashCommands.ts `parseSlash`): "/" and a name, then the
/// arguments typed so far and the one being typed.
public struct SlashInput: Sendable, Hashable {
    public enum Stage: Sendable, Hashable {
        /// Only "/" and (part of) a name: the commands are listed.
        case name
        /// A space after the name: the options for the next argument are listed.
        case argument
    }

    /// Lowercased, as Pebble reads it.
    public var name: String
    public var args: [String]
    public var partial: String
    public var stage: Stage

    public init(name: String, args: [String] = [], partial: String = "", stage: Stage) {
        self.name = name
        self.args = args
        self.partial = partial
        self.stage = stage
    }

    /// Nil unless the text is one line that starts with "/" and a name of at most 32 letters, digits, "_" or "-".
    public static func parse(_ text: String) -> SlashInput? {
        guard text.first == "/", !text.contains(where: \.isNewline) else { return nil }
        let body = text.dropFirst()
        let nameEnd = body.firstIndex { !isNameCharacter($0) } ?? body.endIndex
        let typedName = body[..<nameEnd]
        guard typedName.count <= 32 else { return nil }
        let name = typedName.lowercased()
        let rest = body[nameEnd...]
        guard let separator = rest.first else { return SlashInput(name: name, stage: .name) }
        guard separator.isWhitespace, !name.isEmpty else { return nil }
        let after = String(rest.drop(while: \.isWhitespace))
        let parts = Self.tokens(after)
        let last = parts.last ?? ""
        let open = last.hasPrefix("\"") && (last.count == 1 || !last.hasSuffix("\""))
        let typing = open || (!after.isEmpty && !(after.last?.isWhitespace ?? false))
        return SlashInput(
            name: name, args: typing ? Array(parts.dropLast()) : parts, partial: typing ? last : "", stage: .argument)
    }

    /// `[A-Za-z0-9_-]`.
    static func isNameCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    /// The window's tokens (`/"[^"]*(?:"|$)|\S+/g`): a quoted part, closed or still open at the end, or a run of
    /// anything but spaces.
    static func tokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }
            var end = text.index(after: index)
            if text[index] == "\"" {
                while end < text.endIndex, text[end] != "\"" { end = text.index(after: end) }
                if end < text.endIndex { end = text.index(after: end) }
            } else {
                while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
            }
            tokens.append(String(text[index..<end]))
            index = end
        }
        return tokens
    }
}

/// The composer's "/" list, by the rules of Pebble's window (slashCommands.ts), with the phone's one change: what settles
/// a goal is never offered (F5).
public enum SlashCommands {
    /// The window's order: its first rows, then the rest of the catalogue.
    public static func ordered(_ catalogue: [PebbleCommand]) -> [PebbleCommand] {
        var order = starters(in: catalogue)
        for command in catalogue where !order.contains(command) { order.append(command) }
        return order
    }

    static func starters(in catalogue: [PebbleCommand]) -> [PebbleCommand] {
        PebbleCommand.starters.compactMap { name in catalogue.first { $0.name == name } }
    }

    /// The commands matching what was typed after "/" (slashCommands.ts `filterSlash`): the exact name, then names
    /// that start with it, then names holding it, then descriptions holding it; in list order within each.
    public static func filter(_ commands: [PebbleCommand], query: String) -> [PebbleCommand] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return commands }
        func rank(_ command: PebbleCommand) -> Int? {
            if command.name == needle { return 0 }
            if command.name.hasPrefix(needle) { return 1 }
            if command.name.contains(needle) { return 2 }
            if command.description.lowercased().contains(needle) { return 3 }
            return nil
        }
        return commands.enumerated()
            .compactMap { offset, command in rank(command).map { (rank: $0, offset: offset, command: command) } }
            .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
            .map(\.command)
    }

    /// The words the window offers for the argument being typed (slashCommands.ts `argumentOptions`), where they come
    /// from the command itself: /memory's three, /goal's pause and resume, /criteria's add and its --evidence, and
    /// /export's formats. The words that settle a goal (`settling`) are never offered.
    public static func options(for input: SlashInput) -> [String] {
        guard input.stage == .argument else { return [] }
        let at = input.args.count
        let words: [String]
        switch (input.name, at) {
        case ("memory", 0): words = ["status", "candidates", "maintain"]
        case ("goal", 0): words = ["pause", "resume"]
        case ("criteria", 0): words = ["add"]
        case ("criteria", 1) where input.args.first == "add": words = ["--evidence"]
        case ("export", 1): words = ["docx", "xlsx", "csv", "html"]
        default: words = []
        }
        let needle = input.partial.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
        guard !needle.isEmpty else { return words }
        let starting = words.filter { $0.hasPrefix(needle) }
        return starting + words.filter { !starting.contains($0) && $0.contains(needle) }
    }

    /// The composer's text once an option is chosen (slashCommands.ts `completeArgument`).
    public static func complete(_ input: SlashInput, with option: String) -> String {
        "/" + input.name + " " + (input.args + [option]).joined(separator: " ") + " "
    }

    /// The composer's text once a command is chosen: its name and a space, ready for an argument or for Send.
    public static func fill(_ command: PebbleCommand) -> String { "/" + command.name + " " }

    /// The words that settle a goal, by command (`settles_goal` in Pebble's shell, main.rs): /goal done and abandon,
    /// /criteria check, uncheck, accept and reject. The "/" list never offers them, in its words or in the arguments it
    /// shows (the lead, 02:55): on the phone a goal is settled in the conversation's Details › Task, with Face ID. A
    /// person who types one anyway sends it like any message, and Pebble answers.
    public static let settling: [String: Set<String>] = [
        "goal": ["done", "abandon"], "criteria": ["check", "uncheck", "accept", "reject"],
    ]

    /// A command's arguments as the list shows them: Pebble's own, less the alternatives that settle a goal
    /// ("[\"title\"|done|pause|resume|abandon]" shows as "[\"title\"|pause|resume]").
    public static func shownArguments(_ command: PebbleCommand) -> String {
        let arguments = command.arguments.trimmingCharacters(in: .whitespaces)
        guard let settles = settling[command.name], arguments.hasPrefix("["), arguments.hasSuffix("]") else {
            return command.arguments
        }
        let choices = arguments.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
        let kept = choices.filter { choice in
            let first = choice.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
            return !settles.contains(first)
        }
        return "[" + kept.joined(separator: "|") + "]"
    }
}
