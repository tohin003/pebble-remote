import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The menu of a long press on a conversation in Chats (`ChatMenuItem`): Rename and a new conversation in its project
/// first, then Stop or Delete apart from them. Delete has the destructive role; it asks first (Chats' dialog).
struct ChatContextMenu: View {
    let items: [ChatMenuItem]
    let act: (ChatMenuItem) -> Void

    var body: some View {
        Section {
            ForEach(items.filter { !$0.ends }, id: \.self) { item in
                ChatMenuButton(item: item, act: act)
            }
        }
        Section {
            ForEach(items.filter(\.ends), id: \.self) { item in
                ChatMenuButton(item: item, act: act)
            }
        }
    }
}

/// One item of the menu, in Pebble's words, with its symbol.
private struct ChatMenuButton: View {
    let item: ChatMenuItem
    let act: (ChatMenuItem) -> Void

    var body: some View {
        switch item {
        case .rename:
            Button(AppCopy.ChatMenu.rename, systemImage: "pencil", action: perform)
        case .newConversation(let project):
            Button(AppCopy.ChatMenu.newConversation(in: project.name), systemImage: "square.and.pencil", action: perform)
        case .stop:
            Button(AppCopy.ChatMenu.stop, systemImage: "stop.fill", action: perform)
        case .delete:
            Button(AppCopy.ChatMenu.delete, systemImage: "trash", role: .destructive, action: perform)
        }
    }

    private func perform() {
        act(item)
    }
}
