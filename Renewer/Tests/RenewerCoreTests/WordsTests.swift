import Foundation
import Testing
@testable import RenewerCore

struct TimeWordsTests {
    @Test func spansRoundDownToWholeUnits() {
        #expect(TimeWords.span(5.7 * 86_400) == "5 days")
        #expect(TimeWords.span(1.9 * 86_400) == "1 day")
        #expect(TimeWords.span(23.5 * 3_600) == "23 hours")
        #expect(TimeWords.span(1.5 * 3_600) == "1 hour")
        #expect(TimeWords.span(45 * 60 + 30) == "45 minutes")
        #expect(TimeWords.span(20) == "1 minute")
        #expect(TimeWords.span(-5) == "1 minute")
    }

    @Test func momentsReadAsDays() {
        let now = Fixture.thursday
        func when(_ date: Date) -> String {
            TimeWords.when(date, now: now, calendar: Fixture.calendar, locale: Fixture.locale)
        }
        #expect(when(now) == "today at 09:14")
        #expect(when(Fixture.expires) == "tomorrow at 02:07")
        #expect(when(Fixture.date("2026-11-04T17:40:00Z")) == "yesterday at 23:10")
        #expect(when(Fixture.date("2026-11-02T03:44:00Z")) == "Mon 2 Nov at 09:14")
    }
}

struct MenuWordsTests {
    let policy = RenewalPolicy(timing: .beforeExpiry)
    let installed = ExpiryInfo(expires: Fixture.expires, source: .installedBuild)

    func menu(_ facts: MenuFacts) -> MenuWords {
        Words.menu(facts, calendar: Fixture.calendar, locale: Fixture.locale)
    }

    func facts(
        now: Date = Fixture.saturday, expiry: ExpiryInfo?, build: Bool = true, auto: Bool = true,
        unmoved: Date? = nil, decision: Decision? = nil, renewing: Bool = false,
        attempt: RenewerRecord.Attempt? = nil, installedAt: Date? = nil
    ) -> MenuFacts {
        let situation = Situation(
            now: now, expires: expiry?.expires, hasBuild: build, autoRenew: auto, unmovedExpiry: unmoved)
        return MenuFacts(
            now: now, expiry: expiry, stage: policy.stage(situation), decision: decision, renewing: renewing,
            waitsForExpiry: policy.waitsForExpiry(situation), lastAttempt: attempt, installedAt: installedAt)
    }

    @Test func daysLeftAndWhenItRenews() {
        let words = menu(facts(expiry: installed))
        #expect(words.bar == "5 days")
        #expect(words.expiry == "Expires Fri 6 Nov at 02:07")
        #expect(words.note == nil)
        #expect(words.plan == "Renews in 4 days")
        #expect(words.result == ["Not renewed yet"])
    }

    @Test func whileRenewing() {
        let words = menu(facts(expiry: installed, renewing: true))
        #expect(words.bar == "Renewing…")
        #expect(words.plan == "Renewing now. This takes a few minutes.")
    }

    @Test func afterTheEndDate() {
        let words = menu(facts(now: Fixture.date("2026-11-06T03:44:00Z"), expiry: installed))
        #expect(words.bar == "Expired")
        #expect(words.expiry == "Expired today at 02:07")
        #expect(words.plan == "Renews at the next check")
    }

    @Test func beforeRenewShHasInstalled() {
        let words = menu(facts(expiry: ExpiryInfo(expires: Fixture.expires, source: .xcodeProfile), build: false))
        #expect(words.note == "Date from Xcode's newest profile")
        #expect(words.plan == "To renew from here, install once with scripts/renew.sh")
        let none = menu(facts(expiry: nil, build: false))
        #expect(none.bar == "No date")
        #expect(none.expiry == "No end date found")
        #expect(none.plan == "Install Pebble Remote once with scripts/renew.sh")
    }

    @Test func theMenuSaysWhenRenewingWaitsForTheEndDate() {
        #expect(menu(facts(expiry: installed, unmoved: Fixture.expires)).plan == "Renews right after it expires")
        #expect(menu(facts(now: Fixture.thursday, expiry: installed, unmoved: Fixture.expires)).plan
            == "Renews right after it expires")
        #expect(menu(facts(expiry: installed, auto: false)).plan == "Renews only when you choose Renew Now")
    }

    @Test func dueButWaiting() {
        let now = Fixture.thursday
        #expect(menu(facts(now: now, expiry: installed, decision: .waitForHold)).plan
            == "Renews when Pebble's timed work is done")
        #expect(menu(facts(now: now, expiry: installed, decision: .waitForPhone(notify: false))).plan
            == "Renews when your iPhone is reachable")
        #expect(menu(facts(now: now, expiry: installed, decision: .severalPhones)).plan
            == "Renews when only your iPhone is connected")
        let resting = MenuFacts(
            now: now, expiry: installed, stage: .resting(until: Fixture.date("2026-11-05T04:09:00Z")))
        #expect(menu(resting).plan == "Tries again at 09:39")
    }

    @Test func theLastResult() {
        let started = Fixture.date("2026-10-31T03:38:00Z")
        let finished = Fixture.saturday
        let renewed = RenewerRecord.Attempt(
            at: started, finishedAt: finished, automatic: true, succeeded: true, dateMoved: true)
        #expect(menu(facts(expiry: installed, attempt: renewed)).result == ["Renewed today at 09:14"])

        var unmoved = renewed
        unmoved.dateMoved = false
        #expect(menu(facts(expiry: installed, attempt: unmoved)).result
            == ["Renewed today at 09:14; the end date didn't move"])

        let failed = RenewerRecord.Attempt(
            at: started, finishedAt: finished, automatic: false, succeeded: false, message: Copy.unreachable)
        #expect(menu(facts(expiry: installed, attempt: failed)).result
            == ["Couldn't renew today at 09:14", "Your iPhone wasn't reachable. Connect it, then choose Renew Now."])

        // renew.sh run by hand afterwards is the newer news.
        let later = Fixture.date("2026-10-31T04:00:00Z")
        #expect(menu(facts(expiry: installed, attempt: failed, installedAt: later)).result
            == ["Installed today at 09:30"])
        // Its own install (written while the renewal ran) doesn't hide the renewal.
        #expect(menu(facts(expiry: installed, attempt: renewed, installedAt: finished.addingTimeInterval(-2))).result
            == ["Renewed today at 09:14"])
    }
}
