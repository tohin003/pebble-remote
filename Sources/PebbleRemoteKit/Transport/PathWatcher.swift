import Foundation
import Network
import Synchronization

/// Tells LiveClient when the phone's network changes (Wi-Fi to cellular, a new Wi-Fi, Tailscale coming up), so it
/// races the Mac's endpoints again instead of waiting for a dead socket to time out.
public protocol PathWatching: Sendable {
    /// Starts watching. `onChange` runs after each change that matters, never for the first report.
    func start(_ onChange: @escaping @Sendable () -> Void)
    func stop()
}

/// NWPathMonitor, reporting only changes to the path's status or its interfaces.
public final class NetworkPathWatcher: PathWatching {
    private struct State {
        var monitor: NWPathMonitor?
        var signature: String?
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "PebbleRemote.path", qos: .utility)

    public init() {}

    public func start(_ onChange: @escaping @Sendable () -> Void) {
        let monitor = NWPathMonitor()
        let previous = state.withLock { state in
            defer {
                state.monitor = monitor
                state.signature = nil
            }
            return state.monitor
        }
        previous?.cancel()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let signature = Self.signature(of: path)
            let changed = self.state.withLock { state in
                defer { state.signature = signature }
                return state.signature != nil && state.signature != signature
            }
            if changed { onChange() }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        let monitor = state.withLock { state in
            defer {
                state.monitor = nil
                state.signature = nil
            }
            return state.monitor
        }
        monitor?.cancel()
    }

    /// What identifies a path for reconnecting: whether it works and over which interfaces.
    static func signature(of path: NWPath) -> String {
        let status: String =
            switch path.status {
            case .satisfied: "up"
            case .unsatisfied: "down"
            case .requiresConnection: "on-demand"
            @unknown default: "other"
            }
        let interfaces = path.availableInterfaces.map { "\($0.type):\($0.name)" }.sorted()
        return ([status] + interfaces).joined(separator: ",")
    }
}

/// A watcher that never reports a change (tests, previews).
public struct StillPathWatcher: PathWatching {
    public init() {}
    public func start(_ onChange: @escaping @Sendable () -> Void) {}
    public func stop() {}
}
