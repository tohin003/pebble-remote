import Foundation

/// How the checks read in the log and in `--check`. Short and stable (a check's line is logged only when it
/// changes), with no personal details: devices appear by identifier, never by name.
public enum LogWords {
    public static func date(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm Z"
        return formatter.string(from: date)
    }

    public static func stage(_ stage: Stage) -> String {
        switch stage {
        case .unknownDate: return "no end date known"
        case .noBuild: return "no installed build recorded"
        case .off: return "Renew Automatically is off"
        case .early(let renewsAt): return "not due yet (renews from \(date(renewsAt)))"
        case .lastDay(let renewsAt): return "last day, renewing waits for the end date (\(date(renewsAt)))"
        case .due: return "due"
        case .resting(let until): return "due, resting after a failed try until \(date(until))"
        }
    }

    public static func decision(_ decision: Decision) -> String {
        switch decision {
        case .wait: return "wait"
        case .waitForHold: return "wait for Pebble's HOLD to lift"
        case .holdUnknown: return "wait (hold-status.sh couldn't tell)"
        case .waitForPhone(let notify): return notify ? "wait for the iPhone, and notify" : "wait for the iPhone"
        case .severalPhones: return "wait (more than one iPhone reachable)"
        case .renew(let device): return "renew on \(device)"
        }
    }

    public static func phone(_ phone: Reachability) -> String {
        switch phone {
        case .reachable(let device, let link): return "reachable \(linkWords(link)) as \(device.identifier)"
        case .unreachable(let knownPhone): return knownPhone ? "paired, not reachable" : "no paired iPhone"
        case .several(let devices): return "\(devices.count) iPhones reachable"
        case .unreadable: return "devicectl's list couldn't be read"
        }
    }

    public static func linkWords(_ link: Link) -> String {
        switch link {
        case .cable: return "by cable"
        case .network: return "on the network"
        case .other: return "(connected)"
        }
    }
}
