import Foundation

/// Text that came from a pairing link, the bridge or Pebble (a Mac's name, a card's title, a schedule's name), made
/// safe to show as one line in the phone's own words and in what Face ID shows: no control or format characters (line
/// breaks, bidirectional overrides and isolates, zero-width characters), runs of white space as one space, and at most
/// `limit` characters. A pairing link from a web page, or a title a model wrote, can then neither break a Face ID
/// sentence over several lines nor reorder what it shows (security review 2026-10-30, S-08).
public enum DisplayText {
    public static func line(_ text: String, limit: Int = 80) -> String {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .surrogate,
                .privateUse, .unassigned:
                // Tabs and line breaks are controls; U+2028/U+2029 separators; bidi marks are formats.
                pendingSpace = pendingSpace || scalar.properties.isWhitespace || isBreak(scalar)
            default:
                if pendingSpace, !scalars.isEmpty { scalars.append(" ") }
                pendingSpace = false
                scalars.append(scalar)
            }
        }
        let cleaned = String(scalars)
        guard cleaned.count > limit, limit > 0 else { return cleaned }
        return String(cleaned.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    private static func isBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }
}
