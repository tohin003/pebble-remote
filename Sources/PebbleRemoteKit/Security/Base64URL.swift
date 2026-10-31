import Foundation

/// base64url without padding (RFC 4648, section 5): the contract's text form for keys, signatures, nonces, one-time
/// codes and pins (the bridge contract, sections 3.1 to 3.6).
public enum Base64URL {
    /// Encodes without padding.
    public static func encode<Bytes: DataProtocol>(_ bytes: Bytes) -> String {
        var text = Data(bytes).base64EncodedString()
        while text.last == "=" { text.removeLast() }
        return String(
            text.map { character in
                switch character {
                case "+": "-"
                case "/": "_"
                default: character
                }
            })
    }

    /// Decodes strictly: only the URL-safe alphabet, no padding, no whitespace. Returns nil for anything else.
    public static func decode(_ text: String) -> Data? {
        let utf8 = text.utf8
        guard utf8.count % 4 != 1, utf8.allSatisfy(isAlphabet) else { return nil }
        var standard = String(
            text.map { character in
                switch character {
                case "-": "+"
                case "_": "/"
                default: character
                }
            })
        standard += String(repeating: "=", count: (4 - utf8.count % 4) % 4)
        return Data(base64Encoded: standard)
    }

    private static func isAlphabet(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"):
            true
        default:
            false
        }
    }
}

extension Data {
    /// base64url without padding.
    public var base64URLEncoded: String { Base64URL.encode(self) }

    /// Strict base64url (no padding); nil for anything else.
    public init?(base64URLEncoded text: String) {
        guard let data = Base64URL.decode(text) else { return nil }
        self = data
    }
}

/// Comparisons whose time does not depend on where two secrets first differ.
public enum ConstantTime {
    /// True when both hold the same bytes. Unequal lengths return false at once (lengths are not secret here).
    public static func equal<A: DataProtocol, B: DataProtocol>(_ a: A, _ b: B) -> Bool {
        let left = [UInt8](a)
        let right = [UInt8](b)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}
