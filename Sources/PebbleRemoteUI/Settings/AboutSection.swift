import Foundation
import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Versions: this app, and Pebble on the Mac; under them, in small type, the avatar engine's credit, as Pebble's own
/// About gives it.
struct AboutSection: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        Section {
            LabeledContent(AppCopy.appName, value: Self.appVersion)
            if let version = store.pebble?.version ?? store.bridge?.pebbleVersion {
                LabeledContent(AppCopy.pebble, value: version)
            }
        } header: {
            Text(AppCopy.Settings.about)
        } footer: {
            Text(AppCopy.Settings.avatarCredit)
        }
    }

    /// "Version 1.0 (5)", from this app's bundle.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return AppCopy.Settings.version(version, build: build)
    }
}
