import PebbleDesign
import PebbleRemoteKit

extension RemoteStore {
    /// Pebble's pose for what it is doing now, shared by the Pebble tab's companion and the tab's glyph: asleep while
    /// Pebble isn't open on the Mac, the first live run's status while one works or waits, otherwise at rest.
    var pebblePose: PebbleAvatar.Pose {
        if !isPebbleOpen { return .sleepy }
        if let run = liveRuns.first { return PebbleAvatar.Pose(status: run.status) }
        return .idle
    }

    /// Pebble is open on the Mac, as far as the phone knows.
    var isPebbleOpen: Bool {
        (mac?.pebbleRunning ?? true) && (bridge?.pebbleRunning ?? true)
    }

    /// One of the Mac companion's switches (Pebble's Settings › Appearance: "pointer", "reactions"). It is on until
    /// Pebble says otherwise, and Pebble's own Reduce Motion turns it off, as on the Mac.
    func companionSwitch(_ key: String) -> Bool {
        guard let settings else { return true }
        return !settings.reducedMotion && settings.companion[key]?.bool != false
    }
}
