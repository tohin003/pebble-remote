import Foundation

/// The app's provisioning profile, read from `embedded.mobileprovision` in the app bundle: when this build stops
/// opening ("This build expires in N days") and whether it was signed with a free Apple ID (a Personal Team), whose
/// profiles last 7 days.
///
/// The file is a CMS (PKCS #7) signed blob whose content is a property list in XML; the reader takes the bytes from
/// `<?xml` to `</plist>` and parses them. It does not check the CMS signature: iOS already did before launching.
public struct ProvisioningProfile: Sendable, Hashable {
    /// "iOS Team Provisioning Profile: com.example.app"
    public var name: String?
    public var appIDName: String?
    /// The team as the person sees it in Xcode ("Jane Doe (Personal Team)").
    public var teamName: String?
    public var teamIdentifier: String?
    public var uuid: String?
    public var creationDate: Date?
    public var expirationDate: Date
    /// `get-task-allow`: a development build that Xcode can debug.
    public var allowsDebugging: Bool
    public var provisionsAllDevices: Bool
    public var provisionedDeviceCount: Int

    public enum ReadError: Error, Sendable, Hashable {
        /// No property list inside the blob.
        case noPropertyList
        /// The property list is not a profile (no expiration date).
        case notAProfile
    }

    public init(
        name: String? = nil, appIDName: String? = nil, teamName: String? = nil, teamIdentifier: String? = nil,
        uuid: String? = nil, creationDate: Date? = nil, expirationDate: Date, allowsDebugging: Bool = false,
        provisionsAllDevices: Bool = false, provisionedDeviceCount: Int = 0
    ) {
        self.name = name
        self.appIDName = appIDName
        self.teamName = teamName
        self.teamIdentifier = teamIdentifier
        self.uuid = uuid
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.allowsDebugging = allowsDebugging
        self.provisionsAllDevices = provisionsAllDevices
        self.provisionedDeviceCount = provisionedDeviceCount
    }

    /// Reads a profile from the bytes of an `embedded.mobileprovision` file.
    public init(data: Data) throws {
        guard let plist = Self.propertyListBytes(in: data) else { throw ReadError.noPropertyList }
        guard
            let object = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil),
            let dictionary = object as? [String: Any]
        else { throw ReadError.noPropertyList }
        guard let expiration = dictionary["ExpirationDate"] as? Date else { throw ReadError.notAProfile }
        let entitlements = dictionary["Entitlements"] as? [String: Any]
        self.init(
            name: dictionary["Name"] as? String,
            appIDName: dictionary["AppIDName"] as? String,
            teamName: dictionary["TeamName"] as? String,
            teamIdentifier: (dictionary["TeamIdentifier"] as? [String])?.first,
            uuid: dictionary["UUID"] as? String,
            creationDate: dictionary["CreationDate"] as? Date,
            expirationDate: expiration,
            allowsDebugging: entitlements?["get-task-allow"] as? Bool ?? false,
            provisionsAllDevices: dictionary["ProvisionsAllDevices"] as? Bool ?? false,
            provisionedDeviceCount: (dictionary["ProvisionedDevices"] as? [Any])?.count ?? 0)
    }

    /// The profile this app was installed with, or nil where there is none (the simulator, the Mac, an App Store
    /// build, or a file that cannot be read).
    public static func embedded(in bundle: Bundle = .main) -> ProvisioningProfile? {
        let candidates = [
            bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
            bundle.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile"),
        ]
        for case let url? in candidates {
            if let data = try? Data(contentsOf: url), let profile = try? ProvisioningProfile(data: data) {
                return profile
            }
        }
        return nil
    }

    /// How long the profile was made to last.
    public var lifespan: TimeInterval? {
        creationDate.map { expirationDate.timeIntervalSince($0) }
    }

    /// True for a profile that lasts at most a week: what Xcode makes for a free Apple ID (a Personal Team). Paid
    /// development, ad hoc and enterprise profiles last a year.
    public var looksLikeFreeProfile: Bool {
        guard let lifespan else { return false }
        return lifespan <= 7.5 * 86_400 && !provisionsAllDevices
    }

    public func isExpired(at now: Date = .now) -> Bool {
        now >= expirationDate
    }

    /// Time left before the build stops opening; zero once expired.
    public func timeLeft(at now: Date = .now) -> TimeInterval {
        max(0, expirationDate.timeIntervalSince(now))
    }

    /// Whole days left (rounded down): 6 days and 23 hours is 6. Zero on the last day and after it expired; show
    /// `expirationDate` itself for the exact moment.
    public func daysLeft(at now: Date = .now) -> Int {
        Int((timeLeft(at: now) / 86_400).rounded(.down))
    }

    /// The bytes from `<?xml` through `</plist>`, or nil.
    static func propertyListBytes(in data: Data) -> Data? {
        let start = Data("<?xml".utf8)
        let end = Data("</plist>".utf8)
        guard let startRange = data.range(of: start),
            let endRange = data.range(of: end, in: startRange.upperBound..<data.endIndex)
        else { return nil }
        return data.subdata(in: startRange.lowerBound..<endRange.upperBound)
    }
}
