import PebbleDesign
import PebbleRemoteKit

/// One line of the composer's "/" list (item 12 of the inventory; SlashMenu.vue).
nonisolated enum SlashRow: Hashable, Identifiable {
    /// A command, dimmed with Pebble's reason when it can't run now.
    case command(PebbleCommand, unavailable: String?)
    /// A word for the argument being typed, with Pebble's note where it has one.
    case option(String, note: String?)
    /// A line with nothing to choose: no command matches.
    case note(String)

    var id: String {
        switch self {
        case .command(let command, _): "c/" + command.name
        case .option(let word, _): "o/" + word
        case .note(let text): "n/" + text
        }
    }

    /// What the list shows for the composer's text (slashCommands.ts); nil when it doesn't show. Typing "/" lists
    /// Pebble's commands once they are read (`catalogue`), the best match first; after a command and a space, the words
    /// its next argument takes. The words that settle a goal are never among them (`SlashCommands.settling`); typed by
    /// hand, they go to Pebble like any message, and the list adds nothing (the lead, 02:55).
    static func rows(for draft: String, catalogue: [PebbleCommand]?, isWorking: Bool) -> [SlashRow]? {
        guard let input = SlashInput.parse(draft) else { return nil }
        switch input.stage {
        case .name:
            guard let catalogue, !catalogue.isEmpty else { return nil }
            let matches = SlashCommands.filter(SlashCommands.ordered(catalogue), query: input.name)
            guard !matches.isEmpty else { return [.note(AppCopy.Slash.noMatch)] }
            return matches.map { command -> SlashRow in
                let resting = isWorking && PebbleCommand.idleOnly.contains(command.name)
                return .command(command, unavailable: resting ? AppCopy.Slash.idleOnly : nil)
            }
        case .argument:
            let words = SlashCommands.options(for: input)
            guard !words.isEmpty else { return nil }
            return words.map { word -> SlashRow in
                .option(word, note: AppCopy.Slash.note(command: input.name, option: word))
            }
        }
    }

    /// The composer's text once this line is chosen; nil for a line with nothing to choose or a dimmed command.
    func chosen(in draft: String) -> String? {
        switch self {
        case .command(let command, let unavailable):
            return unavailable == nil ? SlashCommands.fill(command) : nil
        case .option(let word, _):
            return SlashInput.parse(draft).map { SlashCommands.complete($0, with: word) }
        case .note:
            return nil
        }
    }
}
