import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The route and round trip while connected ("Home Wi-Fi · 6 ms"); the connection's state otherwise.
struct ConnectionLine: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        if store.isDemo {
            RouteBadge(route: .demo, roundTripMilliseconds: nil)
        } else if let state = ConnectionWords.state(store.connection.phase) {
            Label(state, systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
        } else if let route = store.connection.route {
            RouteBadge(route: ConnectionWords.badgeRoute(route), roundTripMilliseconds: store.connection.roundTrip)
        }
    }
}
