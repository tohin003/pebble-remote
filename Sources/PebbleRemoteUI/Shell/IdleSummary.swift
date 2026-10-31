import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The accessory when nothing runs: Pebble is ready, or how the connection stands.
struct IdleSummary: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        HStack(spacing: PebbleSpace.s2) {
            // On the accessory's glass: Pebble's secondary text colour, which keeps 4.5:1, not the dimmed `.secondary`.
            Text(text)
                .font(.subheadline)
                .foregroundStyle(PebbleColor.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var text: String {
        if store.isDemo { return AppCopy.Home.idle }
        return ConnectionWords.state(store.connection.phase) ?? AppCopy.Home.idle
    }
}
