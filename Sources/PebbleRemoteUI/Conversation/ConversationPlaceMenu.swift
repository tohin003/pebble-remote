import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The conversation's title menu, under which it says where it is (Companion or its project): Pebble's sidebar actions
/// from here, "New conversation in" this place, and "Connect a project".
struct ConversationPlaceMenu: View {
    let transcript: Transcript
    @Binding var sheet: ConversationSheet?
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if store.bridgeOffers("new_chat") {
            Button(AppCopy.Sidebar.newConversation(in: placeName), systemImage: "square.and.pencil", action: newHere)
            Button(AppCopy.Sidebar.connectProject, systemImage: "folder.badge.plus", action: connectProject)
        }
    }

    private var placeName: String { transcript.project ?? AppCopy.Sidebar.companion }

    /// The Mac's project row: a new conversation in this conversation's project (or in Companion).
    private func newHere() {
        let place = transcript.workspace.map { ProjectRef(path: $0, name: transcript.project ?? ProjectRef.folderName($0)) }
        router.push(draft: store.newDraft(in: place).id)
    }

    private func connectProject() {
        sheet = .connectProject
    }
}
