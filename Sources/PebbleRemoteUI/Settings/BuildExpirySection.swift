import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// "This build expires Tue 4 Nov, 09:12": free provisioning lasts 7 days, read from the app's embedded profile.
/// Shows nothing where there is no profile (the macOS type-check, a simulator build).
struct BuildExpirySection: View {
    /// Read once per launch; the profile can't change while the app runs.
    static let profile = ProvisioningProfile.embedded()

    var body: some View {
        if let profile = Self.profile {
            Section {
                BuildExpiryLabel(profile: profile)
            } header: {
                Text(AppCopy.Settings.build)
            } footer: {
                Text(AppCopy.Settings.renewHow)
            }
        }
    }
}

/// The build's expiry as one row, with how to renew it under it (Settings › iPhone).
struct BuildExpiryRow: View {
    var body: some View {
        if let profile = BuildExpirySection.profile {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                BuildExpiryLabel(profile: profile)
                Text(AppCopy.Settings.renewHow)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// "This build expires …", with a warning symbol on its last day.
struct BuildExpiryLabel: View {
    let profile: ProvisioningProfile

    var body: some View {
        Label(
            profile.isExpired() ? AppCopy.Settings.expired : AppCopy.Settings.expires(profile.expirationDate),
            systemImage: profile.daysLeft() <= 1 ? PebbleSymbol.expiry : "calendar")
    }
}
