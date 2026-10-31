import Foundation

/// Takes out of a log line what must never be logged: Apple ID e-mail addresses, the names in signing identities and
/// Personal Teams, team ids, and anything that looks like a token, key or certificate fingerprint. Every line goes
/// through it before it reaches the log file.
public enum Redactor {
    struct Rule: Sendable {
        let pattern: String
        let template: String
        let ignoresCase: Bool
    }

    static let rules: [Rule] = [
        // E-mail addresses (an Apple ID is one).
        Rule(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, template: "<e-mail>", ignoresCase: true),
        // Signing identities carry the person's name: "Apple Development: Jane Doe (AB12CD34EF)".
        Rule(
            pattern: #"\b(Apple Development|Apple Distribution|iPhone Developer|iPhone Distribution|Mac Developer|Developer ID Application|Developer ID Installer)\s*:\s*[^"'\n]+"#,
            template: "$1: <name>", ignoresCase: true),
        // A Personal Team is named after the person: "Jane Doe (Personal Team)".
        Rule(pattern: #"[^"'\n:=]+\(Personal Team\)"#, template: "<name> (Personal Team)", ignoresCase: true),
        // Team ids after DEVELOPMENT_TEAM or "Team", and as an app id's prefix ("AB12CD34EF.io.github...").
        Rule(pattern: #"(DEVELOPMENT_TEAM\s*=\s*|[Tt]eam\s+(?:ID\s+)?["']?)[A-Z0-9]{10}\b"#, template: "$1<team>",
             ignoresCase: false),
        Rule(pattern: #"\b[A-Z0-9]{10}\.(?=[a-z][a-z0-9-]*\.)"#, template: "<team>.", ignoresCase: false),
        // Secrets named as such.
        Rule(pattern: #"\b(token|password|passwd|secret|authorization|bearer|cookie)\b\s*[:=]\s*\S+"#,
             template: "$1: <hidden>", ignoresCase: true),
        // Long opaque strings: tokens, keys, certificate fingerprints.
        Rule(pattern: #"[A-Za-z0-9_+=-]{40,}"#, template: "<hidden>", ignoresCase: false),
    ]

    public static func redact(_ text: String) -> String {
        var result = text
        for rule in rules {
            guard let expression = try? NSRegularExpression(
                pattern: rule.pattern, options: rule.ignoresCase ? [.caseInsensitive] : [])
            else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.template)
        }
        return result
    }
}
