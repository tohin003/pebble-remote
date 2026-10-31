import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

/// UX audit U-23 (lane W): a paused run reports Pebble's active seconds for the whole run, as Pebble does, so a resumed
/// run counts on from them ("Reading 54 s" never becomes "4 s" after Resume). The demo used to report two seconds and
/// three more.
@MainActor
@Test func aPausedDemoRunReportsItsActiveSecondsSoResumeCountsOn() async throws {
    let clock = ResumeTestClock(Fixture.t0)
    let client = DemoClient(pace: 0, autoplay: false, now: { clock.now })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.start()
    #expect(await eventually { store.liveRuns.contains { $0.id == DemoData.loginRun && $0.state == .running } })

    clock.advance(54)
    try await store.pause(chat: DemoData.loginChat)
    #expect(await eventually { store.liveRuns.first { $0.id == DemoData.loginRun }?.state == .paused })
    let paused = await client.sent.last { $0.name == "run" && $0.data["state"]?.string == "paused" }
    // The 2 s Pebble had counted, the 40 s the run had been live when the demo opened, and the 54 s since.
    #expect(paused?.data["elapsed"]?.double == 96)
}

private final class ResumeTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    var now: Date { lock.withLock { date } }

    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

/// The re-check's U-58: Details › Activity said "Worked for 2 s" a minute into a run. Pebble's run_activity counts a
/// live run's time on from its last update (run_activity.py `_elapsed`); the demo now does too, in the reply and in its
/// work view's header.
@MainActor
@Test func aLiveDemoRunsActivityReportsTheTimeItHasRunSoFar() async throws {
    let clock = ResumeTestClock(Fixture.t0)
    let client = DemoClient(pace: 0, autoplay: false, now: { clock.now })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.start()
    #expect(await eventually { store.liveRuns.contains { $0.id == DemoData.loginRun && $0.state == .running } })

    clock.advance(54)
    let reply = try await client.call("run_activity", ["run_id": .string(DemoData.loginRun), "after": 0])
    // The 2 s Pebble had counted, the 40 s the run had been live when the demo opened, and the 54 s since.
    #expect(reply["elapsed"]?.double == 96)
    clock.advance(10)
    let later = try await client.call("run_activity", ["run_id": .string(DemoData.loginRun), "after": 0])
    #expect(later["elapsed"]?.double == 106)
}
