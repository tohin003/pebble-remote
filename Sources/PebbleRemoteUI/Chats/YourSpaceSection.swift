import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's sidebar under YOUR SPACE: Companion, the projects as the Mac lists them (the conversations' folders, newest
/// first, at most five), then "Connect a project". Each place starts a new conversation there; nothing reaches the Mac
/// until its first message.
struct YourSpaceSection: View {
    /// Opens a new conversation in Companion (nil) or a project.
    let open: (ProjectRef?) -> Void
    let connectProject: () -> Void
    @Environment(RemoteStore.self) private var store

    var body: some View {
        Section(AppCopy.Sidebar.yourSpace) {
            PlaceButton(name: AppCopy.Sidebar.companion, systemImage: PebbleSymbol.conversation) { open(nil) }
            ForEach(store.recentProjects) { project in
                PlaceButton(name: project.name, systemImage: PebbleSymbol.project) { open(project) }
            }
            Button(AppCopy.Sidebar.connectProject, systemImage: "folder.badge.plus", action: connectProject)
                .accessibilityHint(AppCopy.Sidebar.connectProjectHint)
        }
    }
}
