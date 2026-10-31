import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A folder of the Mac in "Connect a project": its name, and "Git repository" when it holds `.git` (the bridge's
/// `is_project`), with a filled sage folder so repositories stand out.
struct FolderRow: View {
    let folder: FolderEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(folder.name)
                if folder.isProject {
                    Text(AppCopy.ConnectProject.gitRepository)
                        .font(PebbleFont.meta)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: folder.isProject ? "folder.fill" : PebbleSymbol.project)
                .foregroundStyle(folder.isProject ? PebbleColor.accent : PebbleColor.secondaryText)
        }
    }
}
