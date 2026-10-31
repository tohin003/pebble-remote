import PebbleRemoteKit

/// A conversation pushed onto a tab's navigation stack, or a new conversation that isn't on the Mac yet (a draft, by its
/// id in the store). Every tab that can open a chat registers this one route.
struct ChatRoute: Hashable {
    enum Target: Hashable {
        case chat(ChatID)
        /// `RemoteStore.draft(_:)`: made on the Mac when its first message is sent.
        case draft(String)
    }

    let target: Target

    init(chatID: ChatID) {
        target = .chat(chatID)
    }

    init(draftID: String) {
        target = .draft(draftID)
    }

    /// The conversation on the Mac; nil for a draft.
    var chatID: ChatID? {
        if case .chat(let id) = target { id } else { nil }
    }

    /// The draft's id; nil for a conversation on the Mac.
    var draftID: String? {
        if case .draft(let id) = target { id } else { nil }
    }
}
