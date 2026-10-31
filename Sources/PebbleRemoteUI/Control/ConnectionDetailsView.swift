import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// How the phone reaches the Mac: the route and round trip now, the address in use, every address the Mac offered,
/// and the versions on the Mac.
struct ConnectionDetailsView: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        Form {
            Section {
                if let state = ConnectionWords.state(store.connection.phase), !store.isDemo {
                    LabeledContent(AppCopy.Connection.title, value: state)
                }
                if let route = store.connection.route {
                    LabeledContent(AppCopy.Connection.route, value: ConnectionWords.routeName(route))
                }
                if let roundTrip = store.connection.roundTrip {
                    LabeledContent(
                        AppCopy.Connection.roundTrip, value: AppCopy.Connection.milliseconds(roundTrip))
                }
                if let endpoint = store.connection.endpoint {
                    LabeledContent(AppCopy.Connection.address, value: endpoint.description)
                }
                if let since = store.connection.since {
                    LabeledContent(AppCopy.Connection.connectedSince) {
                        Text(since, format: .dateTime.hour().minute())
                    }
                }
            }
            if let mac = store.pairedMac, !mac.endpoints.isEmpty {
                Section(AppCopy.Connection.addresses) {
                    ForEach(mac.endpoints, id: \.self) { endpoint in
                        LabeledContent(endpoint.description, value: ConnectionWords.routeName(endpoint.routeKind))
                    }
                }
            }
            if store.usesUnlock {
                // C1: reading never needs Face ID; acting does, within the bridge's window. The client asks by itself
                // when a call needs it; Unlock here asks now.
                Section {
                    UnlockStatusRow()
                } header: {
                    Text(AppCopy.Unlock.title)
                } footer: {
                    Text("\(AppCopy.Unlock.explanation(minutes: store.unlockMinutes)) \(AppCopy.Unlock.why)")
                }
            }
            if let bridge = store.bridge {
                Section {
                    LabeledContent(AppCopy.Connection.remoteOnMac, value: bridge.bridgeVersion)
                    if let version = bridge.pebbleVersion {
                        LabeledContent(AppCopy.pebble, value: version)
                    }
                }
            }
            // The Mac this iPhone is paired with, and Forget This Mac (Settings › iPhone has no other place for it).
            if let mac = store.pairedMac {
                PairedMacSection(mac: mac)
            }
        }
        .navigationTitle(AppCopy.Connection.title)
    }
}
