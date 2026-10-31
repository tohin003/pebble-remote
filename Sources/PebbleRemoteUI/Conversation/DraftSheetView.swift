import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The sheets of a new conversation: Terminal command (which makes the conversation, as the command and its card are
/// its first content), Read a web source (kept for the first message) and Connect a project (where it starts).
struct DraftSheetView: View {
    let which: ConversationSheet
    let draft: ConversationDraft
    @Binding var sheet: ConversationSheet?
    @Environment(RemoteStore.self) private var store

    var body: some View {
        switch which {
        case .terminalCommand:
            TerminalCommandSheet(project: draft.placeName, propose: propose, connectProject: connectProject)
        case .webSource:
            WebSourceSheet(readsOnSend: true, attach: attachURL)
        case .connectProject:
            ConnectProjectSheet(current: draft.place?.path, choose: choose)
        }
    }

    private func propose(_ command: String, _ network: Bool) async -> Bool {
        let made: ChatID? = await store.attempt {
            try await store.proposeTerminalCommand(command, network: network, from: draft)
        }
        return made != nil
    }

    private func attachURL(_ address: String) async -> Bool {
        await store.attempt { try store.attachURL(address, to: draft) }
    }

    private func connectProject() {
        sheet = .connectProject
    }

    private func choose(_ project: ProjectRef) async -> Bool {
        store.move(draft, to: project)
        return true
    }
}
