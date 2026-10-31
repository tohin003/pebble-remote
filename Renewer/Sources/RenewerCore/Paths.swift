import Foundation

/// Where the renewer keeps its files.
///
/// The support folder is shared with `scripts/renew.sh`, which writes `state.json` there after every successful
/// install and keeps the clean worktree for `--commit` in it. Both read the same `PEBBLE_REMOTE_RENEWER_DIR` override,
/// so they always agree. Nothing here lives in `/tmp`, which a restart wipes.
public struct RenewerPaths: Equatable, Sendable {
    /// `~/Library/Application Support/PebbleRemoteRenewer`, owner-only (0700).
    public var supportFolder: URL
    /// `~/Library/Logs/PebbleRemoteRenewer.log`, rotated to `.log.1`.
    public var logFile: URL
    /// Xcode's provisioning profile folders, newest layout first. Read only, never changed.
    public var profileFolders: [URL]

    public init(supportFolder: URL, logFile: URL, profileFolders: [URL]) {
        self.supportFolder = supportFolder
        self.logFile = logFile
        self.profileFolders = profileFolders
    }

    /// Written by renew.sh after a successful install: the build on the iPhone and its profile's dates.
    public var stateFile: URL { supportFolder.appending(path: "state.json") }
    /// The renewer's own memory: Renew Automatically, the last result, the notices already posted.
    public var recordFile: URL { supportFolder.appending(path: "renewer.json") }
    /// Held for the life of the menu-bar app, so a second copy quits.
    public var lockFile: URL { supportFolder.appending(path: "renewer.lock") }
    /// The clean worktree renew.sh builds `--commit` in.
    public var worktree: URL { supportFolder.appending(path: "worktree", directoryHint: .isDirectory) }

    public static let supportFolderVariable = "PEBBLE_REMOTE_RENEWER_DIR"

    public static func standard(home: URL, environment: [String: String] = [:]) -> RenewerPaths {
        let library = home.appending(path: "Library", directoryHint: .isDirectory)
        let support: URL
        if let custom = environment[supportFolderVariable], !custom.isEmpty {
            support = URL(filePath: custom, directoryHint: .isDirectory)
        } else {
            support = library.appending(path: "Application Support/PebbleRemoteRenewer", directoryHint: .isDirectory)
        }
        return RenewerPaths(
            supportFolder: support,
            logFile: library.appending(path: "Logs/PebbleRemoteRenewer.log"),
            profileFolders: [
                library.appending(path: "Developer/Xcode/UserData/Provisioning Profiles", directoryHint: .isDirectory),
                library.appending(path: "MobileDevice/Provisioning Profiles", directoryHint: .isDirectory),
            ])
    }
}

/// Files only this Mac user can read: folders 0700, files 0600, replaced in one step so a reader never sees half.
public enum OwnerOnlyFile {
    public static func makeFolder(_ url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path(percentEncoded: false))
    }

    public static func write(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try makeFolder(folder)
        let temporary = folder.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
        let temporaryPath = temporary.path(percentEncoded: false)
        guard FileManager.default.createFile(
            atPath: temporaryPath, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        if rename(temporaryPath, url.path(percentEncoded: false)) != 0 {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public static func modificationDate(of url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return attributes?[.modificationDate] as? Date
    }
}
