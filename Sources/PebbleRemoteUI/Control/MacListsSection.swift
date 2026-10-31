import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The phone's lists across every conversation, after Pebble's Settings sections: schedules and the windows Pebble
/// may use, whose rows open each conversation's Details › Tools (their one home, as on the Mac: the lead's IA decision,
/// 2026-10-31), and Stop Everything (the phone's own). The Toolbox is under Skills & connectors, as on the Mac.
struct MacListsSection: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        if store.bridgeOffers("job_list") || store.bridgeOffers("screen_sessions") || store.bridgeOffers("cancel") {
            Section {
                if store.bridgeOffers("job_list") {
                    NavigationLink(value: ControlRoute.schedules) {
                        Label(AppCopy.Control.schedules, systemImage: "calendar.badge.clock")
                    }
                }
                if store.bridgeOffers("screen_sessions") {
                    NavigationLink(value: ControlRoute.screenSessions) {
                        Label(AppCopy.Control.sharedWindows, systemImage: "macwindow.on.rectangle")
                    }
                }
                if store.bridgeOffers("cancel") {
                    StopEverythingButton()
                }
            } header: {
                Text(AppCopy.SettingsTab.acrossConversations)
            } footer: {
                Text(AppCopy.Details.acrossSectionNote)
            }
        }
    }
}
