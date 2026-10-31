import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The connection in one row of Settings › iPhone: "Connection", then the route and round trip ("Local network ·
/// 6 ms"), or the state when not connected.
struct ConnectionSummaryRow: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        LabeledContent {
            Text(value)
        } label: {
            Label(AppCopy.Connection.title, systemImage: symbol)
        }
    }

    private var value: String {
        if store.isDemo { return AppCopy.Connection.routeDemo }
        if let state = ConnectionWords.state(store.connection.phase) { return state }
        let route =
            store.connection.route.flatMap { store.isConnectedToMac ? ConnectionWords.routeName($0) : nil }
            ?? AppCopy.Connection.route
        guard let roundTrip = store.connection.roundTrip else { return route }
        return route + " \u{00B7} " + AppCopy.Connection.milliseconds(roundTrip)
    }

    private var symbol: String {
        switch store.connection.route {
        case .lan: "wifi"
        case .tailscale: "point.3.connected.trianglepath.dotted"
        case .demo: "play.circle"
        default: store.isConnectedToMac ? "globe" : "antenna.radiowaves.left.and.right.slash"
        }
    }
}
