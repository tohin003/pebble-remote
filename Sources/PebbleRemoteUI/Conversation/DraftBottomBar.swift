import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Below a new conversation: what waits for its first message (kept on the phone until then), the model and effort
/// Pebble uses (in the ⋯ menu at accessibility text sizes), and the composer with its "+" menu. Sending makes the
/// conversation on the Mac.
struct DraftBottomBar: View {
    let draft: ConversationDraft
    @Binding var sheet: ConversationSheet?
    /// Where the screen puts the model and effort: the chips show here only with `.chips`.
    var modelEffort: ModelEffortPlacement = .chips
    /// Whether the composer has the keyboard; the screen owns it, so a tap on the welcome closes the keyboard.
    var isWriting: FocusState<Bool>.Binding
    /// The first message went: the conversation's id on the Mac.
    let made: (ChatID) -> Void
    @Environment(RemoteStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            if store.usesUnlock && !store.isUnlocked {
                UnlockStatusRow()
                    .padding(.horizontal)
                    .padding(.top, PebbleSpace.s2)
            }
            let waiting = store.pendingAttachments(for: draft)
            if !waiting.isEmpty {
                PendingAttachmentsBar(attachments: waiting, remove: remove)
                    .padding(.top, PebbleSpace.s2)
            }
            // While a "/" command is typed its list sits above the field and the chips step aside (U-57).
            if modelEffort.showsChips && SlashInput.parse(store.unsent[.newConversation(draft.id)]) == nil {
                ModelEffortBar()
                    .padding(.horizontal)
                    .padding(.top, PebbleSpace.s2)
            }
            Composer(place: .newConversation(draft.id), isFocused: isWriting, send: send) {
                let offers = ComposerAddMenu.Offers.offered(by: store)
                if !offers.isEmpty {
                    ComposerAddMenu(offers: offers, isWorking: false, sheet: $sheet, attach: attach)
                }
            }
        }
        // The model menu's list, read here so it is there in the ⋯ menu as well as on the chip.
        .task {
            if store.models.isEmpty, store.bridgeOffers("model_select") { await store.load(.models) }
        }
    }

    private func send(_ text: String) async -> Bool {
        let connects = draft.place.map { !store.isKnownProject($0.path) } ?? false
        let sent: ChatID?? = await store.attempt { try await store.send(text, from: draft) }
        guard case let chat?? = sent else { return false }
        if connects { ProjectConnected.announce() }
        made(chat)
        return true
    }

    private func attach(_ data: Data, _ name: String, _ preview: Data?) async -> Bool {
        await store.attempt { try store.attach(data, name: name, preview: preview, to: draft) }
    }

    private func remove(_ attachment: AttachmentRef) {
        Task { await store.attempt { try await store.removeAttachment(attachment, from: draft) } }
    }
}
