import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The Pebble tab's quick field, in the bar under its list: the words become the first message of a new conversation in
/// Companion, which then opens. Its button says so ("Start a New Conversation"); the conversation is made on the Mac as
/// the message is sent.
///
/// One line, so the keyboard's Send key sends (a multi-line field would add a line instead: the UX audit's U-12), and in
/// a bar pinned above the tab bar, so the field and its arrow ride above the keyboard. It looks like a conversation's
/// composer: a glass field and the one tinted glass Send.
///
/// The keyboard always lets the person go (the person's P1 of 2026-10-30: on the Pebble tab there is no Back, and the
/// keyboard hides the tab bar): Send with nothing typed closes it (`Submission`), a send that went closes it before the
/// conversation opens, and the screen closes it on a swipe down or a tap on the list (`OverviewScreen`, which owns the
/// focus). Its words stay until they are sent, as in a messaging app (`RemoteStore.unsent`, at `.askPebble`).
struct AskPebbleField: View {
    /// Whether the field has the keyboard; the screen owns it, so its list can close the keyboard too.
    var isFocused: FocusState<Bool>.Binding
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @State private var isSending = false
    /// Counts messages Pebble took: the "sent" haptic confirms a send, as in the composer, not the tap.
    @State private var sentCount = 0

    var body: some View {
        HStack(spacing: PebbleSpace.s2) {
            TextField(AppCopy.Conversation.placeholder, text: draftText)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(ask)
                .padding(.horizontal, PebbleSpace.s4)
                .padding(.vertical, PebbleSpace.s3)
                .frame(minHeight: PebbleSize.minTap)
                .glassEffect(.regular, in: .capsule)
                .accessibilityLabel(AppCopy.Conversation.placeholder)  // a name, not only a placeholder (U-61)
                .accessibilityHint(AppCopy.Home.askPebbleHint)
            Button(AppCopy.Home.startConversation, systemImage: "arrow.up", action: ask)
                .labelStyle(.iconOnly)
                .font(.body.bold())
                .buttonStyle(.pebbleGlassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(Submission(draft) == .closeKeyboard || isSending)
                .accessibilityHint(AppCopy.Home.askPebbleHint)
        }
        .padding(.horizontal)
        .padding(.vertical, PebbleSpace.s2)
        .sensoryFeedback(PebbleHaptics.sent, trigger: sentCount)
    }

    /// The field's words, kept in the store's unsent text.
    private var draft: String {
        get { store.unsent[.askPebble] }
        nonmutating set { store.unsent[.askPebble] = newValue }
    }

    private var draftText: Binding<String> {
        Binding(get: { draft }, set: { draft = $0 })
    }

    private func ask() {
        guard case .send(let text) = Submission(draft) else {
            // Nothing typed: the person only wanted out of the keyboard.
            isFocused.wrappedValue = false
            return
        }
        guard !isSending else { return }
        isSending = true
        let unsent = store.unsent
        let written = draft
        unsent[.askPebble] = ""
        Task {
            if let chat = await store.attempt({ try await store.newChat(firstMessage: text) }) {
                sentCount += 1
                isFocused.wrappedValue = false
                router.push(chat)
            } else if unsent[.askPebble].isEmpty {
                unsent[.askPebble] = written
            }
            isSending = false
        }
    }
}

extension AskPebbleField {
    /// What the field's Send does with its words: nothing typed (or only spaces and line breaks) closes the keyboard;
    /// words go, trimmed, as the first message of a new conversation.
    enum Submission: Equatable {
        case closeKeyboard
        case send(String)

        init(_ draft: String) {
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            self = text.isEmpty ? .closeKeyboard : .send(text)
        }
    }
}
