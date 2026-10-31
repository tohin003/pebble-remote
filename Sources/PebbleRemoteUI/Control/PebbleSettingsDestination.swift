import PebbleRemoteKit
import SwiftUI

/// A Pebble settings screen once the store has read Pebble's settings (a moment after connecting).
struct PebbleSettingsDestination: View {
    enum Screen { case memory, appearance, notifications }

    let screen: Screen
    @Environment(RemoteStore.self) private var store

    var body: some View {
        if screen == .notifications {
            if let notifications = store.notificationSettings?.object {
                NotificationsView(settings: notifications)
            } else {
                ProgressView()
                    .task { await store.load(.notifications) }
            }
        } else if let settings = store.settings {
            if screen == .memory {
                MemorySettingsView(settings: settings)
            } else {
                MacAppearanceView(settings: settings)
            }
        } else {
            ProgressView()
        }
    }
}
