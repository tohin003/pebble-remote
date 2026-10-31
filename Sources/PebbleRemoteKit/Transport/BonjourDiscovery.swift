import Foundation
import Network
import Synchronization

/// Finds the paired Mac's bridge on the LAN again after DHCP moved it (contract 3.1): Bonjour `_pebble-remote._tcp`,
/// matched by its TXT `bid` (and `v=1`). LiveClient adds what it finds to the endpoint race.
public protocol BridgeDiscovering: Sendable {
    /// Starts looking for `bridgeID`. `found` gets every LAN endpoint currently advertised for it, each time that list
    /// changes.
    func start(bridgeID: String, found: @escaping @Sendable ([Endpoint]) -> Void)
    func stop()
}

/// Discovery that never finds anything (tests, previews).
public struct NoBridgeDiscovery: BridgeDiscovering {
    public init() {}
    public func start(bridgeID: String, found: @escaping @Sendable ([Endpoint]) -> Void) {}
    public func stop() {}
}

/// NWBrowser on `_pebble-remote._tcp`. Each matching service is resolved to its address with a short TCP connection
/// (closed at once, before TLS), because the WebSocket needs a host and port to put in its URL. On iOS the app's
/// Info.plist lists the service in `NSBonjourServices` and explains local network access.
public final class BonjourBridgeDiscovery: BridgeDiscovering {
    public static let serviceType = "_pebble-remote._tcp"

    private struct State {
        var generation = 0
        var browser: NWBrowser?
        var resolving: [String: NWConnection] = [:]
        var found: [String: Endpoint] = [:]
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "PebbleRemote.bonjour", qos: .utility)

    public init() {}

    deinit {
        stop()
    }

    public func start(bridgeID: String, found: @escaping @Sendable ([Endpoint]) -> Void) {
        stop()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: .tcp)
        let generation = state.withLock { s in
            s.generation += 1
            s.browser = browser
            return s.generation
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.update(results, bridgeID: bridgeID, generation: generation, found: found)
        }
        browser.start(queue: queue)
    }

    public func stop() {
        let (browser, resolving) = state.withLock { s in
            s.generation += 1
            defer {
                s.browser = nil
                s.resolving = [:]
                s.found = [:]
            }
            return (s.browser, Array(s.resolving.values))
        }
        browser?.cancel()
        for connection in resolving { connection.cancel() }
    }

    /// True for the service of this bridge: its TXT `bid` (contract 3.1), or, with no TXT, an instance named by the
    /// bridge id (C6).
    static func matches(txt: [String: String], serviceName: String?, bridgeID: String) -> Bool {
        if let bid = txt["bid"] { return bid == bridgeID && (txt["v"] ?? "1") == "1" }
        return serviceName == bridgeID
    }

    private func update(
        _ results: Set<NWBrowser.Result>, bridgeID: String, generation: Int,
        found: @escaping @Sendable ([Endpoint]) -> Void
    ) {
        var matching: [String: NWEndpoint] = [:]
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            var txt: [String: String] = [:]
            if case .bonjour(let record) = result.metadata { txt = record.dictionary }
            if Self.matches(txt: txt, serviceName: name, bridgeID: bridgeID) { matching[name] = result.endpoint }
        }
        let (gone, toResolve, current): ([NWConnection], [(String, NWEndpoint)], [Endpoint]?) = state.withLock { s in
            guard s.generation == generation else { return ([], [], nil) }
            let goneNames = Set(s.found.keys).union(s.resolving.keys).subtracting(matching.keys)
            var gone: [NWConnection] = []
            for name in goneNames {
                s.found.removeValue(forKey: name)
                if let connection = s.resolving.removeValue(forKey: name) { gone.append(connection) }
            }
            let fresh = matching.filter { s.found[$0.key] == nil && s.resolving[$0.key] == nil }.map { ($0.key, $0.value) }
            return (gone, fresh, goneNames.isEmpty ? nil : Array(s.found.values))
        }
        for connection in gone { connection.cancel() }
        if let current { found(current.sorted { $0.description < $1.description }) }
        for (name, endpoint) in toResolve {
            resolve(name: name, endpoint: endpoint, generation: generation, found: found)
        }
    }

    /// Resolves a service to an address and port with a TCP connection that is closed once ready.
    private func resolve(
        name: String, endpoint: NWEndpoint, generation: Int, found: @escaping @Sendable ([Endpoint]) -> Void
    ) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let added = state.withLock { s in
            guard s.generation == generation else { return false }
            s.resolving[name] = connection
            return true
        }
        guard added else { return }
        connection.stateUpdateHandler = { [weak self] connectionState in
            switch connectionState {
            case .ready:
                let resolved = connection.currentPath?.remoteEndpoint.flatMap(Self.endpoint(from:))
                connection.cancel()
                self?.finished(name: name, endpoint: resolved, generation: generation, found: found)
            case .failed, .waiting:
                connection.cancel()
                self?.finished(name: name, endpoint: nil, generation: generation, found: found)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            if case .cancelled = connection.state { return }
            connection.cancel()
            self?.finished(name: name, endpoint: nil, generation: generation, found: found)
        }
    }

    private func finished(
        name: String, endpoint: Endpoint?, generation: Int, found: @escaping @Sendable ([Endpoint]) -> Void
    ) {
        let current: [Endpoint]? = state.withLock { s in
            guard s.generation == generation, s.resolving.removeValue(forKey: name) != nil else { return nil }
            guard let endpoint else { return nil }
            s.found[name] = endpoint
            return Array(s.found.values)
        }
        if let current { found(current.sorted { $0.description < $1.description }) }
    }

    /// A resolved address as the race's `Endpoint`: an IPv4 or IPv6 literal (with its zone), and the port.
    static func endpoint(from endpoint: NWEndpoint) -> Endpoint? {
        guard case .hostPort(let host, let port) = endpoint else { return nil }
        let text: String
        switch host {
        case .ipv4(let address): text = "\(address)"
        case .ipv6(let address): text = "\(address)"
        case .name(let name, _): text = name
        @unknown default: return nil
        }
        guard !text.isEmpty, port.rawValue > 0 else { return nil }
        return Endpoint(host: text, port: port.rawValue)
    }
}
