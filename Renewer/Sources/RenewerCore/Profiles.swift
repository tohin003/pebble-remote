import Foundation

/// The only things the renewer takes from a provisioning profile: its dates and the bundle id it signs.
public struct ProfileSummary: Equatable, Sendable {
    public var created: Date
    public var expires: Date
    /// The app id without its team prefix ("io.github.tohin003.PebbleRemote").
    public var bundleId: String

    public init(created: Date, expires: Date, bundleId: String) {
        self.created = created
        self.expires = expires
        self.bundleId = bundleId
    }
}

/// Reads Xcode's provisioning profiles for the fallback date (before renew.sh has recorded an install).
///
/// A profile is a signed envelope around a property list. The list is stored as plain text inside it, so it is read
/// straight from the file's bytes: no Keychain, no signature check, no `security` tool. Of that list only
/// `CreationDate`, `ExpirationDate` and the entitlements' `application-identifier` are read; certificates, device
/// lists and team names are never kept or logged. Profiles are never changed or removed.
public enum ProvisioningProfiles {
    public static func summary(of data: Data) -> ProfileSummary? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.upperBound..<data.endIndex)
        else { return nil }
        let text = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let list = (try? PropertyListSerialization.propertyList(from: text, options: [], format: nil))
                as? [String: Any],
              let created = list["CreationDate"] as? Date,
              let expires = list["ExpirationDate"] as? Date,
              let entitlements = list["Entitlements"] as? [String: Any],
              let appID = entitlements["application-identifier"] as? String,
              let dot = appID.firstIndex(of: ".")
        else { return nil }
        let bundleId = String(appID[appID.index(after: dot)...])
        guard !bundleId.isEmpty else { return nil }
        return ProfileSummary(created: created, expires: expires, bundleId: bundleId)
    }

    /// The newest profile (by creation, then expiry) whose app id is exactly this bundle id. A UI-test runner's
    /// profile ("…PebbleRemoteUIAudit.xctrunner") or a wildcard one never counts.
    public static func newest(for bundleId: String, in folders: [URL]) -> ProfileSummary? {
        let manager = FileManager.default
        var best: ProfileSummary?
        for folder in folders {
            guard let names = try? manager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else {
                continue
            }
            for name in names where name.hasSuffix(".mobileprovision") {
                guard let data = try? Data(contentsOf: folder.appending(path: name)),
                      let summary = summary(of: data),
                      summary.bundleId == bundleId
                else { continue }
                if let current = best, (current.created, current.expires) >= (summary.created, summary.expires) {
                    continue
                }
                best = summary
            }
        }
        return best
    }
}
