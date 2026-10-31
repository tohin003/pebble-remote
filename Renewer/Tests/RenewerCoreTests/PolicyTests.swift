import Foundation
import Testing
@testable import RenewerCore

struct PolicyTests {
    let policy = RenewalPolicy(timing: .beforeExpiry)
    let expires = Fixture.expires

    func situation(
        hoursLeft: Double, build: Bool = true, auto: Bool = true, unmoved: Date? = nil, failedAt: Date? = nil,
        failures: Int = 0
    ) -> Situation {
        Situation(
            now: expires.addingTimeInterval(-hoursLeft * 3_600), expires: expires, hasBuild: build, autoRenew: auto,
            unmovedExpiry: unmoved, lastAutomaticFailure: failedAt, automaticFailures: failures)
    }

    @Test func renewsOnce1DayOrLessIsLeft() {
        #expect(policy.stage(Situation(now: expires, expires: nil, hasBuild: true, autoRenew: true)) == .unknownDate)
        #expect(policy.stage(situation(hoursLeft: 10, build: false)) == .noBuild)
        #expect(policy.stage(situation(hoursLeft: 10, auto: false)) == .off)
        #expect(policy.stage(situation(hoursLeft: 100)) == .early(renewsAt: expires.addingTimeInterval(-86_400)))
        #expect(policy.stage(situation(hoursLeft: 24.5)) == .early(renewsAt: expires.addingTimeInterval(-86_400)))
        #expect(policy.stage(situation(hoursLeft: 24)) == .due)
        #expect(policy.stage(situation(hoursLeft: 3)) == .due)
        #expect(policy.stage(situation(hoursLeft: -2)) == .due)
    }

    @Test func afterExpiryTimingWaitsForTheEndDate() {
        let later = RenewalPolicy(timing: .afterExpiry)
        #expect(later.stage(situation(hoursLeft: 100)) == .early(renewsAt: expires))
        #expect(later.stage(situation(hoursLeft: 10)) == .lastDay(renewsAt: expires))
        #expect(later.stage(situation(hoursLeft: -0.01)) == .due)
    }

    @Test func aDateThatDidNotMoveWaitsForTheEndDate() {
        #expect(policy.stage(situation(hoursLeft: 10, unmoved: expires)) == .lastDay(renewsAt: expires))
        #expect(policy.waitsForExpiry(situation(hoursLeft: 10, unmoved: expires)))
        #expect(policy.stage(situation(hoursLeft: -1, unmoved: expires)) == .due)
        // An older profile's unmoved date changes nothing for this one.
        let older = expires.addingTimeInterval(-7 * 86_400)
        #expect(policy.stage(situation(hoursLeft: 10, unmoved: older)) == .due)
    }

    @Test func restsLongerAfterEachFailureInARow() {
        #expect(policy.rest(afterFailures: 0) == 1_500)
        #expect(policy.rest(afterFailures: 1) == 1_500)
        #expect(policy.rest(afterFailures: 2) == 3_000)
        #expect(policy.rest(afterFailures: 3) == 6_000)
        #expect(policy.rest(afterFailures: 9) == 21_600)
        #expect(policy.rest(afterFailures: 400) == 21_600)

        let now = expires.addingTimeInterval(-3 * 3_600)
        let recent = now.addingTimeInterval(-600)
        #expect(policy.stage(situation(hoursLeft: 3, failedAt: recent, failures: 1))
            == .resting(until: recent.addingTimeInterval(1_500)))
        let older = now.addingTimeInterval(-1_600)
        #expect(policy.stage(situation(hoursLeft: 3, failedAt: older, failures: 1)) == .due)
        #expect(policy.stage(situation(hoursLeft: 3, failedAt: older, failures: 2))
            == .resting(until: older.addingTimeInterval(3_000)))
    }

    @Test func decisions() {
        let phone = Fixture.iPhone()
        let reachable = Reachability.reachable(phone, .cable)
        func decide(
            _ stage: Stage, _ hold: HoldState?, _ found: Reachability?, away: TimeInterval? = nil, notified: Bool = false
        ) -> Decision {
            policy.decide(stage: stage, hold: hold, phone: found, unreachableFor: away, alreadyNotified: notified)
        }
        #expect(decide(.due, .active, nil) == .waitForHold)
        #expect(decide(.due, .unknown, nil) == .holdUnknown)
        #expect(decide(.due, nil, reachable) == .holdUnknown, "never renews without asking hold-status.sh")
        #expect(decide(.due, .clear, reachable) == .renew(device: phone.identifier))
        #expect(decide(.due, .clear, .unreachable(knownPhone: true), away: 0) == .waitForPhone(notify: false))
        #expect(decide(.due, .clear, .unreachable(knownPhone: true), away: 1_200) == .waitForPhone(notify: true))
        #expect(decide(.due, .clear, .unreadable, away: 5_000, notified: true) == .waitForPhone(notify: false))
        #expect(decide(.due, .clear, .several([phone, phone])) == .severalPhones)
        #expect(decide(.lastDay(renewsAt: expires), nil, .unreachable(knownPhone: true), away: 2_000)
            == .waitForPhone(notify: true))
        #expect(decide(.lastDay(renewsAt: expires), nil, reachable) == .wait)
        #expect(decide(.early(renewsAt: expires), .clear, reachable) == .wait)
        #expect(decide(.off, .clear, reachable) == .wait)
        #expect(decide(.resting(until: expires), .clear, reachable) == .wait)
    }

    @Test func checksLandJustAfterAnEdge() {
        let early = expires.addingTimeInterval(-3 * 86_400)
        #expect(policy.nextCheck(after: early, expires: expires, stage: .early(renewsAt: expires))
            == early.addingTimeInterval(1_800))
        let beforeWindow = expires.addingTimeInterval(-86_400 - 600)
        #expect(policy.nextCheck(after: beforeWindow, expires: expires, stage: .early(renewsAt: expires))
            == expires.addingTimeInterval(-86_400 + 30))
        let beforeEnd = expires.addingTimeInterval(-60)
        #expect(policy.nextCheck(after: beforeEnd, expires: expires, stage: .lastDay(renewsAt: expires))
            == expires.addingTimeInterval(30))
        #expect(policy.nextCheck(after: early, expires: expires, stage: .resting(until: early.addingTimeInterval(300)))
            == early.addingTimeInterval(330))
        #expect(policy.nextCheck(after: early, expires: nil, stage: .unknownDate) == early.addingTimeInterval(1_800))
    }

    @Test func whetherTheDateMoved() {
        #expect(RenewalPolicy.dateMoved(before: expires, after: expires.addingTimeInterval(7 * 86_400)) == true)
        #expect(RenewalPolicy.dateMoved(before: expires, after: expires) == false)
        #expect(RenewalPolicy.dateMoved(before: nil, after: expires) == nil)
        #expect(RenewalPolicy.same(expires, expires.addingTimeInterval(0.4)))
    }

    @Test func holdStatusExitCodes() {
        #expect(HoldState(exitStatus: 0) == .clear)
        #expect(HoldState(exitStatus: 3) == .active)
        #expect(HoldState(exitStatus: 127) == .unknown)
    }

    @Test func theSwitchIsTheDefault() {
        #expect(RenewalPolicy().timing == RenewalSwitch.timing)
    }
}
