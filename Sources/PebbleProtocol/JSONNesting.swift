import Foundation

/// How deeply JSON from the bridge may nest. Foundation's decoder recurses once per level, and on a cooperative thread
/// (512 KB of stack) a frame nested a little over 200 deep overflows the stack in a debug build: the app crashes, and a
/// replayed event or a conversation holding the value crashes it again on every connect. Pebble's own payloads nest
/// about ten levels; tool arguments a model wrote can nest as deep as it likes. So frames are measured before they are
/// decoded, and one nested deeper than `maximumDepth` is refused as unreadable (security review 2026-10-30, S-02).
public enum JSONNesting {
    /// The deepest nesting of arrays and objects accepted in one frame, the frame's own object included.
    public static let maximumDepth = 64

    /// True when `json` (UTF-8 text) nests arrays and objects deeper than `limit`. Brackets inside strings do not
    /// count. It stops at the first level past `limit`, and it never fails: unbalanced text is the decoder's to refuse.
    public static func exceeds(_ limit: Int, in json: Data) -> Bool {
        json.withUnsafeBytes { bytes in
            var depth = 0
            var inString = false
            var escaped = false
            for byte in bytes {
                if inString {
                    if escaped {
                        escaped = false
                    } else if byte == UInt8(ascii: "\\") {
                        escaped = true
                    } else if byte == UInt8(ascii: "\"") {
                        inString = false
                    }
                    continue
                }
                switch byte {
                case UInt8(ascii: "\""):
                    inString = true
                case UInt8(ascii: "["), UInt8(ascii: "{"):
                    depth += 1
                    if depth > limit { return true }
                case UInt8(ascii: "]"), UInt8(ascii: "}"):
                    depth -= 1
                default:
                    break
                }
            }
            return false
        }
    }
}
