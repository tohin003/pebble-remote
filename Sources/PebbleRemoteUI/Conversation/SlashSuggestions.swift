import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The composer's "/" list, above the message field (SlashMenu.vue on the phone): each command with its arguments as
/// Pebble writes them and its one-line description, or the words for the argument being typed. Choosing one fills the
/// field; sending stays the person's tap. In the control layer, so on glass like the field; it scrolls when the list is
/// longer than about three rows, and never takes the keyboard away. Capped there because the keyboard is up while it
/// shows: at 236 pt the bar started a quarter of the way down the screen (the re-check's U-57).
struct SlashSuggestions: View {
    let rows: [SlashRow]
    let choose: (SlashRow) -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            SlashRowStack(rows: rows, choose: choose)
            ScrollView {
                SlashRowStack(rows: rows, choose: choose)
            }
            .scrollDismissesKeyboard(.never)
        }
        .frame(maxHeight: 150)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppCopy.Slash.label)
    }
}

/// The list's lines, one under the other.
private struct SlashRowStack: View {
    let rows: [SlashRow]
    let choose: (SlashRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                SlashRowView(row: row) { choose(row) }
            }
        }
        .padding(.vertical, PebbleSpace.s1)
    }
}

/// One line: "/name [arguments]" over its description; a word and Pebble's note; or a note alone.
private struct SlashRowView: View {
    let row: SlashRow
    let choose: () -> Void

    var body: some View {
        switch row {
        case .command(let command, let unavailable):
            Button(action: choose) {
                SlashLine(
                    title: AppCopy.Slash.command(command.name), hint: SlashCommands.shownArguments(command),
                    detail: unavailable ?? command.description)
            }
            .buttonStyle(.plain)
            .disabled(unavailable != nil)
            .opacity(unavailable == nil ? 1 : 0.55)  // dimmed, never hidden, so the rule is learnt (slashCommands.ts)
        case .option(let word, let note):
            Button(action: choose) {
                SlashLine(title: word, hint: "", detail: note)
            }
            .buttonStyle(.plain)
        case .note(let text):
            Text(text)
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: PebbleSize.minTap, alignment: .leading)
                .padding(.horizontal, PebbleSpace.s4)
        }
    }
}

/// A line's words: the title and its hint on one line, the detail under them.
private struct SlashLine: View {
    let title: String
    let hint: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
                Text(verbatim: title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                if !hint.isEmpty {
                    Text(verbatim: hint)
                        .font(PebbleFont.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: PebbleSize.minTap, alignment: .leading)
        .padding(.horizontal, PebbleSpace.s4)
        .padding(.vertical, PebbleSpace.s1)
        .contentShape(.rect)
    }
}
