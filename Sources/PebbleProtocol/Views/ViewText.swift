import Foundation

// Lane G (2026-10-31): pebble-ui-spec v1 (contract 3.12), the views Pebble sends as data.

/// The display text of Pebble's views (pebble-ui-spec v1, rule 3): every string is shown literally, never as a link,
/// markup or a button's words. Pebble's own windows clamp it the same way (activity.ts `clampText`): control and
/// direction characters become spaces, a single line collapses its white space, and text past its bound ends in "…".
public enum ViewText {
    /// `value` made safe to show: one line (or keeping its line breaks when `multiline`), at most `limit` characters.
    /// Nil when nothing is left, so an empty string never draws an empty row.
    public static func clamp(_ value: String, _ limit: Int, multiline: Bool = false) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            scalars.append(isControl(scalar) ? " " : scalar)
        }
        var text = String(scalars)
        if multiline {
            text = text.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            text = collapsed(text)
        }
        guard !text.isEmpty, limit > 0 else { return nil }
        guard text.count > limit else { return text }
        var cut = String(text.prefix(limit - 1))
        while let last = cut.last, last.isWhitespace { cut.removeLast() }
        return cut + "\u{2026}"
    }

    /// Pebble's control set (activity.ts `CONTROL`), plus the direction marks the phone's own one-line rule removes
    /// (DisplayText, S-08) and the byte-order mark.
    static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x08, 0x0B...0x1F, 0x7F...0x9F, 0x2028...0x2029, 0x202A...0x202E, 0x2066...0x2069: true
        case 0x200E, 0x200F, 0x061C, 0xFEFF: true
        default: false
        }
    }

    /// Runs of white space as one space, trimmed (JavaScript's `/\s+/g` and `trim()`).
    static func collapsed(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var pending = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                pending = true
                continue
            }
            if pending, !out.isEmpty { out.append(" ") }
            pending = false
            out.append(scalar)
        }
        return String(out)
    }
}
