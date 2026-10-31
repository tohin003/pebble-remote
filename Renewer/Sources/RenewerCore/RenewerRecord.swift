import Foundation

/// The kinds of notification the renewer posts, each at most once per end date.
public enum Notice: String, CaseIterable, Sendable {
    /// 1 day or less left and the iPhone can't be reached.
    case unreachable
    /// An automatic renewal failed for a reason the person can fix.
    case failed
    /// 1 day or less left and no build is recorded, so nothing can be renewed from the menu bar.
    case noBuild
}

/// The renewer's own memory (`renewer.json`, owner-only): Renew Automatically, the last result, the notices posted.
public struct RenewerRecord: Codable, Equatable, Sendable {
    public var autoRenew: Bool
    public var lastAttempt: Attempt?
    public var lastAutomaticFailure: Date?
    /// Automatic tries that failed in a row; each one doubles the rest before the next (RenewalPolicy.rest).
    public var automaticFailures: Int
    /// A renewal before this end date succeeded but left it unchanged (Xcode kept its cached profile).
    public var unmovedExpiry: Date?
    /// Notice kind → the end date it was posted for.
    public var notified: [String: Date]

    public struct Attempt: Codable, Equatable, Sendable {
        public var at: Date
        public var finishedAt: Date?
        public var automatic: Bool
        public var succeeded: Bool
        /// Why it didn't renew, in plain words (shown under "Couldn't renew ...").
        public var message: String?
        public var expiryBefore: Date?
        public var expiryAfter: Date?
        /// Nil when unknown (renew.sh's date couldn't be read).
        public var dateMoved: Bool?

        public init(
            at: Date, finishedAt: Date? = nil, automatic: Bool, succeeded: Bool, message: String? = nil,
            expiryBefore: Date? = nil, expiryAfter: Date? = nil, dateMoved: Bool? = nil
        ) {
            self.at = at
            self.finishedAt = finishedAt
            self.automatic = automatic
            self.succeeded = succeeded
            self.message = message
            self.expiryBefore = expiryBefore
            self.expiryAfter = expiryAfter
            self.dateMoved = dateMoved
        }
    }

    public init(
        autoRenew: Bool = true, lastAttempt: Attempt? = nil, lastAutomaticFailure: Date? = nil,
        automaticFailures: Int = 0, unmovedExpiry: Date? = nil, notified: [String: Date] = [:]
    ) {
        self.autoRenew = autoRenew
        self.lastAttempt = lastAttempt
        self.lastAutomaticFailure = lastAutomaticFailure
        self.automaticFailures = automaticFailures
        self.unmovedExpiry = unmovedExpiry
        self.notified = notified
    }

    enum CodingKeys: String, CodingKey {
        case autoRenew, lastAttempt, lastAutomaticFailure, automaticFailures, unmovedExpiry, notified
    }

    /// Missing keys take their defaults: Renew Automatically is on unless the person turned it off.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoRenew = try container.decodeIfPresent(Bool.self, forKey: .autoRenew) ?? true
        lastAttempt = try? container.decodeIfPresent(Attempt.self, forKey: .lastAttempt)
        lastAutomaticFailure = try? container.decodeIfPresent(Date.self, forKey: .lastAutomaticFailure)
        automaticFailures = (try? container.decodeIfPresent(Int.self, forKey: .automaticFailures)) ?? 0
        unmovedExpiry = try? container.decodeIfPresent(Date.self, forKey: .unmovedExpiry)
        notified = (try? container.decodeIfPresent([String: Date].self, forKey: .notified)) ?? [:]
    }

    public func wasNotified(_ notice: Notice, for expires: Date?) -> Bool {
        guard let expires, let posted = notified[notice.rawValue] else { return false }
        return RenewalPolicy.same(posted, expires)
    }

    public mutating func markNotified(_ notice: Notice, for expires: Date) {
        notified[notice.rawValue] = expires
    }

    public static func decode(_ data: Data) -> RenewerRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(RenewerRecord.self, from: data)) ?? RenewerRecord()
    }

    /// The saved record, or the defaults when there is none yet (or it can't be read).
    public static func load(from url: URL) -> RenewerRecord {
        guard let data = try? Data(contentsOf: url) else { return RenewerRecord() }
        return decode(data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
