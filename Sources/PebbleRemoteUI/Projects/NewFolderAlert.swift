import PebbleDesign
import SwiftUI

/// The "New Folder" alert of the folder browser, in the Files app's words: a name field, Cancel and Create. What it says
/// under its title comes from `NewFolderControls`. Create is always there to tap: an alert's buttons are fixed when it
/// appears, so a Create that waited for a good name might never wake up. A name the Mac can't take brings the alert back
/// saying why (`FolderBrowserView.create`).
struct NewFolderAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var name: String
    let message: String
    let create: () -> Void
    let cancel: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(AppCopy.ConnectProject.newFolder, isPresented: $isPresented) {
                TextField(AppCopy.ConnectProject.folderNamePrompt, text: $name)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button(AppCopy.ConnectProject.createFolder, action: create)
                Button(AppCopy.Common.cancel, role: .cancel, action: cancel)
            } message: {
                Text(message)
            }
    }
}

extension View {
    /// The "New Folder" alert: `name` is what the person types; Create runs `create`, Cancel runs `cancel`.
    func newFolderAlert(
        isPresented: Binding<Bool>, name: Binding<String>, message: String, create: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) -> some View {
        modifier(NewFolderAlert(isPresented: isPresented, name: name, message: message, create: create, cancel: cancel))
    }
}
