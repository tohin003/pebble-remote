import PebbleRemoteKit

extension FolderListing {
    /// This listing with `folder` among its folders, in its place by name: what the Mac lists once the folder is there. A
    /// folder that is listed already stays as it is.
    func adding(_ folder: FolderEntry) -> FolderListing {
        guard !folders.contains(where: { $0.path == folder.path }) else { return self }
        var listing = self
        listing.folders.append(folder)
        listing.folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return listing
    }

    /// The listing of a folder just made inside this one: nothing is in it yet.
    func opening(_ made: FolderEntry) -> FolderListing {
        FolderListing(home: home, path: made.path, parent: path, folders: [])
    }
}
