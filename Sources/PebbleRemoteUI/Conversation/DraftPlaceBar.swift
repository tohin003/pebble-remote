import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Where a new conversation starts, at the top of its screen: a menu of Companion, the recent projects and the folder
/// the person chose, then "Connect a project". Choosing changes nothing on the Mac; the conversation starts there with
/// its first message. A folder no conversation uses yet says that Face ID comes then.
struct DraftPlaceBar: View {
    let draft: ConversationDraft
    @Binding var sheet: ConversationSheet?
    @Environment(RemoteStore.self) private var store

    var body: some View {
        VStack(spacing: PebbleSpace.s1) {
            Menu {
                Picker(AppCopy.Draft.whereLabel, selection: placeBinding) {
                    Label(AppCopy.Sidebar.companion, systemImage: PebbleSymbol.conversation)
                        .tag(String?.none)
                    ForEach(choices) { project in
                        Label(project.name, systemImage: PebbleSymbol.project)
                            .tag(Optional(project.path))
                    }
                }
                if store.bridgeOffers("new_chat") {
                    Button(AppCopy.Sidebar.connectProject, systemImage: "folder.badge.plus", action: connectProject)
                }
            } label: {
                Label(AppCopy.Draft.startsIn(placeName), systemImage: placeSymbol)
                    .font(PebbleFont.chip)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityLabel(AppCopy.Sidebar.newConversation(in: placeName))
            .accessibilityHint(AppCopy.Draft.whereHint)
            if isNewFolder {
                Text(AppCopy.Draft.newFolderNote)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, PebbleSpace.s2)
    }

    private var placeName: String { draft.placeName ?? AppCopy.Sidebar.companion }
    private var placeSymbol: String { draft.place == nil ? PebbleSymbol.conversation : PebbleSymbol.project }

    /// A folder chosen with "Connect a project" that no conversation uses yet.
    private var isNewFolder: Bool {
        guard let place = draft.place else { return false }
        return !store.isKnownProject(place.path)
    }

    /// The recent projects, and the chosen place when it isn't one of them.
    private var choices: [ProjectRef] {
        var list = store.recentProjects
        if let place = draft.place, !list.contains(where: { $0.path == place.path }) { list.append(place) }
        return list
    }

    /// The picker shows where the draft starts; a pick moves it (nothing reaches the Mac).
    private var placeBinding: Binding<String?> {
        Binding(
            get: { draft.place?.path },
            set: { path in store.move(draft, to: path.flatMap { wanted in choices.first { $0.path == wanted } }) })
    }

    private func connectProject() {
        sheet = .connectProject
    }
}
