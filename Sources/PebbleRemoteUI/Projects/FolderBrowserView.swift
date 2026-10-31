import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One folder of the Mac and its subfolders (`remote.folders`, proposal v0.5), starting at the home folder: a folder
/// opens its own subfolders, Back goes up to its parent, and "Connect this folder" ends it. Folder names only; the bridge
/// leaves out hidden folders and those Pebble protects. "New Folder" (proposal v0.6) makes a folder here on the Mac, with
/// Face ID, and opens it with "Connect this folder" ready.
struct FolderBrowserView: View {
    /// The folder's path on the Mac; nil for the home folder.
    let path: String?
    /// What connecting does here, from the sheet.
    let note: String?
    /// Why the last choice didn't go through, from the sheet.
    let failure: String?
    let isChoosing: Bool
    let connect: (ProjectRef) -> Void
    /// Opens a folder in the sheet: the one just made.
    let open: (FolderRoute) -> Void
    @Environment(RemoteStore.self) private var store
    @State private var listing: FolderListing?
    @State private var problem: String?
    @State private var isLoading = true
    // New Folder
    @State private var isNaming = false
    @State private var newName = ""
    @State private var isMaking = false
    @State private var makeFailure: String?
    @State private var madeCount = 0

    /// `initial` is what is known of the folder before the Mac answers (a folder just made is empty).
    init(
        path: String?, initial: FolderListing? = nil, note: String?, failure: String?, isChoosing: Bool,
        connect: @escaping (ProjectRef) -> Void, open: @escaping (FolderRoute) -> Void
    ) {
        self.path = path
        self.note = note
        self.failure = failure
        self.isChoosing = isChoosing
        self.connect = connect
        self.open = open
        _listing = State(initialValue: initial)
    }

    var body: some View {
        List {
            if let listing {
                ForEach(listing.folders) { folder in
                    NavigationLink(value: FolderRoute(path: folder.path)) {
                        FolderRow(folder: folder)
                    }
                }
            }
        }
        .overlay {
            FolderListingState(
                isLoading: isLoading && listing == nil, problem: listing == nil ? problem : nil,
                isEmpty: listing?.folders.isEmpty == true, retry: reload)
        }
        .navigationTitle(listing?.name ?? path.map(ProjectRef.folderName) ?? AppCopy.ConnectProject.chooseFolder)
        .toolbar {
            if controls.showsButton {
                ToolbarItem(placement: .primaryAction) {
                    Button(AppCopy.ConnectProject.newFolder, systemImage: "folder.badge.plus", action: beginNaming)
                        .disabled(!controls.buttonIsEnabled)
                        .accessibilityHint(AppCopy.ConnectProject.newFolderHint)
                }
            }
        }
        .newFolderAlert(
            isPresented: $isNaming, name: $newName,
            message: controls.message(typed: newName, failure: makeFailure, parent: listing?.name ?? ""),
            create: create, cancel: cancelNaming
        )
        .onChange(of: newName) { makeFailure = nil }
        .sensoryFeedback(.success, trigger: madeCount)
        .safeAreaBar(edge: .bottom) {
            ConnectFolderBar(listing: listing, note: note, failure: failure, isChoosing: isChoosing, connect: connect)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var controls: NewFolderControls {
        NewFolderControls(
            isOffered: store.bridgeOffers("remote.folder_create"), hasListing: listing != nil,
            isBusy: isChoosing || isMaking)
    }

    private func reload() {
        Task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            listing = try await store.folders(at: path)
            problem = nil
        } catch {
            problem = store.takeNotice() ?? AppCopy.Errors.generic
        }
    }

    private func beginNaming() {
        makeFailure = nil
        isNaming = true
    }

    private func cancelNaming() {
        newName = ""
        makeFailure = nil
    }

    /// Create: Face ID, then the folder on the Mac. A name the Mac can't take never gets as far as Face ID: the alert comes
    /// back with the name as typed, and says what is wrong.
    private func create() {
        guard let listing, !isMaking else { return }
        if let words = controls.problem(typed: newName) {
            makeFailure = words
            nameAgain()
            return
        }
        let name = newName
        isMaking = true
        makeFailure = nil
        Task {
            await make(name, in: listing)
            isMaking = false
        }
    }

    private func make(_ name: String, in parent: FolderListing) async {
        switch await store.makeFolder(named: name, in: parent.path) {
        case .made(let folder):
            newName = ""
            listing = (listing ?? parent).adding(folder)
            madeCount += 1
            FolderCreated.announce(folder.name)
            open(FolderRoute(path: folder.path, initial: parent.opening(folder)))
        case .refused(let words):
            makeFailure = words
            nameAgain()
        case .cancelled:
            break
        }
    }

    /// The alert again, with the name as typed and the reason under its title: once the one that Create dismissed has gone.
    private func nameAgain() {
        Task { isNaming = true }
    }
}
