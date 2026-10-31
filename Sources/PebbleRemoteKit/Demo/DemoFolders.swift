import Foundation
import PebbleProtocol

/// The demo Mac's folders, for "Connect a project" (`remote.folders`, proposal v0.5) and "New Folder"
/// (`remote.folder_create`, proposal v0.6): a small home folder holding the demo's projects, one project no conversation
/// uses yet (`pebble-ios`), and the folders the person makes while trying the demo. Answers in the bridge's shape: folder
/// names only, never files; nothing hidden. A folder made here counts as known to the phone for ten minutes (the demo's
/// clock), so connecting it needs no second Face ID, as the bridge says.
struct DemoFolders {
    static let home = "/Users/you"
    /// A folder no demo conversation uses yet.
    static let newProject = "/Users/you/Projects/pebble-ios"

    /// Every folder under the home folder when the demo starts, and whether it holds `.git`.
    static let seeded: [String: Bool] = [
        "/Users/you/Desktop": false,
        "/Users/you/Documents": false,
        "/Users/you/Documents/Notes": false,
        "/Users/you/Documents/Writing": false,
        "/Users/you/Downloads": false,
        "/Users/you/Music": false,
        "/Users/you/Pictures": false,
        "/Users/you/Projects": false,
        "/Users/you/Projects/pebble-docs": true,
        "/Users/you/Projects/pebble-ios": true,
        "/Users/you/Projects/pebble-site": true,
        "/Users/you/Projects/pebble-web": true,
        "/Users/you/Projects/sketches": false,
        "/Users/you/Projects/sketches/garden-planner": true,
    ]

    /// The folders made in the demo, with when. Never a Git repository: each is empty.
    private var made: [String: Date] = [:]

    /// Every folder under the home folder now, and whether it holds `.git`.
    private var tree: [String: Bool] {
        Self.seeded.merging(made.mapValues { _ in false }) { seeded, _ in seeded }
    }

    /// A folder the demo Mac has, the home folder included.
    func contains(_ path: String) -> Bool { path == Self.home || tree[path] != nil }

    /// A folder made here in the last ten minutes (`RemoteStore.madeFolderMemory`), as the bridge counts it: known to
    /// this phone, so the unlock is enough to connect it.
    func wasMadeRecently(_ path: String, at now: Date) -> Bool {
        guard let when = made[path] else { return false }
        return now.timeIntervalSince(when) <= RemoteStore.madeFolderMemory
    }

    /// `remote.folders {path?}`: the subfolders of `path` (the home folder's when nil), sorted by name.
    func listing(_ path: String?) throws -> JSONValue {
        let folder = path ?? Self.home
        try checkInsideHome(folder)
        guard contains(folder) else { throw Self.refusal(Self.missing) }
        let everything = tree
        let children = everything.keys.filter { ($0 as NSString).deletingLastPathComponent == folder }
            .sorted { ProjectRef.folderName($0).localizedStandardCompare(ProjectRef.folderName($1)) == .orderedAscending }
        let parent: JSONValue = folder == Self.home ? .null : .string((folder as NSString).deletingLastPathComponent)
        return [
            "home": .string(Self.home), "path": .string(folder), "parent": parent,
            "folders": .array(
                children.map { child in
                    [
                        "name": .string(ProjectRef.folderName(child)), "path": .string(child),
                        "is_project": .bool(everything[child] ?? false),
                    ]
                }),
        ]
    }

    /// `remote.folder_create {parent, name}`: one empty folder in `parent`, answered as the listing shows an entry. The
    /// same rules as the bridge: a name that is trimmed and then 1 to 255 bytes with no `/` or `:`, no control character
    /// and no leading dot; a parent inside the home folder; a name not already there (the Mac ignores case).
    mutating func create(_ params: JSONValue, at now: Date) throws -> JSONValue {
        guard let parent = params["parent"]?.string, let typed = params["name"]?.string else {
            throw Self.refusal(Self.unreadableRequest, code: BridgeErrorCode.badRequest)
        }
        let name = NewFolderName.trimmed(typed)
        if let problem = NewFolderName.problem(in: name) {
            throw Self.refusal(problem.words, code: BridgeErrorCode.badRequest)
        }
        try checkInsideHome(parent)
        guard contains(parent) else { throw Self.refusal(Self.missing) }
        let path = parent + "/" + name
        guard !tree.keys.contains(where: { $0.compare(path, options: .caseInsensitive) == .orderedSame }) else {
            throw Self.refusal(Self.exists)
        }
        made[path] = now
        return ["path": .string(path), "name": .string(name), "is_project": false]
    }

    // MARK: The bridge's words

    private static let outside = "Pebble Remote shows folders inside your home folder only."
    private static let missing = "That folder isn't on your Mac anymore."
    private static let exists = "A folder with that name is already there."
    private static let unreadableRequest =
        "Pebble couldn't read that request. Update Pebble Remote if this keeps happening."

    private static func refusal(_ words: String, code: BridgeErrorCode? = nil) -> RemoteCallError {
        .refused(PersonFacingError(message: words, code: code?.rawValue))
    }

    /// A path inside the home folder, without a `..`.
    private func checkInsideHome(_ folder: String) throws {
        guard folder == Self.home || folder.hasPrefix(Self.home + "/"), !folder.split(separator: "/").contains("..") else {
            throw Self.refusal(Self.outside, code: .notAllowed)
        }
    }
}

extension DemoClient {
    /// `remote.folder_create`: one empty folder on the demo Mac. It writes to the Mac, so it needs Face ID, which always
    /// agrees in the demo.
    func makeFolder(_ params: JSONValue, proven: Bool) throws -> JSONValue {
        guard proven else {
            throw refusal("Confirm with Face ID to do this.", code: BridgeErrorCode.proofRequired.rawValue)
        }
        return try folders.create(params, at: now())
    }
}
