import AppKit
import Foundation
import Observation
import RenewerCore

/// The menu-bar item's state and actions. It reads the dates, checks at login, on wake and every 30 minutes, and
/// renews through scripts/renew.sh. Everything that decides lives in RenewerCore (RenewalPolicy, Words); this class
/// only gathers the facts, runs the subprocesses and keeps the record.
@MainActor
@Observable
final class RenewerModel {
    private(set) var now: Date = Date()
    private(set) var state: InstallState? = nil
    private(set) var xcodeProfile: ProfileSummary? = nil
    private(set) var record: RenewerRecord
    private(set) var renewing: Bool = false
    private(set) var decision: Decision? = nil

    let configuration: AppConfiguration
    private let log: FileLog
    private let notifier: Notifier
    private let probes: Probes
    @ObservationIgnored private var loop: Task<Void, Never>? = nil
    @ObservationIgnored private var ticker: Task<Void, Never>? = nil
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)? = nil
    @ObservationIgnored private var checking: Bool = false
    @ObservationIgnored private var stateStamp: Date? = nil
    @ObservationIgnored private var unreachableSince: Date? = nil
    @ObservationIgnored private var lastNote: String? = nil

    init(configuration: AppConfiguration) {
        let log = FileLog(url: configuration.paths.logFile)
        self.configuration = configuration
        self.log = log
        self.notifier = Notifier(log: log)
        self.probes = Probes(configuration: configuration, log: log)
        self.record = RenewerRecord.load(from: configuration.paths.recordFile)
        reload()
    }

    // MARK: What the menu shows

    var expiry: ExpiryInfo? { Expiry.resolve(state: state, profile: xcodeProfile) }

    var situation: Situation {
        Situation(
            now: now, expires: expiry?.expires, hasBuild: state?.buildCommit != nil, autoRenew: record.autoRenew,
            unmovedExpiry: record.unmovedExpiry, lastAutomaticFailure: record.lastAutomaticFailure,
            automaticFailures: record.automaticFailures)
    }

    var stage: Stage { configuration.policy.stage(situation) }

    var words: MenuWords {
        Words.menu(MenuFacts(
            now: now, expiry: expiry, stage: stage, decision: decision, renewing: renewing,
            waitsForExpiry: configuration.policy.waitsForExpiry(situation), lastAttempt: record.lastAttempt,
            installedAt: state?.installedAt))
    }

    var canRenewNow: Bool { !renewing && state?.buildCommit != nil }

    var autoRenew: Bool { record.autoRenew }

    // MARK: Starting

    /// Called once at launch; the work starts when the app's run loop does.
    func start() {
        Task { self.begin() }
    }

    private func begin() {
        _ = NSApplication.shared.setActivationPolicy(.accessory)
        do {
            try OwnerOnlyFile.makeFolder(configuration.paths.supportFolder)
        } catch {
            log.write("Couldn't make the support folder: \(error.localizedDescription)")
        }
        let timing = configuration.policy.timing == .beforeExpiry
            ? "from 1 day before the end date" : "right after the end date"
        log.write(
            "Started. Renew Automatically is \(record.autoRenew ? "on" : "off"); renewals run \(timing). "
                + "Repository: \(configuration.repository.path(percentEncoded: false))")
        if !FileManager.default.isExecutableFile(atPath: configuration.renewScript.path(percentEncoded: false)) {
            log.write("scripts/renew.sh wasn't found in that repository, so nothing can be renewed.")
        }
        notifier.requestPermission()
        observeWake()
        startTicker()
        scheduleChecks(after: configuration.policy.startDelay)
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.didWake() }
        }
    }

    private func didWake() {
        log.write("Woke from sleep: checking in a minute.")
        unreachableSince = nil
        scheduleChecks(after: configuration.policy.wakeDelay)
    }

    /// The check loop: after `delay`, then every 30 minutes or at the next edge (RenewalPolicy.nextCheck).
    private func scheduleChecks(after delay: TimeInterval) {
        loop?.cancel()
        loop = Task { [weak self] in
            var wait = delay
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self else { return }
                await self.check()
                wait = max(5, self.nextCheck().timeIntervalSinceNow)
            }
        }
    }

    private func nextCheck() -> Date {
        configuration.policy.nextCheck(after: Date(), expires: expiry?.expires, stage: stage)
    }

    /// Once a minute the bar's count moves on, and a state file that renew.sh rewrote (a run by hand) is read again.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func refresh() {
        now = Date()
        if OwnerOnlyFile.modificationDate(of: configuration.paths.stateFile) != stateStamp { reload() }
    }

    func reload() {
        now = Date()
        stateStamp = OwnerOnlyFile.modificationDate(of: configuration.paths.stateFile)
        let loaded = InstallState.load(from: configuration.paths.stateFile)
        if loaded != state { state = loaded }
        let profile = loaded?.profileExpires == nil
            ? ProvisioningProfiles.newest(for: configuration.bundleId, in: configuration.paths.profileFolders)
            : nil
        if profile != xcodeProfile { xcodeProfile = profile }
    }

    // MARK: The menu's actions

    func setAutoRenew(_ on: Bool) {
        guard record.autoRenew != on else { return }
        record.autoRenew = on
        saveRecord()
        log.write("Renew Automatically turned \(on ? "on" : "off").")
        if on { scheduleChecks(after: 2) }
    }

    func renewNow() {
        guard !renewing else { return }
        Task { await self.renew(automatic: false, device: nil) }
    }

    // MARK: The check (at login, on wake, every 30 minutes)

    func check() async {
        guard !checking, !renewing else { return }
        checking = true
        defer { checking = false }
        reload()
        let stage = self.stage
        var hold: HoldState? = nil
        var phone: Reachability? = nil
        switch stage {
        case .due:
            hold = await probes.hold()
            if hold == .clear { phone = await probes.phone(preferring: state?.buildDevice) }
        case .lastDay:
            phone = await probes.phone(preferring: state?.buildDevice)
        default:
            break
        }
        now = Date()
        let expires = expiry?.expires
        let decided = configuration.policy.decide(
            stage: stage, hold: hold, phone: phone, unreachableFor: unreachableTime(phone),
            alreadyNotified: record.wasNotified(.unreachable, for: expires))
        decision = decided
        note(stage, decided, phone)
        switch decided {
        case .renew(let device):
            await renew(automatic: true, device: device)
        case .waitForPhone(notify: true):
            if let expires {
                post(.unreachable, Copy.unreachableNotice(when: whenWords(expires), expired: expires <= now), for: expires)
            }
        default:
            break
        }
        if case .noBuild = stage, let expires, configuration.policy.isLastDay(now: now, expires: expires),
           !record.wasNotified(.noBuild, for: expires) {
            post(.noBuild, Copy.noBuildNotice(when: whenWords(expires), expired: expires <= now), for: expires)
        }
    }

    /// How long the iPhone has been out of reach, across checks (reset when it is seen, and on wake).
    private func unreachableTime(_ phone: Reachability?) -> TimeInterval? {
        switch phone {
        case nil:
            return nil
        case .some(.reachable), .some(.several):
            unreachableSince = nil
            return nil
        default:
            let since = unreachableSince ?? Date()
            unreachableSince = since
            return Date().timeIntervalSince(since)
        }
    }

    /// A check's line goes to the log only when it differs from the last one.
    private func note(_ stage: Stage, _ decision: Decision, _ phone: Reachability?) {
        var line = "Check: \(LogWords.stage(stage)); \(LogWords.decision(decision))"
        if let phone { line += "; iPhone \(LogWords.phone(phone))" }
        guard line != lastNote else { return }
        lastNote = line
        log.write(line)
    }

    // MARK: Renewing

    private func renew(automatic: Bool, device chosen: String?) async {
        guard !renewing else { return }
        reload()
        let startedAt = Date()
        let before = expiry?.expires
        guard let commit = state?.buildCommit else {
            refuse(.noBuild, automatic: automatic, at: startedAt, before: before)
            return
        }
        renewing = true
        defer {
            renewing = false
            now = Date()
        }
        var target = chosen
        if target == nil {
            // Renew Now checks the same two things first; it never passes --force.
            switch await probes.hold() {
            case .active:
                refuse(.hold, automatic: automatic, at: startedAt, before: before)
                return
            case .unknown:
                refuse(.holdUnknown, automatic: automatic, at: startedAt, before: before)
                return
            case .clear:
                break
            }
            switch await probes.phone(preferring: state?.buildDevice) {
            case .reachable(let found, _):
                target = found.identifier
            case .several:
                refuse(.severalPhones, automatic: automatic, at: startedAt, before: before)
                return
            default:
                refuse(.noIPhone, automatic: automatic, at: startedAt, before: before)
                return
            }
        }
        guard let device = target else { return }

        log.write("Renewing (\(automatic ? "automatic" : "Renew Now")): build \(commit.prefix(7)) on iPhone \(device).")
        let sink = log
        let result = await Runner.run(RunRequest(
            executable: configuration.renewScript,
            arguments: ["--commit", commit, "--device", device],
            environment: Runner.environment(developerDir: configuration.developerDir),
            directory: configuration.repository,
            timeout: configuration.renewTimeout,
            streamsLines: true,
            onLine: { line in sink.write(line) }))
        let finishedAt = Date()
        if let failure = result.launchFailure { log.write("renew.sh couldn't start: \(failure)") }
        let outcome = RenewScript.outcome(
            status: result.status, output: result.lines, timedOut: result.timedOut,
            couldNotStart: result.launchFailure != nil)

        reload()
        var after: Date? = nil
        if outcome.succeeded {
            if let recorded = state?.profileExpires, let installedAt = state?.installedAt,
               installedAt >= startedAt.addingTimeInterval(-5) {
                after = recorded
            } else if case .renewed(let printed) = outcome {
                after = printed
            }
        }
        let moved = RenewalPolicy.dateMoved(before: before, after: after)
        let stillExpired = after.map { $0 <= finishedAt } ?? false
        let succeeded = outcome.succeeded && !stillExpired
        let message = succeeded ? nil : (outcome.succeeded ? Copy.stillExpired : Copy.reason(outcome))
        // A HOLD that went up meanwhile, or another renewal, only means "later"; the rest count as failures.
        let failed = !succeeded && (outcome.worthANotice || stillExpired)

        record.lastAttempt = RenewerRecord.Attempt(
            at: startedAt, finishedAt: finishedAt, automatic: automatic, succeeded: succeeded, message: message,
            expiryBefore: before, expiryAfter: after, dateMoved: moved)
        if succeeded {
            record.lastAutomaticFailure = nil
            record.automaticFailures = 0
            if moved == false, let after {
                // Xcode kept its cached profile: renewing again waits for this end date.
                record.unmovedExpiry = after
            } else if moved == true {
                record.unmovedExpiry = nil
            }
        } else if automatic, failed {
            record.lastAutomaticFailure = startedAt
            record.automaticFailures += 1
        }
        saveRecord()

        let minutes = max(1, Int((finishedAt.timeIntervalSince(startedAt) / 60).rounded()))
        if succeeded {
            let change = moved == false
                ? "the end date didn't move (\(LogWords.date(after)))"
                : "end date \(LogWords.date(before)) -> \(LogWords.date(after))"
            log.write("Renewed in about \(minutes) min: \(change).")
        } else {
            log.write("Couldn't renew (exit \(result.status), about \(minutes) min): \(message ?? Copy.seeLog)")
            let lines = result.lines.errorLines.isEmpty ? result.lines.tail : result.lines.errorLines
            for line in lines.suffix(15) { log.write("  " + line) }
            if automatic, failed, let expires = expiry?.expires, !record.wasNotified(.failed, for: expires) {
                let words = Copy.failedNotice(
                    reason: message ?? Copy.seeLog, when: whenWords(expires), expired: expires <= Date())
                post(.failed, words, for: expires)
            }
        }
        if !automatic { scheduleChecks(after: 60) }
    }

    /// Renew Now that didn't start renew.sh: the reason becomes the last result.
    private func refuse(_ refusal: Refusal, automatic: Bool, at startedAt: Date, before: Date?) {
        record.lastAttempt = RenewerRecord.Attempt(
            at: startedAt, finishedAt: Date(), automatic: automatic, succeeded: false,
            message: Copy.reason(refusal), expiryBefore: before)
        saveRecord()
        log.write("Didn't renew: \(Copy.reason(refusal))")
    }

    // MARK: Notices and the record

    private func post(_ notice: Notice, _ words: NoticeWords, for expires: Date) {
        notifier.post(notice, words: words)
        record.markNotified(notice, for: expires)
        saveRecord()
        log.write("Notified: \(words.title)")
    }

    private func whenWords(_ date: Date) -> String {
        TimeWords.when(date, now: Date(), calendar: .current, locale: .current)
    }

    private func saveRecord() {
        do {
            try OwnerOnlyFile.write(record.encoded(), to: configuration.paths.recordFile)
        } catch {
            log.write("Couldn't save renewer.json: \(error.localizedDescription)")
        }
    }
}
