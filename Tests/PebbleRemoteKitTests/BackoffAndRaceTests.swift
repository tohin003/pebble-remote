import Foundation
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane B: the reconnect schedule and Happy-Eyeballs racing.
@Suite("Lane B: backoff")
struct BackoffTests {
    @Test func doublesFromHalfASecondToThirtySeconds() {
        let backoff = Backoff()
        let steps = (1...9).map { backoff.delay(attempt: $0, unit: 0.5).inSeconds }
        #expect(steps == [0.5, 1, 2, 4, 8, 16, 30, 30, 30])
        #expect(backoff.delay(attempt: 1000, unit: 0.5).inSeconds == 30)
        #expect(backoff.delay(attempt: 0, unit: 0.5).inSeconds == 0.5)
    }

    @Test func jitterStaysWithinTwentyPercentAndNeverAboveTheCap() {
        let backoff = Backoff()
        #expect(abs(backoff.delay(attempt: 1, unit: 0).inSeconds - 0.4) < 1e-9)
        #expect(abs(backoff.delay(attempt: 1, unit: 1).inSeconds - 0.6) < 1e-9)
        #expect(abs(backoff.delay(attempt: 7, unit: 0).inSeconds - 24) < 1e-9)
        #expect(backoff.delay(attempt: 7, unit: 1).inSeconds == 30)
        for attempt in 1...12 {
            let delay = backoff.delay(attempt: attempt).inSeconds
            let step = backoff.step(attempt: attempt).inSeconds
            #expect(delay >= step * 0.8 - 1e-9 && delay <= min(30, step * 1.2) + 1e-9)
        }
    }
}

@Suite("Lane B: endpoint race")
struct EndpointRaceTests {
    static let lan = Endpoint(host: "192.168.1.20", port: 47800)
    static let lanName = Endpoint(host: "studio.local", port: 47800)
    static let tailnet = Endpoint(host: "studio.tail1.ts.net", port: 47800)
    static let tailnetIP = Endpoint(host: "100.101.102.103", port: 47800)

    /// When each endpoint's attempt started, after the race began.
    final class Starts: Sendable {
        let origin = ContinuousClock.now
        let values = Mutex<[Endpoint: Duration]>([:])
        func mark(_ endpoint: Endpoint) { values.withLock { $0[endpoint] = ContinuousClock.now - origin } }
        subscript(_ endpoint: Endpoint) -> Duration? { values.withLock { $0[endpoint] } }
    }

    struct Unreachable: Error {}

    @Test func wavesPutLANFirstAndDropDuplicates() {
        let (first, later) = EndpointRace.waves([Self.tailnet, Self.lan, Self.tailnetIP, Self.lan, Self.lanName])
        #expect(first == [Self.lan, Self.lanName])
        #expect(later == [Self.tailnet, Self.tailnetIP])
        let (onlyFirst, none) = EndpointRace.waves([Self.tailnet])
        #expect(onlyFirst == [Self.tailnet] && none.isEmpty)
    }

    @Test func lanWinsWithinItsHeadStartAndTheOthersNeverStart() async throws {
        let starts = Starts()
        let won = try await EndpointRace.run(
            [Self.tailnet, Self.lan], delay: .milliseconds(400),
            attempt: { endpoint in
                starts.mark(endpoint)
                if endpoint == Self.lan { try await Task.sleep(for: .milliseconds(30)) }
                return endpoint.host
            }, discard: { _ in })
        #expect(won.endpoint == Self.lan)
        #expect(starts[Self.tailnet] == nil)
    }

    @Test func othersStartAfterTheDelayWhenLANIsSlow() async throws {
        let starts = Starts()
        let won = try await EndpointRace.run(
            [Self.lan, Self.tailnet], delay: .milliseconds(150),
            attempt: { endpoint in
                starts.mark(endpoint)
                if endpoint == Self.lan { try await Task.sleep(for: .seconds(30)) }
                return endpoint.host
            }, discard: { _ in })
        #expect(won.endpoint == Self.tailnet)
        let tailnetStart = try #require(starts[Self.tailnet])
        #expect(tailnetStart >= .milliseconds(145))
    }

    @Test func othersStartAtOnceWhenEveryLANAttemptFails() async throws {
        let starts = Starts()
        let won = try await EndpointRace.run(
            [Self.lan, Self.lanName, Self.tailnet], delay: .seconds(5),
            attempt: { endpoint in
                starts.mark(endpoint)
                if endpoint.routeKind == .lan { throw Unreachable() }
                return endpoint.host
            }, discard: { _ in })
        #expect(won.endpoint == Self.tailnet)
        #expect(try #require(starts[Self.tailnet]) < .seconds(2))
    }

    @Test func everyFailureIsReported() async {
        do {
            _ = try await EndpointRace.run(
                [Self.lan, Self.tailnet], delay: .milliseconds(20),
                attempt: { (endpoint: Endpoint) -> String in throw Unreachable() }, discard: { _ in })
            Issue.record("expected a failure")
        } catch let failure as EndpointRace.AllFailed {
            #expect(Set(failure.failures.map(\.endpoint)) == [Self.lan, Self.tailnet])
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func aSecondSuccessIsDiscarded() async throws {
        let discarded = Mutex<[String]>([])
        let won = try await EndpointRace.run(
            [Self.lan, Self.lanName], delay: .milliseconds(150),
            attempt: { endpoint in
                if endpoint == Self.lanName { try? await Task.sleep(for: .milliseconds(40)) }  // ignores cancellation
                return endpoint.host
            }, discard: { value in discarded.withLock { $0.append(value) } })
        #expect(won.endpoint == Self.lan)
        #expect(discarded.withLock { $0 } == [Self.lanName.host])
    }
}
