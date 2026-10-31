import Foundation

/// Words that never reach the screen, from Pebble's `src/jargon.test.mjs` (`BANNED`, `NOWHERE`). Internal words stay
/// off what a person can see or hear; the app says what Pebble does in plain words instead. `BannedWordTests` scans
/// every copy string in this module, and `scripts/lint_copy.py` scans every Swift string literal under `Sources/`.
nonisolated public enum BannedWords {
    /// Matched as whole words, any case (`BANNED`).
    public static let words = ["inference", "receipt", "receipts", "host", "runtime", "capacity", "E-B1"]
    /// Retired names that must appear nowhere (`NOWHERE`).
    public static let phrases = [
        "Activity & review", "Windows Pebble can use", "Pebble's browser", "Settings → Mods", "Settings → Extensions",
    ]
    /// Not banned by Pebble, but internal to this app: say what they mean instead (`lint_copy.py` warns).
    public static let discouraged = ["bridge", "payload", "endpoint", "endpoints", "epoch", "RPC", "JSON", "idempotency"]

    /// Pebble's `BANNED` expression, word boundaries and all.
    public static let pattern = #"\b(inference|receipts?|host|runtime|capacity|E-B1)\b"#

    /// The banned words and retired phrases found in `text`, in order of appearance (empty when clean).
    public static func violations(in text: String) -> [String] {
        var found: [(Int, String)] = []
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) {
                    found.append((match.range.location, String(text[r])))
                }
            }
        }
        for phrase in phrases {
            if let r = text.range(of: phrase) {
                found.append((text.distance(from: text.startIndex, to: r.lowerBound), phrase))
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    public static func isClean(_ text: String) -> Bool { violations(in: text).isEmpty }
}
