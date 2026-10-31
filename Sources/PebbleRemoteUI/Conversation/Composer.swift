import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The message field and Send, led by the "+" menu (Pebble's "Add context"). While a run works, what the person sends
/// reaches the run as guidance (Pebble's `send` steers the live run), and the field says so: "Tell Pebble while it
/// works". A conversation sends to its chat; a new conversation sends its first message, which makes it on the Mac.
///
/// Typing "/" at the start lists Pebble's commands above the field (`SlashSuggestions`, lane Z), read from Pebble's
/// `command_catalogue` the first time, once acting on the Mac is unlocked, so typing never asks for Face ID by itself.
/// Choosing one fills the field; sending stays the person's tap. Return in an empty field closes the keyboard, and so does
/// a tap on the transcript or the welcome above: the screen owns the field's focus (`closesKeyboardOnTap`).
///
/// Its words stay until they are sent, as in a messaging app: closing the keyboard, leaving the conversation, a
/// reconnect or the app closing keeps them (`RemoteStore.unsent`, at `place`).
struct Composer<Leading: View>: View {
    /// The conversation it writes in (nil for a new one): words the router holds for it come into the field.
    var chatID: ChatID?
    /// Where its unsent words are kept: the conversation, or the new conversation before its first message.
    let place: UnsentText.Place
    let isRunLive: Bool
    /// Whether the field has the keyboard; the screen owns it, so a tap above the bar can close the keyboard too.
    var isFocused: FocusState<Bool>.Binding
    /// Sends the words; returns whether Pebble took them (otherwise they go back in the field).
    let send: (String) async -> Bool
    let onSent: () -> Void
    let leading: Leading
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appTab) private var appTab
    @State private var isSending = false
    @State private var sentCount = 0
    /// Pebble's commands, once read (nil before).
    @State private var commands: [PebbleCommand]?

    init(
        chatID: ChatID? = nil, place: UnsentText.Place, isRunLive: Bool = false, isFocused: FocusState<Bool>.Binding,
        send: @escaping (String) async -> Bool, onSent: @escaping () -> Void = {}, @ViewBuilder leading: () -> Leading
    ) {
        self.chatID = chatID
        self.place = place
        self.isRunLive = isRunLive
        self.isFocused = isFocused
        self.send = send
        self.onSent = onSent
        self.leading = leading()
    }

    var body: some View {
        VStack(spacing: PebbleSpace.s2) {
            if let rows = SlashRow.rows(for: draft, catalogue: commands, isWorking: isRunLive) {
                SlashSuggestions(rows: rows, choose: choose)
            }
            HStack(alignment: .bottom, spacing: PebbleSpace.s2) {
                leading
                TextField(
                    isRunLive ? AppCopy.Conversation.placeholderWhileWorking : AppCopy.Conversation.placeholder,
                    text: draftText, axis: .vertical
                )
                .lineLimit(1...6)
                // Its own height for its width: one line when empty, up to six as the words grow. Without this the
                // field took extra height from the bar (75 pt when empty in the re-check's trees: two to three lines).
                .fixedSize(horizontal: false, vertical: true)
                .focused(isFocused)
                .closesKeyboardOnEmptyReturn(draftText, focus: isFocused)
                .accessibilityLabel(AppCopy.Conversation.placeholder)  // a name, not only a placeholder (U-61)
                .padding(.horizontal, PebbleSpace.s4)
                .padding(.vertical, PebbleSpace.s3)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
                Button(AppCopy.Conversation.send, systemImage: "arrow.up", action: sendDraft)
                    .labelStyle(.iconOnly)
                    .font(.body.bold())
                    .buttonStyle(.pebbleGlassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .disabled(trimmed.isEmpty || isSending || !store.bridgeOffers("send"))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, PebbleSpace.s2)
        .sensoryFeedback(PebbleHaptics.sent, trigger: sentCount)
        .task(id: wantsCommands) {
            if wantsCommands { await readCommands() }
        }
        // An app demo's Send Feedback (App.vue `demoFeedback`): the words join the field and it takes the keyboard,
        // once the full-screen view has gone.
        .onChange(of: router.composerWords, initial: true) {
            guard let chatID, let words = router.takeComposerWords(for: chatID, on: appTab) else { return }
            draft = ComposerWords.merged(draft, words)
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                isFocused.wrappedValue = true
            }
        }
    }

    /// The field's words, kept in the store's unsent text for this place.
    private var draft: String {
        get { store.unsent[place] }
        nonmutating set { store.unsent[place] = newValue }
    }

    private var draftText: Binding<String> {
        Binding(get: { draft }, set: { draft = $0 })
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The field starts a command and Pebble's commands aren't read yet, and reading them won't ask for Face ID.
    private var wantsCommands: Bool {
        draft.hasPrefix("/") && commands == nil && store.bridgeOffers("command_catalogue")
            && (!store.usesUnlock || store.isUnlocked)
    }

    private func readCommands() async {
        guard let read = try? await store.commandCatalogue() else { return }
        commands = read
    }

    /// A line of the "/" list fills the field; nothing is sent.
    private func choose(_ row: SlashRow) {
        guard let text = row.chosen(in: draft) else { return }
        draft = text
        isFocused.wrappedValue = true
    }

    private func sendDraft() {
        let text = trimmed
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        // Held here: the screen may be gone by the time Pebble answers, and its words must still come back.
        let unsent = store.unsent
        let place = place
        let written = draft
        unsent[place] = ""
        Task {
            let sent = await send(text)
            isSending = false
            if sent {
                sentCount += 1
                onSent()
            } else if unsent[place].isEmpty {
                unsent[place] = written
            }
        }
    }
}
