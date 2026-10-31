import Foundation

/// Lengths and moments in plain words, in the person's own date and clock settings.
public enum TimeWords {
    /// "5 days", "1 day", "17 hours", "45 minutes": whole units, rounded down.
    public static func span(_ interval: TimeInterval) -> String {
        let seconds = max(0, interval)
        let days = Int(seconds / 86_400)
        if days >= 1 { return Copy.days(days) }
        let hours = Int(seconds / 3_600)
        if hours >= 1 { return Copy.hours(hours) }
        return Copy.minutes(max(1, Int(seconds / 60)))
    }

    /// "09:14" (or "9:14 AM", as the Mac's clock is set).
    public static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        formatter(template: "jjmm", calendar: calendar, locale: locale).string(from: date)
    }

    /// "Fri 6 Nov" (or "Fri, 6 Nov", as the Mac's region is set).
    public static func day(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        formatter(template: "EEEdMMM", calendar: calendar, locale: locale).string(from: date)
    }

    /// "today at 09:14", "tomorrow at 02:07", "yesterday at 23:10", "Fri 6 Nov at 02:07".
    public static func when(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let clock = time(date, calendar: calendar, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) { return Copy.today(clock) }
        if let next = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: next) {
            return Copy.tomorrow(clock)
        }
        if let previous = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: previous) {
            return Copy.yesterday(clock)
        }
        return Copy.onDay(day(date, calendar: calendar, locale: locale), clock)
    }

    static func formatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}

/// Everything the menu's words depend on.
public struct MenuFacts: Sendable {
    public var now: Date
    public var expiry: ExpiryInfo?
    public var stage: Stage
    public var decision: Decision?
    public var renewing: Bool
    public var waitsForExpiry: Bool
    public var lastAttempt: RenewerRecord.Attempt?
    public var installedAt: Date?

    public init(
        now: Date, expiry: ExpiryInfo?, stage: Stage, decision: Decision? = nil, renewing: Bool = false,
        waitsForExpiry: Bool = false, lastAttempt: RenewerRecord.Attempt? = nil, installedAt: Date? = nil
    ) {
        self.now = now
        self.expiry = expiry
        self.stage = stage
        self.decision = decision
        self.renewing = renewing
        self.waitsForExpiry = waitsForExpiry
        self.lastAttempt = lastAttempt
        self.installedAt = installedAt
    }
}

/// The words on the bar and in the menu.
public struct MenuWords: Equatable, Sendable {
    /// The bar: the days left ("5 days"), "Expired", "Renewing…".
    public var bar: String
    /// "Expires Fri 6 Nov at 02:07".
    public var expiry: String
    /// Only while the date is Xcode's newest profile rather than the build renew.sh installed.
    public var note: String?
    /// What happens next: "Renews in 4 days".
    public var plan: String
    /// The last result: "Renewed today at 09:14", or "Couldn't renew ..." and why.
    public var result: [String]

    public init(bar: String, expiry: String, note: String?, plan: String, result: [String]) {
        self.bar = bar
        self.expiry = expiry
        self.note = note
        self.plan = plan
        self.result = result
    }
}

public enum Words {
    public static func menu(_ facts: MenuFacts, calendar: Calendar = .current, locale: Locale = .current) -> MenuWords {
        MenuWords(
            bar: bar(facts),
            expiry: expiry(facts, calendar: calendar, locale: locale),
            note: facts.expiry?.source == .xcodeProfile ? Copy.fromXcode : nil,
            plan: plan(facts, calendar: calendar, locale: locale),
            result: result(facts, calendar: calendar, locale: locale))
    }

    static func bar(_ facts: MenuFacts) -> String {
        if facts.renewing { return Copy.barRenewing }
        guard let expires = facts.expiry?.expires else { return Copy.barNoDate }
        let left = expires.timeIntervalSince(facts.now)
        return left <= 0 ? Copy.barExpired : TimeWords.span(left)
    }

    static func expiry(_ facts: MenuFacts, calendar: Calendar, locale: Locale) -> String {
        guard let expires = facts.expiry?.expires else { return Copy.noEndDate }
        let when = TimeWords.when(expires, now: facts.now, calendar: calendar, locale: locale)
        return expires > facts.now ? Copy.expires(when) : Copy.expired(when)
    }

    static func plan(_ facts: MenuFacts, calendar: Calendar, locale: Locale) -> String {
        if facts.renewing { return Copy.planRenewing }
        switch facts.stage {
        case .unknownDate:
            return Copy.planNoDate
        case .noBuild:
            return Copy.planNoBuild
        case .off:
            return Copy.planOff
        case .early(let renewsAt):
            if facts.waitsForExpiry { return Copy.planAfterExpiry }
            return Copy.planIn(TimeWords.span(renewsAt.timeIntervalSince(facts.now)))
        case .lastDay:
            if case .some(.waitForPhone) = facts.decision { return Copy.planWaitPhone }
            return Copy.planAfterExpiry
        case .resting(let until):
            return Copy.planRetry(TimeWords.time(until, calendar: calendar, locale: locale))
        case .due:
            switch facts.decision {
            case .some(.waitForHold): return Copy.planWaitHold
            case .some(.holdUnknown): return Copy.planHoldUnknown
            case .some(.waitForPhone): return Copy.planWaitPhone
            case .some(.severalPhones): return Copy.planSeveral
            default: return Copy.planDue
            }
        }
    }

    static func result(_ facts: MenuFacts, calendar: Calendar, locale: Locale) -> [String] {
        if let attempt = facts.lastAttempt {
            let finished = attempt.finishedAt ?? attempt.at
            // renew.sh run by hand since then wins: its install is the newer news.
            let installedSince = facts.installedAt.map { $0 > finished.addingTimeInterval(5) } ?? false
            if !installedSince {
                let when = TimeWords.when(finished, now: facts.now, calendar: calendar, locale: locale)
                if attempt.succeeded {
                    return [attempt.dateMoved == false ? Copy.renewedUnmoved(when) : Copy.renewed(when)]
                }
                return [Copy.couldNotRenew(when), attempt.message ?? Copy.seeLog]
            }
        }
        if let installed = facts.installedAt {
            return [Copy.installed(TimeWords.when(installed, now: facts.now, calendar: calendar, locale: locale))]
        }
        return [Copy.notRenewedYet]
    }
}
