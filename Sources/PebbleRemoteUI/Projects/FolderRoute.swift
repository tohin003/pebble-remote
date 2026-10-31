import PebbleRemoteKit

/// A folder pushed in "Connect a project": its path on the Mac, or nil for the home folder.
struct FolderRoute: Hashable {
    let path: String?
    /// What is known of the folder before the Mac answers: a folder just made is empty, so it opens at once with
    /// "Connect this folder" ready.
    var initial: FolderListing? = nil
}
