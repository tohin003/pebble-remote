import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The sheets of a conversation on the Mac: Terminal command, Read a web source and Connect a project. A project picked
/// for a conversation with messages starts a new conversation there and this one stays where it is; an empty
/// conversation moves there (App.vue `chooseProject`, `openProject`).
struct ConversationSheetView: View {
    let which: ConversationSheet
    let transcript: Transcript
    @Binding var sheet: ConversationSheet?
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        switch which {
        case .terminalCommand:
            TerminalCommandSheet(project: transcript.project, propose: propose, connectProject: connectProject)
        case .webSource:
            WebSourceSheet(readsOnSend: false, attach: attachURL)
        case .connectProject:
            ConnectProjectSheet(
                current: transcript.workspace,
                note: transcript.hasMessages ? AppCopy.Place.startsNewConversation : nil, choose: choose)
        }
    }

    private func propose(_ command: String, _ network: Bool) async -> Bool {
        let chat = transcript.chatID
        return await store.attempt { try await store.proposeTerminalCommand(command, network: network, in: chat) }
    }

    private func attachURL(_ address: String) async -> Bool {
        let chat = transcript.chatID
        return await store.attempt { try await store.attachURL(address, to: chat) }
    }

    private func connectProject() {
        sheet = .connectProject
    }

    private func choose(_ project: ProjectRef) async -> Bool {
        if transcript.hasMessages {
            router.push(draft: store.newDraft(in: project).id)
            return true
        }
        let chat = transcript.chatID
        let moved: Bool = await store.attempt { try await store.setWorkspace(chat, to: project) }
        if moved { ProjectConnected.announce() }
        return moved
    }
}
