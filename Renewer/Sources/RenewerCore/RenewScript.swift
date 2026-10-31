import Foundation

/// renew.sh's output as the renewer keeps it: renew.sh's own lines ("renew.sh: ..."), the lines that name an error,
/// and the last lines. xcodebuild prints thousands of lines; they are never kept whole.
public struct RenewOutput: Equatable, Sendable {
    public private(set) var scriptLines: [String] = []
    public private(set) var errorLines: [String] = []
    public private(set) var tail: [String] = []

    public static let errorLimit = 40
    public static let tailLimit = 60

    public init() {}

    public init(lines: [String]) {
        for line in lines { add(line) }
    }

    public mutating func add(_ raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if line.hasPrefix(RenewScript.prefix) {
            scriptLines.append(line)
            return
        }
        if RenewOutput.namesError(line), errorLines.count < RenewOutput.errorLimit { errorLines.append(line) }
        tail.append(line)
        if tail.count > RenewOutput.tailLimit { tail.removeFirst(tail.count - RenewOutput.tailLimit) }
    }

    static func namesError(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("error") || lower.contains("failed")
    }

    /// Every kept line, renew.sh's first.
    public var everything: String { (scriptLines + errorLines + tail).joined(separator: "\n") }
}

/// What a run of renew.sh came to.
public enum RenewOutcome: Equatable, Sendable {
    /// Built, installed, and (when renew.sh printed it) the new end date.
    case renewed(expires: Date?)
    case hold
    /// Another renewal was using the clean worktree.
    case busy
    case noIPhone
    case noXcode
    case noProject
    /// The recorded commit isn't in the repository any more.
    case commitMissing
    case worktreeFailed
    case signingFailed
    case buildFailed
    case installFailed(locked: Bool)
    case noAppOrDate
    case usage
    case timedOut
    case couldNotStart
    case failed(code: Int32)

    public var succeeded: Bool {
        if case .renewed = self { return true }
        return false
    }

    /// Whether a failed automatic renewal is worth one notification: not for a HOLD or another renewal, which only
    /// mean "later".
    public var worthANotice: Bool {
        switch self {
        case .renewed, .hold, .busy: return false
        default: return true
        }
    }
}

/// renew.sh's contract: its exit codes (see the script's header) and the words of its own lines.
public enum RenewScript {
    public static let prefix = "renew.sh: "

    public static let done: Int32 = 0
    public static let missingAppOrDate: Int32 = 1
    public static let usage: Int32 = 64
    public static let noProject: Int32 = 66
    public static let unavailable: Int32 = 69
    public static let worktree: Int32 = 73
    public static let hold: Int32 = 75

    /// Words in a failed build's output that point at signing rather than the code.
    static let signingWords = [
        "signing for", "provisioning profile", "no account for team", "requires a development team",
        "no signing certificate", "code signing", "codesign", "session has expired", "sign in", "unable to log in",
        "certificate", "communication with apple failed", "app id limit",
    ]

    public static func outcome(
        status: Int32, output: RenewOutput, timedOut: Bool = false, couldNotStart: Bool = false,
        timeZone: TimeZone = .current
    ) -> RenewOutcome {
        if couldNotStart { return .couldNotStart }
        if timedOut { return .timedOut }
        let said = output.scriptLines.joined(separator: "\n").lowercased()
        let all = output.everything.lowercased()
        switch status {
        case done:
            let date = output.scriptLines.reversed().lazy.compactMap { expiry(in: $0, timeZone: timeZone) }.first
            return .renewed(expires: date)
        case hold:
            return said.contains("another renewal") ? .busy : .hold
        case unavailable:
            return said.contains("xcode is not installed") ? .noXcode : .noIPhone
        case noProject:
            return .noProject
        case worktree:
            return said.contains("not in this repository") ? .commitMissing : .worktreeFailed
        case usage:
            return .usage
        default:
            break
        }
        if said.contains("no pebbleremote.app was found") || said.contains("expiry date could not be read") {
            return .noAppOrDate
        }
        if said.contains("installing on") {
            return .installFailed(locked: all.contains("locked") || all.contains("passcode"))
        }
        if said.contains("building for ios") {
            return signingWords.contains(where: { all.contains($0) }) ? .signingFailed : .buildFailed
        }
        return .failed(code: status)
    }

    /// The end date in renew.sh's last line:
    /// "renew.sh: installed. This build expires Fri 06 Nov 2026, 02:07 (in 5.0 days). Run ...".
    /// The state file is the first source; this is the fallback when it couldn't be written.
    public static func expiry(in line: String, timeZone: TimeZone = .current) -> Date? {
        guard let marker = line.range(of: "This build expires ") else { return nil }
        let rest = line[marker.upperBound...]
        guard let open = rest.range(of: " (") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE dd MMM yyyy, HH:mm"
        return formatter.date(from: String(rest[..<open.lowerBound]))
    }
}
