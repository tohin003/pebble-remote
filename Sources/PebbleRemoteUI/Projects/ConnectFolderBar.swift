import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The bottom of a folder in "Connect a project": "Connect this folder", with what connecting does here, or Pebble's
/// reason it can't be connected (the home folder), or why the last try didn't go through.
struct ConnectFolderBar: View {
    let listing: FolderListing?
    let note: String?
    let failure: String?
    let isChoosing: Bool
    let connect: (ProjectRef) -> Void

    var body: some View {
        VStack(spacing: PebbleSpace.s2) {
            if let failure {
                Text(failure)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.danger)
            } else if listing?.isHome == true {
                Text(AppCopy.ConnectProject.homeRefused)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            } else if let note {
                Text(note)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            Button(action: connectListed) {
                Label(AppCopy.ConnectProject.connectThisFolder, systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pebbleGlassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!canConnect)
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    /// A listed folder other than the home folder, which Pebble refuses.
    private var canConnect: Bool {
        guard let listing else { return false }
        return !listing.isHome && !isChoosing
    }

    private func connectListed() {
        guard canConnect, let listing else { return }
        connect(ProjectRef(folder: listing.path))
    }
}
