import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The rename alert for a conversation: a field with the current title, Save and Cancel.
struct RenameChatAlert: ViewModifier {
    let transcript: Transcript
    @Binding var isPresented: Bool
    @Environment(RemoteStore.self) private var store
    @State private var title = ""

    func body(content: Content) -> some View {
        content
            .alert(AppCopy.Chats.renameTitle, isPresented: $isPresented) {
                TextField(AppCopy.Chats.renameField, text: $title)
                Button(AppCopy.Chats.save, action: save)
                Button(AppCopy.Chats.cancel, role: .cancel) {}
            }
            .onChange(of: isPresented) { _, presented in
                if presented { title = transcript.title }
            }
    }

    private func save() {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != transcript.title else { return }
        let chat = transcript.chatID
        Task { await store.attempt { try await store.rename(chat: chat, to: newTitle) } }
    }
}
