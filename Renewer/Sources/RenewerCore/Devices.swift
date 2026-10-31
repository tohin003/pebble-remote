import Foundation

/// One device in `xcrun devicectl list devices --json-output -`.
public struct PairedDevice: Equatable, Sendable {
    /// CoreDevice's identifier; renew.sh's `--device` takes it.
    public var identifier: String
    public var name: String?
    public var udid: String?
    public var platform: String?
    public var deviceType: String?
    /// "paired", "unpaired", "pairingInProgress".
    public var pairingState: String?
    /// "connected", "connecting", "disconnected", "unavailable".
    public var tunnelState: String?
    /// "wired", "localNetwork" (absent while the Mac can't reach it).
    public var transportType: String?

    public init(
        identifier: String, name: String? = nil, udid: String? = nil, platform: String? = nil,
        deviceType: String? = nil, pairingState: String? = nil, tunnelState: String? = nil,
        transportType: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.udid = udid
        self.platform = platform
        self.deviceType = deviceType
        self.pairingState = pairingState
        self.tunnelState = tunnelState
        self.transportType = transportType
    }

    public var isIPhone: Bool {
        platform?.lowercased() == "ios" && (deviceType == nil || deviceType == "iPhone")
    }

    public var isPaired: Bool { pairingState == "paired" }

    /// How the Mac reaches it right now: by cable or on the network. Nil when it can't.
    public var link: Link? {
        guard isPaired, tunnelState != "unavailable" else { return nil }
        switch transportType {
        case "wired": return .cable
        case "localNetwork": return .network
        default: return tunnelState == "connected" ? .other : nil
        }
    }

    public func matches(_ id: String) -> Bool {
        identifier.caseInsensitiveCompare(id) == .orderedSame
            || udid?.caseInsensitiveCompare(id) == .orderedSame
    }
}

public enum Link: String, Equatable, Sendable {
    case cable
    case network
    /// Connected, by a way devicectl didn't name.
    case other
}

public enum Reachability: Equatable, Sendable {
    case reachable(PairedDevice, Link)
    /// No paired iPhone the Mac can reach now. `knownPhone`: one is paired, just not reachable.
    case unreachable(knownPhone: Bool)
    /// More than one paired iPhone is reachable and none is the one renew.sh last installed on.
    case several([PairedDevice])
    /// devicectl failed, or its output made no sense.
    case unreadable
}

public enum DeviceListError: Error, Equatable {
    case unreadable
}

public enum DeviceList {
    /// Parses devicectl's device list. Reads the long-standing keys (`hardwareProperties`, `deviceProperties`,
    /// `connectionProperties`) first, then the newer `properties` dictionary that Xcode 27's devicectl says replaces
    /// them (`properties.<category>.<field>`), so the parser keeps working when the old keys go.
    public static func parse(_ data: Data) throws -> [PairedDevice] {
        // A tool may print a line before the document: start at the first "{".
        guard let open = data.firstIndex(of: UInt8(ascii: "{")),
              let root = (try? JSONSerialization.jsonObject(with: data[open...])) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]]
        else { throw DeviceListError.unreadable }
        return devices.compactMap(device(from:))
    }

    static func device(from item: [String: Any]) -> PairedDevice? {
        guard let identifier = item["identifier"] as? String, isPlainIdentifier(identifier) else { return nil }
        let properties = item["properties"] as? [String: Any]
        let hardware = item["hardwareProperties"] as? [String: Any]
        let details = item["deviceProperties"] as? [String: Any]
        let connection = item["connectionProperties"] as? [String: Any]
        func value(_ legacy: [String: Any]?, _ key: String, or alternates: [(String, String)] = []) -> String? {
            if let found = text(legacy?[key]) { return found }
            return lookup(key, in: properties, alternates: alternates)
        }
        return PairedDevice(
            identifier: identifier,
            name: value(details, "name"),
            udid: value(hardware, "udid"),
            platform: value(hardware, "platform"),
            deviceType: value(hardware, "deviceType"),
            pairingState: value(connection, "pairingState", or: [("pairing", "state")]),
            tunnelState: value(connection, "tunnelState", or: [("tunnel", "state")]),
            transportType: value(connection, "transportType", or: [("connection", "transport")]))
    }

    /// `properties.<field>`, `properties.<category>.<field>` (categories in name order), then the alternates.
    static func lookup(_ key: String, in properties: [String: Any]?, alternates: [(String, String)]) -> String? {
        guard let properties else { return nil }
        if let found = text(properties[key]) { return found }
        for category in properties.keys.sorted() {
            if let fields = properties[category] as? [String: Any], let found = text(fields[key]) { return found }
        }
        for (category, field) in alternates {
            if let fields = properties[category] as? [String: Any], let found = text(fields[field]) { return found }
        }
        return nil
    }

    /// A field is a string, or a dictionary holding it under "value".
    static func text(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let wrapped = value as? [String: Any] { return wrapped["value"] as? String }
        return nil
    }

    /// CoreDevice identifiers and UDIDs: letters, digits and hyphens, starting with a letter or digit (they become
    /// arguments to renew.sh, so nothing that reads as an option).
    public static func isPlainIdentifier(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, text.count <= 64,
              first.isASCII, CharacterSet.alphanumerics.contains(first)
        else { return false }
        return text.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
    }

    /// The iPhone to install on. The one renew.sh last installed on wins when it is still paired; another iPhone is
    /// never used in its place while it is merely out of reach.
    public static func reachability(of devices: [PairedDevice], preferring preferred: String?) -> Reachability {
        let phones = devices.filter { $0.isIPhone && $0.isPaired }
        if let preferred, let recorded = phones.first(where: { $0.matches(preferred) }) {
            if let link = recorded.link { return .reachable(recorded, link) }
            return .unreachable(knownPhone: true)
        }
        let reachable: [(PairedDevice, Link)] = phones.compactMap { phone in
            guard let link = phone.link else { return nil }
            return (phone, link)
        }
        if reachable.count == 1, let only = reachable.first { return .reachable(only.0, only.1) }
        if reachable.count > 1 { return .several(reachable.map { $0.0 }) }
        return .unreachable(knownPhone: !phones.isEmpty)
    }
}
