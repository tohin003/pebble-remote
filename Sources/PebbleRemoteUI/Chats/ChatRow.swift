import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// One chat: title, project, when it last changed, and what it is doing (a status badge) or how much waits; words written
/// here and not sent yet show under them after "Draft:", as a messaging app marks a chat's draft. At accessibility text
/// sizes the parts stack, so the title keeps the full width. VoiceOver reads the row as one element.
struct ChatRow: View {
    let chat: ChatSummary
    @Environment(RemoteStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let line = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PebbleSpace.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            line {
                Text(chat.title.isEmpty ? AppCopy.Chats.untitled : chat.title)
                    .font(.headline)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                Spacer(minLength: 0)
                if let updated = chat.updated {
                    Text(updated.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        .font(PebbleFont.meta)
                        .foregroundStyle(.secondary)
                }
            }
            line {
                if let project = chat.project {
                    Label(project, systemImage: PebbleSymbol.project)
                        .font(PebbleFont.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)  // the project's name keeps its room; it identifies the row
                }
                Spacer(minLength: 0)
                if Self.showsCount(waiting: chat.waitingCount, status: chat.status) {
                    // Pebble's "needs you" ink (as StatusPill draws it); system orange text is 2.2:1 on a white row.
                    Text(AppCopy.Chats.waiting(chat.waitingCount))
                        .font(PebbleFont.meta)
                        .bold()
                        .foregroundStyle(PebbleColor.accent)
                }
                if isHeld {
                    HeldPill()
                } else if let status = chat.status {
                    StatusPill(status: status)
                }
            }
            if let unsent = unsentLine {
                Text(unsent)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
        }
        .padding(.vertical, PebbleSpace.s1)
        .accessibilityElement(children: .combine)
    }

    /// "Draft:" in Pebble's accent, then the first line of the words waiting unsent in this conversation; nil when none.
    private var unsentLine: AttributedString? {
        let words = store.unsent[.chat(chat.id)]
        guard let first = words.split(whereSeparator: \.isNewline).first(where: { !$0.allSatisfy(\.isWhitespace) })
        else { return nil }
        var label = AttributedString(AppCopy.Chats.draft)
        label.foregroundColor = PebbleColor.accent
        label.inlinePresentationIntent = .stronglyEmphasized
        return label + AttributedString(" " + first.trimmingCharacters(in: .whitespaces))
    }

    /// The chat's task is held for verification ("Pebble's change isn't verified yet."): Pebble's `blocked` key also
    /// covers a task that reached its limit, so the waiting list, which holds the task, tells the two apart.
    private var isHeld: Bool {
        guard chat.status == .blocked else { return false }
        return store.waiting.contains { item in
            if case .task(let task) = item { return task.chatID == chat.id && task.isHeld }
            return false
        }
    }

    /// "N waiting" only where it adds to the pill (UX audit U-17): a pill that already says the chat waits for the
    /// person makes "1 waiting" a second label for one fact; a count above one still says something.
    static func showsCount(waiting: Int, status: StatusKey?) -> Bool {
        guard waiting > 0 else { return false }
        guard let status, pillSaysItWaits(status) else { return true }
        return waiting > 1
    }

    /// The pill's word already says the chat waits for the person: an answer, a review, a check, a held task.
    static func pillSaysItWaits(_ status: StatusKey) -> Bool {
        [.question, .review, .uncertain, .blocked].contains(status)
    }
}

/// A held task's word in a pill (UX audit U-20): Pebble's "Needs verification" in place of the `blocked` key's "Blocked",
/// drawn as StatusPill draws a state that waits for the person.
private struct HeldPill: View {
    var body: some View {
        Label(AppCopy.Held.needsVerification, systemImage: PebbleSymbol.status(.review))
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .font(PebbleFont.chip)
            .foregroundStyle(PebbleColor.accent)
            .padding(.horizontal, PebbleSpace.s2 + 2)
            .padding(.vertical, PebbleSpace.s1)
            .fixedSize()
            .background(PebbleColor.soft, in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppCopy.Held.label)
    }
}
