import Foundation

/// The link a Mac shows to pair a phone (as a QR code, or copied and pasted through Universal Clipboard):
///
///     pebble-remote://pair?v=1&bid=<bridge id>&name=<Mac name>&pin=<base64url SPKI SHA-256>
///         &code=<base64url one-time code>&ep=<host:port>&ep=<host:port>...
///
/// Contract: the bridge contract, section 2. Valid for 5 minutes, once.
public struct PairingLink: Sendable, Hashable {
    public var version: Int
    public var bridgeID: String
    public var macName: String
    public var pin: String
    public var code: String
    public var endpoints: [Endpoint]

    public init(version: Int, bridgeID: String, macName: String, pin: String, code: String, endpoints: [Endpoint]) {
        self.version = version
        self.bridgeID = bridgeID
        self.macName = macName
        self.pin = pin
        self.code = code
        self.endpoints = endpoints
    }

    /// Parses the link's text by hand and decodes each value once. Never through URL(string:): a link with unencoded
    /// characters (an IPv6 endpoint's brackets) makes Foundation re-encode the whole string, "%20" included.
    public init?(string: String) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "pebble-remote://pair?"
        guard text.lowercased().hasPrefix(prefix) else { return nil }
        let query = text.dropFirst(prefix.count).prefix { $0 != "#" }
        self.init(query: String(query))
    }

    /// For links the system opened (onOpenURL, a scanned code). The bridge percent-encodes every value (section 2).
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "pebble-remote", url.host()?.lowercased() == "pair",
            let query = url.query(percentEncoded: true)
        else { return nil }
        self.init(query: query)
    }

    private init?(query: String) {
        let items: [(name: String, value: String?)] = query.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let decode = { (text: Substring) in String(text).replacingOccurrences(of: "+", with: " ").removingPercentEncoding }
            return (name: decode(parts[0]) ?? "", value: parts.count > 1 ? decode(parts[1]) : nil)
        }
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        // Only well-formed endpoints, each once, and at most `maximumEndpoints` of them: the phone races them all at once.
        var seen = Set<Endpoint>()
        let endpoints = items.filter { $0.name == "ep" }
            .compactMap { $0.value.flatMap(Endpoint.init(parsing:)) }
            .filter { seen.insert($0).inserted }
            .prefix(Self.maximumEndpoints)
        guard let versionText = value("v"), let version = Int(versionText), version == 1,
            let bridgeID = value("bid"), let pin = value("pin"), let code = value("code"), !endpoints.isEmpty
        else { return nil }
        // The name is the link's to choose (a web page can open such a link), and it goes into the confirmation and
        // Face ID's sentence: one plain line (security review 2026-10-30, S-08).
        let name = DisplayText.line(value("name") ?? "", limit: Self.maximumNameLength)
        self.init(
            version: version, bridgeID: bridgeID, macName: name.isEmpty ? "Mac" : name, pin: pin, code: code,
            endpoints: Array(endpoints))
    }

    /// The most endpoints a link may give (contract 3.2 lists four kinds; IPv6 addresses add a few). The phone races
    /// every one at once, so a link with hundreds would open hundreds of connections (S-07).
    public static let maximumEndpoints = 12
    /// The longest Mac name kept from a link, in characters.
    public static let maximumNameLength = 64

    /// How this link relates to the Mac the phone is paired with, which the confirmation must say before pairing.
    public enum Relation: Sendable, Hashable {
        /// No Mac is paired yet.
        case firstPairing
        /// The paired Mac, proving itself with the same key: pairing again only renews this phone's keys.
        case samePairedMac
        /// Another Mac: pairing replaces the one paired now.
        case replaces(PairedMac)
        /// The paired Mac's id, but another TLS key. Either that Mac set up Remote again (a new key), or the link is
        /// not from it: anyone on the network can read the id (Bonjour), and a link opened from a web page or tapped in
        /// a reply chooses its own key and addresses. Pairing replaces the working keys, so the confirmation warns
        /// (security review 2026-10-30, S-04).
        case sameMacNewKey(PairedMac)
    }

    public func relation(to paired: PairedMac?) -> Relation {
        guard let paired else { return .firstPairing }
        guard paired.bridgeID == bridgeID else { return .replaces(paired) }
        return Self.samePin(paired.pin, pin) ? .samePairedMac : .sameMacNewKey(paired)
    }

    /// Two pins name the same key: the same 32 bytes (a pin may be spelled with different unused bits), else the
    /// same text.
    static func samePin(_ a: String, _ b: String) -> Bool {
        if let left = Base64URL.decode(a), let right = Base64URL.decode(b) { return left == right }
        return a == b
    }
}

extension Endpoint {
    /// "host:port", "[ipv6]:port".
    public init?(parsing text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        let host: Substring
        let portText: Substring
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]"), text[text.index(after: close)...].hasPrefix(":") else {
                return nil
            }
            host = text[text.index(after: text.startIndex)..<close]
            portText = text[text.index(close, offsetBy: 2)...]
        } else {
            guard let colon = text.lastIndex(of: ":"), !text[..<colon].contains(":") else { return nil }
            host = text[..<colon]
            portText = text[text.index(after: colon)...]
        }
        guard Self.isValidHost(String(host)), let port = UInt16(portText), port > 0 else { return nil }
        self.init(host: String(host), port: port)
    }

    /// A host the phone may connect to: a DNS name (letters, digits, "-" and "_" in dot-separated labels, one trailing
    /// dot allowed), an IPv4 address, or an IPv6 address with an optional zone ("fe80::1%en0"). Anything else is
    /// refused, because the host goes into a `wss://` URL: "@", "/", "?", "#", "%" or a space there would make the
    /// phone connect to another host or port than the one the confirmation showed (security review 2026-10-30, S-06).
    public static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        if host.contains(":") {
            let parts = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
            let address = parts[0]
            guard address.filter({ $0 == ":" }).count >= 2,
                address.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == ":" || $0 == ".") })
            else { return false }
            guard parts.count == 2 else { return true }
            let zone = parts[1]
            return !zone.isEmpty && zone.count <= 32
                && zone.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        for (index, label) in labels.enumerated() {
            if label.isEmpty {
                guard index == labels.count - 1, index > 0 else { return false }  // one trailing dot: "mac.local."
                continue
            }
            guard label.count <= 63,
                label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
            else { return false }
        }
        return true
    }
}
