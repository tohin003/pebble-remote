import PebbleProtocol
import PebbleRemoteKit

/// What a long press on a conversation in Chats offers (UX audit U-19; docs/parity/IA.md rule 3): the Mac sidebar row's
/// actions that the bridge offers, as the row's swipe actions offer them (Apple's guidance: the same actions in both),
/// and a new conversation in the row's project, as the Mac's project rows start one.
/// - Rename (`chat_rename`), the Mac's pencil.
/// - New conversation in the conversation's project (`new_chat`); none in Companion, where Chats' own button starts one.
/// - Stop (`cancel`) while its task works, as the swipe offers it then; otherwise Delete (`storage_trash_chat`), the
///   Mac's trash, which asks first in the Mac's words.
nonisolated enum ChatMenuItem: Hashable {
    case rename
    case newConversation(ProjectRef)
    case stop
    case delete

    static func items(for chat: ChatSummary, project: ProjectRef?, offers: (String) -> Bool) -> [ChatMenuItem] {
        var items: [ChatMenuItem] = []
        if offers("chat_rename") { items.append(.rename) }
        if let project, offers("new_chat") { items.append(.newConversation(project)) }
        if chat.status?.isLive == true {
            if offers("cancel") { items.append(.stop) }
        } else if offers("storage_trash_chat") {
            items.append(.delete)
        }
        return items
    }

    /// Stop and Delete end something, so the menu keeps them apart, after the others.
    var ends: Bool {
        switch self {
        case .stop, .delete: true
        case .rename, .newConversation: false
        }
    }
}
