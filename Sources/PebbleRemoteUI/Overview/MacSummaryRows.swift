import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The Mac: its name and battery, Keep awake and its screen when the bridge offers them. They are on the Pebble tab
/// only (UX audit U-36; the IA map: "The Mac (battery, Keep awake, screenshot) → Pebble tab › your Mac").
struct MacSummaryRows: View {
    let mac: MacOverview
    @Environment(RemoteStore.self) private var store

    /// What Keep Awake does now; on battery, that turning it on asks for Face ID.
    private var keepAwakeNote: String {
        if mac.keepAwake { return AppCopy.Mac.keepAwakeOnNote }
        return mac.onPower == false ? AppCopy.Mac.keepAwakeBatteryNote : AppCopy.Mac.keepAwakeOffNote
    }

    var body: some View {
        LabeledContent {
            Text(AppCopy.Mac.batteryLine(percent: mac.batteryPercent, charging: mac.charging, onPower: mac.onPower))
        } label: {
            Label(mac.name, systemImage: PebbleSymbol.mac)
        }
        if store.bridgeOffers("remote.keep_awake") {
            RemoteToggle(
                AppCopy.Mac.keepAwake,
                subtitle: keepAwakeNote,
                value: mac.keepAwake,
                faceID: mac.onPower == false ? .whenTurningOn : .never
            ) { on in
                await store.attempt { try await store.setKeepAwake(on) }
            }
        }
        if store.bridgeOffers("remote.screenshot") {
            // The Pebble tab's stack routes conversations only; the Mac's screen is a leaf, so the link carries it.
            NavigationLink {
                MacScreenDestination()
            } label: {
                Label(AppCopy.MacScreen.title, systemImage: "display")
            }
        }
    }
}
