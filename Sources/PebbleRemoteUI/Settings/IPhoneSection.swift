import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Settings › iPhone, where Pebble's Settings window has its iPhone tab (Pebble 1.9.29, RemoteSettings.vue: between
/// Privacy & Stealth and Appearance). One section, as the lead decided (23:03): the Mac's rows for this app that the
/// phone can show, and the phone's own. Pairing a new iPhone stays on the Mac; the Mac's list of what this iPhone did,
/// and the unlock time when the bridge doesn't say it, are "On your Mac" rows. Forget This Mac is in Connection.
struct IPhoneSection: View {
    @Environment(RemoteStore.self) private var store
    @Environment(PebbleRemoteModel.self) private var model

    var body: some View {
        Section {
            if store.isDemo {
                Button(AppCopy.Settings.leaveDemo, systemImage: "xmark.circle", action: model.leaveDemo)
            }
            NavigationLink(value: ControlRoute.connection) {
                ConnectionSummaryRow()
            }
            if store.bridgeOffers("remote.devices") {
                NavigationLink(value: ControlRoute.pairedPhones) {
                    Label(AppCopy.Devices.title, systemImage: "iphone")
                }
            }
            if let seconds = store.bridge?.unlockSeconds, seconds > 0 {
                // The window the person chose on the Mac (welcome `unlock_seconds`); it changes only there.
                LabeledContent(
                    AppCopy.SettingsTab.unlockFor,
                    value: AppCopy.SettingsTab.unlockTime(minutes: max(1, seconds / 60)))
            } else {
                OnYourMacRow(title: AppCopy.SettingsTab.unlockFor)
            }
            OnYourMacRow(title: AppCopy.SettingsTab.whatYourIPhoneDid)
            if !store.isDemo {
                LockSettingRow()
            }
            BuildExpiryRow()
            LabeledContent(AppCopy.appName, value: AboutSection.appVersion)
        } header: {
            Text(AppCopy.SettingsTab.iPhone)
        } footer: {
            VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                if store.isDemo {
                    Text(AppCopy.Settings.demoNote)
                }
                Text(AppCopy.SettingsTab.iPhoneNote)
            }
        }
    }
}
