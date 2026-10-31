import PebbleDesign
import PebbleRemoteKit

/// Plain words for the connection's state, and the route badge's kind.
enum ConnectionWords {
    /// What to say about the connection when it isn't simply connected; nil when connected.
    static func state(_ phase: ConnectionPhase) -> String? {
        switch phase {
        case .connected: nil
        case .idle: AppCopy.Connection.notConnected
        case .connecting: AppCopy.Connection.connecting
        case .reconnecting(let attempt, _): AppCopy.Connection.reconnecting(attempt: attempt)
        case .failed(let problem): problemMessage(problem)
        }
    }

    static func problemMessage(_ problem: ConnectionProblem) -> String {
        switch problem {
        case .revoked: AppCopy.Connection.revoked
        case .unknownDevice: AppCopy.Connection.unknownDevice
        case .pinMismatch: AppCopy.Connection.identityChanged
        case .bridgeTooOld: AppCopy.Connection.pebbleTooOld
        case .pebbleNotRunning: AppCopy.Connection.pebbleNotRunning
        case .unreachable: AppCopy.Connection.unreachable
        case .localNetworkDenied: AppCopy.Connection.localNetworkDenied
        case .other(let message): message
        }
    }

    /// Problems only pairing again can fix.
    static func needsPairing(_ problem: ConnectionProblem) -> Bool {
        switch problem {
        case .revoked, .unknownDevice, .pinMismatch: true
        default: false
        }
    }

    static func routeName(_ route: RouteKind) -> String {
        switch route {
        case .lan: AppCopy.Connection.routeLocal
        case .tailscale: AppCopy.Connection.routeTailscale
        case .other: AppCopy.Connection.routeOther
        case .demo: AppCopy.Connection.routeDemo
        }
    }

    static func badgeRoute(_ route: RouteKind) -> RouteBadge.Route {
        switch route {
        case .lan: .lan
        case .tailscale: .tailscale
        case .other: .other
        case .demo: .demo
        }
    }
}
