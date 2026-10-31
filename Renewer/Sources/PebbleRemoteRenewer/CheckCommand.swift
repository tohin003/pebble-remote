import Foundation
import RenewerCore

/// `PebbleRemoteRenewer --check`: prints what the item sees and would do right now, then exits. It renews nothing and
/// writes nothing; it runs hold-status.sh and `xcrun devicectl list devices`, which only read.
@MainActor
enum CheckCommand {
    static func run(_ configuration: AppConfiguration) async -> Int32 {
        let paths = configuration.paths
        let policy = configuration.policy
        let now = Date()
        let state = InstallState.load(from: paths.stateFile)
        let profile = state?.profileExpires == nil
            ? ProvisioningProfiles.newest(for: configuration.bundleId, in: paths.profileFolders) : nil
        let record = RenewerRecord.load(from: paths.recordFile)
        let expiry = Expiry.resolve(state: state, profile: profile)
        let situation = Situation(
            now: now, expires: expiry?.expires, hasBuild: state?.buildCommit != nil, autoRenew: record.autoRenew,
            unmovedExpiry: record.unmovedExpiry, lastAutomaticFailure: record.lastAutomaticFailure,
            automaticFailures: record.automaticFailures)
        let stage = policy.stage(situation)
        let probes = Probes(configuration: configuration, log: nil)
        let hold = await probes.hold()
        let phone = await probes.phone(preferring: state?.buildDevice)
        // As if the iPhone had been out of reach long enough, to show whether the one notification would go out.
        let decision = policy.decide(
            stage: stage, hold: hold, phone: phone, unreachableFor: policy.unreachableGrace,
            alreadyNotified: record.wasNotified(.unreachable, for: expiry?.expires))
        let words = Words.menu(MenuFacts(
            now: now, expiry: expiry, stage: stage, decision: decision,
            waitsForExpiry: policy.waitsForExpiry(situation), lastAttempt: record.lastAttempt,
            installedAt: state?.installedAt))

        var build = "none recorded yet (renew.sh records one after its next install)"
        if let state {
            build = "\(state.shortCommit ?? "no commit") from the \(state.builtFrom ?? "unknown") tree, installed "
                + "\(LogWords.date(state.installedAt)) on \(state.buildDevice ?? "an unknown device")"
        }
        var source = "none found"
        if let expiry {
            source = expiry.source == .installedBuild ? "the state file" : "Xcode's newest profile for the app"
        }
        let rows: [(String, String)] = [
            ("Repository", configuration.repository.path(percentEncoded: false)),
            ("State file", paths.stateFile.path(percentEncoded: false)),
            ("Installed build", build),
            ("End date", "\(LogWords.date(expiry?.expires)) (from \(source))"),
            ("Timing switch", "RenewalSwitch.timing = .\(policy.timing.rawValue)"
                + (policy.waitsForExpiry(situation) ? "; waits for the end date" : "")),
            ("Renew Automatically", record.autoRenew ? "on" : "off"),
            ("Stage", LogWords.stage(stage)),
            ("Pebble HOLD", hold.rawValue),
            ("iPhone", LogWords.phone(phone)),
            ("Decision now", LogWords.decision(decision)),
            ("Bar", words.bar),
            ("Menu", ([words.expiry] + (words.note.map { [$0] } ?? []) + [words.plan] + words.result)
                .joined(separator: " / ")),
            ("Log", paths.logFile.path(percentEncoded: false)),
        ]
        for (label, value) in rows {
            print(label.padding(toLength: 21, withPad: " ", startingAt: 0) + value)
        }
        return 0
    }
}
