import PebbleDesign
import PebbleRemoteKit

/// What "New Folder" allows in a folder of "Connect a project" (proposal v0.6), from what the screen knows: when the
/// button shows, whether a name can go on to Face ID, and what the alert says under its title.
struct NewFolderControls {
    /// The bridge offers `remote.folder_create`; an older bridge shows no button.
    var isOffered: Bool
    /// The folder's own listing is loaded: its path is where the new folder goes.
    var hasListing: Bool
    /// A folder is being chosen or made.
    var isBusy: Bool

    var showsButton: Bool { isOffered && hasListing }
    var buttonIsEnabled: Bool { showsButton && !isBusy }

    /// Why what is typed can't be a folder's name, in the bridge's words; nil when the Mac can take it. Create asks for
    /// Face ID, so it goes on only with a name the Mac can take (`NewFolderName`); tapped with another it asks for none,
    /// and the alert comes back with these words.
    func problem(typed: String) -> String? {
        NewFolderName.problem(in: typed)?.words
    }

    /// What the alert says under its title: why the last try didn't go through, or what is wrong with the name so far
    /// (nothing, while the field is empty), or where the folder goes and that it asks for Face ID.
    func message(typed: String, failure: String?, parent: String) -> String {
        if let failure { return failure }
        if let problem = NewFolderName.problem(in: typed), problem != .empty { return problem.words }
        return AppCopy.ConnectProject.newFolderMessage(in: parent)
    }
}
