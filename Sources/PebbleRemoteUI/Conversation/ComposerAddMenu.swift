import PebbleDesign
import PebbleRemoteKit
import PhotosUI
import SwiftUI

/// The composer's "+" (Pebble's "Add context"): Terminal command, Attach a file, Read a web source and Connect a
/// project, in Pebble's order and words. Each shows only when the bridge offers what it needs. "Attach a file" offers the
/// iPhone's two places for one: the photo library and Files. While the conversation's task works its items wait, as
/// the Mac's "+" does (Pebble takes attachments only with a new task); the menu still opens and says so.
struct ComposerAddMenu: View {
    /// Which items show.
    struct Offers: Equatable {
        var terminalCommand = false
        var attachFile = false
        var webSource = false
        var connectProject = false

        var isEmpty: Bool { !(terminalCommand || attachFile || webSource || connectProject) }

        /// What the connected bridge offers (before its welcome, everything shows, as every control here).
        static func offered(by store: RemoteStore) -> Offers {
            Offers(
                terminalCommand: store.bridgeOffers("terminal_propose"), attachFile: store.bridgeOffers("attach_bytes"),
                webSource: store.bridgeOffers("attach_url"), connectProject: store.bridgeOffers("new_chat"))
        }
    }

    let offers: Offers
    let isWorking: Bool
    @Binding var sheet: ConversationSheet?
    /// Keeps a photo or file (its bytes, name and preview) for the next message; returns whether it was taken.
    let attach: (Data, String, Data?) async -> Bool
    @Environment(RemoteStore.self) private var store
    @State private var isPickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var isPickingFile = false
    @State private var isAttaching = false

    var body: some View {
        Menu(AppCopy.AddContext.title, systemImage: "plus") {
            // While the task works the menu still opens (the UX audit's U-09): its items show greyed under a header
            // that says when they come back, rather than a dimmed "+" that does nothing. One shape either way (only the
            // header's words and the greying change), so a task starting or ending doesn't rebuild an open menu (U-53).
            Section(isWorking ? AppCopy.AddContext.whileWorkingHint : AppCopy.AddContext.title) {
                items
                    .disabled(isWorking)
            }
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .opacity(isAttaching ? 0 : 1)
        .overlay {
            if isAttaching {
                ProgressView()
            }
        }
        .disabled(isAttaching)
        .accessibilityHint(isWorking ? AppCopy.AddContext.whileWorkingHint : "")
        .photosPicker(isPresented: $isPickingPhoto, selection: $photo, matching: .images)
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.item], onCompletion: filePicked)
        .onChange(of: photo) { _, picked in
            guard let picked else { return }
            Task { await send(picked) }
        }
    }

    /// Pebble's four, in its order; each only when the bridge offers what it needs.
    @ViewBuilder
    private var items: some View {
        if offers.terminalCommand {
            Button(AppCopy.AddContext.terminalCommand, systemImage: "terminal", action: openTerminalCommand)
        }
        if offers.attachFile {
            Menu(AppCopy.AddContext.attachFile, systemImage: "paperclip") {
                Button(AppCopy.AddContext.photoLibrary, systemImage: "photo.on.rectangle", action: pickPhoto)
                Button(AppCopy.AddContext.files, systemImage: "folder", action: pickFile)
            }
        }
        if offers.webSource {
            Button(AppCopy.AddContext.readWebSource, systemImage: "globe", action: openWebSource)
        }
        if offers.connectProject {
            Button(AppCopy.AddContext.connectProject, systemImage: "folder.badge.plus", action: openConnectProject)
        }
    }

    private func openTerminalCommand() { sheet = .terminalCommand }
    private func openWebSource() { sheet = .webSource }
    private func openConnectProject() { sheet = .connectProject }
    private func pickPhoto() { isPickingPhoto = true }
    private func pickFile() { isPickingFile = true }

    /// A photo from the library goes as a JPEG (PhotoPayload), with a small preview for its chip.
    private func send(_ picked: PhotosPickerItem) async {
        isAttaching = true
        defer {
            isAttaching = false
            photo = nil
        }
        guard let data = try? await picked.loadTransferable(type: Data.self), let payload = PhotoPayload(imageData: data)
        else {
            store.notice = PersonFacingError(message: AppCopy.Attach.unreadable)
            return
        }
        _ = await attach(payload.data, payload.filename, payload.preview)
    }

    /// A file from Files goes as it is, read off the main thread.
    private func filePicked(_ result: Result<URL, any Error>) {
        guard case .success(let url) = result else { return }  // cancelled, or the picker said why itself
        isAttaching = true
        Task {
            defer { isAttaching = false }
            do {
                let file = try await Task.detached { try PickedFile.read(url) }.value
                _ = await attach(file.data, file.name, file.preview)
            } catch {
                store.notice = (error as? PersonFacingError) ?? PersonFacingError(message: AppCopy.AddContext.unreadableFile)
            }
        }
    }
}
