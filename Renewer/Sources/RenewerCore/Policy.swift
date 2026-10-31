import Foundation

public enum RenewalTiming: String, Equatable, Sendable {
    /// Renew once 1 day or less is left.
    case beforeExpiry
    /// Renew right after the end date: for when renewing early keeps Xcode's cached profile and the date doesn't move.
    case afterExpiry
}

/// THE SWITCH (the brief's item 5). Check once with the real iPhone: a few days before the end date, choose Renew Now.
/// - If the end date in the menu moves (to 7 days after the renewal), keep `.beforeExpiry`.
/// - If it doesn't (Xcode reused its cached profile, which is still valid), set `.afterExpiry`. The item then renews
///   right after the end date, and the menu says "Renews right after it expires".
/// Either way, a renewal that leaves the date where it was makes the item wait for that end date before it renews
/// again, so a wrong setting costs one extra build, never a build every 30 minutes.
public enum RenewalSwitch {
    public static let timing: RenewalTiming = .beforeExpiry
}

/// `scripts/hold-status.sh`'s answer: exit 0 no HOLD, 3 a Pebble HOLD; anything else means it couldn't tell.
public enum HoldState: String, Equatable, Sendable {
    case clear
    case active
    case unknown

    public init(exitStatus: Int32) {
        switch exitStatus {
        case 0: self = .clear
        case 3: self = .active
        default: self = .unknown
        }
    }
}

/// What the renewer knows before it asks anything: the date, the build, the switches, the last tries.
public struct Situation: Equatable, Sendable {
    public var now: Date
    public var expires: Date?
    /// A commit is recorded (state.json), so there is something to rebuild.
    public var hasBuild: Bool
    public var autoRenew: Bool
    /// A renewal before this end date left it unchanged, so the next one waits for it.
    public var unmovedExpiry: Date?
    public var lastAutomaticFailure: Date?
    /// Automatic tries that failed in a row since the last success.
    public var automaticFailures: Int

    public init(
        now: Date, expires: Date?, hasBuild: Bool, autoRenew: Bool, unmovedExpiry: Date? = nil,
        lastAutomaticFailure: Date? = nil, automaticFailures: Int = 0
    ) {
        self.now = now
        self.expires = expires
        self.hasBuild = hasBuild
        self.autoRenew = autoRenew
        self.unmovedExpiry = unmovedExpiry
        self.lastAutomaticFailure = lastAutomaticFailure
        self.automaticFailures = automaticFailures
    }
}

/// Where the current profile stands, before any check runs.
public enum Stage: Equatable, Sendable {
    case unknownDate
    case noBuild
    case off
    /// More than a day left (or, waiting for the end date, not yet in the last day).
    case early(renewsAt: Date)
    /// 1 day or less left, but renewing waits for the end date: the iPhone is still checked, to warn in time.
    case lastDay(renewsAt: Date)
    case due
    /// Due, but the last automatic try failed a moment ago.
    case resting(until: Date)
}

/// What to do after the checks.
public enum Decision: Equatable, Sendable {
    case wait
    case waitForHold
    case holdUnknown
    case waitForPhone(notify: Bool)
    case severalPhones
    case renew(device: String)
}

public struct RenewalPolicy: Equatable, Sendable {
    public var timing: RenewalTiming
    /// "1 day or less is left".
    public var window: TimeInterval
    /// Checks run at login, on wake and this often.
    public var checkEvery: TimeInterval
    /// After an automatic try fails, the next waits this long (the next check, in practice), doubling with each
    /// further failure in a row up to `longestRest`.
    public var retryAfterFailure: TimeInterval
    public var longestRest: TimeInterval
    /// The iPhone must stay unreachable this long before the one notification: right after login or wake, devicectl
    /// may not have found it yet.
    public var unreachableGrace: TimeInterval
    public var startDelay: TimeInterval
    public var wakeDelay: TimeInterval
    /// Checks land this long after an edge (the window's start, the end date), never on it.
    public var edgeDelay: TimeInterval

    public init(
        timing: RenewalTiming = RenewalSwitch.timing, window: TimeInterval = 86_400, checkEvery: TimeInterval = 1_800,
        retryAfterFailure: TimeInterval = 1_500, longestRest: TimeInterval = 21_600,
        unreachableGrace: TimeInterval = 1_200, startDelay: TimeInterval = 60, wakeDelay: TimeInterval = 60,
        edgeDelay: TimeInterval = 30
    ) {
        self.timing = timing
        self.window = window
        self.checkEvery = checkEvery
        self.retryAfterFailure = retryAfterFailure
        self.longestRest = longestRest
        self.unreachableGrace = unreachableGrace
        self.startDelay = startDelay
        self.wakeDelay = wakeDelay
        self.edgeDelay = edgeDelay
    }

    /// True when renewing waits for the end date: the switch says so, or renewing early already left this date as it
    /// was.
    public func waitsForExpiry(_ situation: Situation) -> Bool {
        if timing == .afterExpiry { return true }
        guard let expires = situation.expires, let unmoved = situation.unmovedExpiry else { return false }
        return Self.same(expires, unmoved)
    }

    public func isLastDay(now: Date, expires: Date) -> Bool {
        now >= expires.addingTimeInterval(-window)
    }

    public func stage(_ situation: Situation) -> Stage {
        guard let expires = situation.expires else { return .unknownDate }
        guard situation.hasBuild else { return .noBuild }
        guard situation.autoRenew else { return .off }
        let renewsAt = waitsForExpiry(situation) ? expires : expires.addingTimeInterval(-window)
        if situation.now < renewsAt {
            return isLastDay(now: situation.now, expires: expires) ? .lastDay(renewsAt: renewsAt) : .early(renewsAt: renewsAt)
        }
        if let failed = situation.lastAutomaticFailure {
            let until = failed.addingTimeInterval(rest(afterFailures: situation.automaticFailures))
            if situation.now < until { return .resting(until: until) }
        }
        return .due
    }

    /// 25 minutes after one failed automatic try, twice as long after each further one in a row, at most 6 hours: a
    /// lasting problem (signing, a broken build) never means a heavy build every half hour.
    public func rest(afterFailures count: Int) -> TimeInterval {
        let doublings = min(max(count - 1, 0), 10)
        return min(retryAfterFailure * Double(1 << doublings), longestRest)
    }

    /// The decision once the checks for this stage have run: `hold` from hold-status.sh (only when due), `phone` from
    /// devicectl (when due and no HOLD, or in the last day), `unreachableFor` how long the iPhone has been out of
    /// reach, `alreadyNotified` whether this end date's one notification went out.
    public func decide(
        stage: Stage, hold: HoldState?, phone: Reachability?, unreachableFor: TimeInterval?, alreadyNotified: Bool
    ) -> Decision {
        let notify = !alreadyNotified && (unreachableFor ?? 0) >= unreachableGrace
        switch stage {
        case .due:
            switch hold {
            case .active?: return .waitForHold
            case .clear?: break
            case .unknown?, nil: return .holdUnknown
            }
            switch phone {
            case .some(.reachable(let device, _)): return .renew(device: device.identifier)
            case .some(.several): return .severalPhones
            default: return .waitForPhone(notify: notify)
            }
        case .lastDay:
            switch phone {
            case .some(.unreachable), .some(.unreadable): return .waitForPhone(notify: notify)
            default: return .wait
            }
        default:
            return .wait
        }
    }

    /// When to check next: in `checkEvery`, or just after the next edge (the start of the last day, the end date, the
    /// end of a rest) when that comes sooner.
    public func nextCheck(after now: Date, expires: Date?, stage: Stage) -> Date {
        var next = now.addingTimeInterval(checkEvery)
        var edges: [Date] = []
        if let expires { edges += [expires.addingTimeInterval(-window), expires] }
        if case .resting(let until) = stage { edges.append(until) }
        for edge in edges {
            let moment = edge.addingTimeInterval(edgeDelay)
            if moment > now, moment < next { next = moment }
        }
        return next
    }

    /// Whether a renewal moved the end date. Nil when either date is unknown.
    public static func dateMoved(before: Date?, after: Date?) -> Bool? {
        guard let before, let after else { return nil }
        return after.timeIntervalSince(before) > 60
    }

    /// Two end dates are the same profile's when within a second (they pass through second-precision files).
    public static func same(_ first: Date, _ second: Date) -> Bool {
        abs(first.timeIntervalSince(second)) < 1
    }
}
