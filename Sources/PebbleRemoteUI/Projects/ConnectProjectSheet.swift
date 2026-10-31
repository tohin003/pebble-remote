import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// "Connect a project": the projects Pebble knows, newest first, then the folders of the Mac (`remote.folders`,
/// proposal v0.5) ending with "Connect this folder", where "New Folder" makes a folder on the Mac (proposal v0.6). A
/// bridge without folder browsing gets the projects and a line saying where to connect another folder. What choosing
/// does belongs to whoever opened the sheet: a new conversation there, where a new conversation starts, or an empty
/// conversation moving there.
struct ConnectProjectSheet: View {
    /// Where the conversation is now, marked in the list.
    var current: String? = nil
    /// What choosing does here, when the person should know before choosing.
    var note: String? = nil
    /// Acts on the choice; returns whether it went through (the sheet then closes).
    let choose: (ProjectRef) async -> Bool
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var path: [FolderRoute] = []
    @State private var isChoosing = false
    @State private var failure: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let note {
                    Section {
                        Text(note)
                            .foregroundStyle(.secondary)
                    }
                }
                if !store.projects.isEmpty {
                    Section(AppCopy.ConnectProject.recentProjects) {
                        ForEach(store.projects) { project in
                            ProjectChoiceRow(project: project, isCurrent: project.path == current) { pick(project) }
                        }
                    }
                }
                Section {
                    if canBrowse {
                        NavigationLink(value: FolderRoute(path: nil)) {
                            Label(AppCopy.ConnectProject.chooseFolder, systemImage: PebbleSymbol.project)
                        }
                        .accessibilityHint(AppCopy.ConnectProject.chooseFolderHint)
                    }
                } footer: {
                    Text(footerNote)
                }
                if let failure {
                    Section {
                        Text(failure)
                            .foregroundStyle(PebbleColor.danger)
                    }
                }
            }
            .disabled(isChoosing)
            .navigationTitle(AppCopy.ConnectProject.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: FolderRoute.self) { route in
                FolderBrowserView(
                    path: route.path, initial: route.initial, note: note, failure: failure, isChoosing: isChoosing,
                    connect: pick, open: open)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel, action: close)
                }
            }
        }
    }

    /// The bridge lists the Mac's folders (proposal v0.5).
    private var canBrowse: Bool { store.bridgeOffers("remote.folders") }

    /// What the footer says: what connecting asks for, and where to make a new folder when the bridge can.
    private var footerNote: String {
        guard canBrowse else { return AppCopy.ConnectProject.onMacOnly }
        let makes = store.bridgeOffers("remote.folder_create")
        return makes
            ? AppCopy.ConnectProject.newFolderNote + " " + AppCopy.ConnectProject.canMakeFolders
            : AppCopy.ConnectProject.newFolderNote
    }

    private func close() {
        dismiss()
    }

    /// Opens a folder in the sheet's stack: the one "New Folder" just made.
    private func open(_ route: FolderRoute) {
        path.append(route)
    }

    private func pick(_ project: ProjectRef) {
        guard !isChoosing else { return }
        isChoosing = true
        failure = nil
        Task {
            if await choose(project) {
                dismiss()
            } else {
                failure = store.takeNotice()
            }
            isChoosing = false
        }
    }
}
