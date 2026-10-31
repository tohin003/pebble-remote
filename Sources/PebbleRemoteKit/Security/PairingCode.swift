import CryptoKit
import Foundation

/// The six digits both sides show once `pair` verifies (contract X-1, accepted by the bridge on 2026-10-30). The person
/// compares the phone's code with the Mac's and confirms on the Mac, and the bridge sends `paired` only then. A pairing
/// link that someone else got hold of cannot make the Mac show the same code as this phone does, so the person sees that
/// the two differ and cancels.
///
/// The code is the first 4 bytes of SHA-256 over the UTF-8 bytes of `pebble-remote/v1/sas\n` followed by T_pair (the
/// very bytes both pair signatures cover, `SignedTranscript.pair`), read as a big-endian unsigned integer, modulo
/// 1,000,000, zero-padded to six digits. Both sides compute it from their own copy of T_pair.
public struct PairingCode: Sendable, Hashable, CustomStringConvertible {
    /// Exactly six ASCII digits: "035072" keeps its leading zero.
    public let digits: String

    /// The code for the T_pair a pairing signs.
    public init(pairTranscript: Data) {
        var message = Data((SignedTranscript.sasLabel + "\n").utf8)
        message.append(pairTranscript)
        // The first four bytes of the digest, most significant first.
        let value = SHA256.hash(data: message).prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let text = String(value % 1_000_000)
        digits = String(repeating: "0", count: Self.length - text.count) + text
    }

    /// A code from its digits (tests, previews); nil unless it is six ASCII digits.
    public init?(digits: String) {
        guard digits.utf8.count == Self.length, digits.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) })
        else { return nil }
        self.digits = digits
    }

    /// How many digits a code has.
    public static let length = 6

    /// "035 072": two groups of three, as the screen shows it and as a person reads it aloud.
    public var grouped: String { "\(digits.prefix(3)) \(digits.suffix(3))" }

    /// The digits one by one, in two groups, for VoiceOver: "0 3 5, 0 7 2". Read as "035 072" it would be two numbers.
    public var spoken: String {
        let one = { (part: Substring) in part.map(String.init).joined(separator: " ") }
        return "\(one(digits.prefix(3))), \(one(digits.suffix(3)))"
    }

    public var description: String { digits }
}
