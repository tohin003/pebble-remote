import Foundation

/// What `scripts/renew.sh` records in `state.json` after a successful install: which build is on the iPhone, and its
/// signing profile's dates. Only the dates and the app id's bundle part come from the profile; nothing else of it
/// (no certificate, device list or team name) is kept. Unknown keys are ignored and every key may be missing.
public struct InstallState: Codable, Equatable, Sendable {
    public var version: Int?
    public var installedAt: Date?
    /// The commit that was built (a full hash).
    public var commit: String?
    /// False when renew.sh built a working tree with changes; the renewer still builds only `commit`.
    public var treeWasClean: Bool?
    /// "worktree" (`--commit`, a clean worktree) or "tree" (the tree renew.sh lives in).
    public var builtFrom: String?
    /// The devicectl identifier it was installed on.
    public var device: String?
    public var bundleId: String?
    public var profileCreated: Date?
    public var profileExpires: Date?

    public init(
        version: Int? = 1, installedAt: Date? = nil, commit: String? = nil, treeWasClean: Bool? = nil,
        builtFrom: String? = nil, device: String? = nil, bundleId: String? = nil, profileCreated: Date? = nil,
        profileExpires: Date? = nil
    ) {
        self.version = version
        self.installedAt = installedAt
        self.commit = commit
        self.treeWasClean = treeWasClean
        self.builtFrom = builtFrom
        self.device = device
        self.bundleId = bundleId
        self.profileCreated = profileCreated
        self.profileExpires = profileExpires
    }

    /// The commit to rebuild, only when it is a plain git hash (it becomes an argument to renew.sh).
    public var buildCommit: String? {
        guard let commit, (7...64).contains(commit.count), commit.allSatisfy(\.isHexDigit) else { return nil }
        return commit.lowercased()
    }

    public var shortCommit: String? { buildCommit.map { String($0.prefix(7)) } }

    /// The recorded device, only when it looks like a devicectl identifier or UDID.
    public var buildDevice: String? {
        guard let device, DeviceList.isPlainIdentifier(device) else { return nil }
        return device
    }

    public static func decode(_ data: Data) throws -> InstallState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InstallState.self, from: data)
    }

    /// The state file's contents, or nil when it is missing or unreadable.
    public static func load(from url: URL) -> InstallState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }
}

/// Where the end date shown in the menu came from.
public enum ExpirySource: String, Equatable, Sendable {
    /// state.json: the build renew.sh last installed.
    case installedBuild
    /// Until renew.sh has installed once: the newest Xcode profile for the app's bundle id.
    case xcodeProfile
}

public struct ExpiryInfo: Equatable, Sendable {
    public var expires: Date
    public var source: ExpirySource

    public init(expires: Date, source: ExpirySource) {
        self.expires = expires
        self.source = source
    }
}

public enum Expiry {
    /// The build last installed wins; Xcode's newest profile is only the fallback before renew.sh has run once.
    public static func resolve(state: InstallState?, profile: ProfileSummary?) -> ExpiryInfo? {
        if let expires = state?.profileExpires { return ExpiryInfo(expires: expires, source: .installedBuild) }
        if let profile { return ExpiryInfo(expires: profile.expires, source: .xcodeProfile) }
        return nil
    }
}
