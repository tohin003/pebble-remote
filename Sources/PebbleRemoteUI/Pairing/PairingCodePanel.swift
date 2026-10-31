import Accessibility
import PebbleDesign
import PebbleRemoteKit
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// While the Mac waits for the person to confirm a pairing (X-1): the six digits the phone made from the pairing it
/// signed, large, to compare with the Mac's, and what to do. The person confirms on the Mac, so this has no Confirm
/// button; it has Cancel (`showsCancel`, unless a sheet's own toolbar has it).
///
/// The screen stays awake while it shows, so that the phone does not lock and leave the Mac waiting for a connection
/// iOS may close while the person looks at the Mac. VoiceOver hears the code, one digit at a time, as it appears.
struct PairingCodePanel: View {
    let code: PairingCode
    var showsCancel = true
    let cancel: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize = 96
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize = 56

    var body: some View {
        VStack(spacing: PebbleSpace.s5) {
            PebbleAvatar(pose: .idle)
                .frame(width: avatarSize, height: avatarSize)
            VStack {
                Text(AppCopy.Pairing.codeTitle)
                    .font(.largeTitle)
                    .bold()
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(AppCopy.Pairing.codePrompt)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
            PebbleCard {
                Text(code.grouped)
                    .font(.system(size: digitSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(PebbleColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(AppCopy.Pairing.codeLabel)
                    .accessibilityValue(code.spoken)
            }
            Text(AppCopy.Pairing.codeMismatch)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack {
                ProgressView(AppCopy.Pairing.codeWaiting)
                Text(AppCopy.Pairing.codeTimeLimit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if showsCancel {
                Button(AppCopy.Pairing.cancel, role: .cancel, action: cancel)
                    .buttonStyle(.pebbleSecondary)
            }
        }
        .frame(maxWidth: PebbleSize.readableWidth)
        .onAppear {
            Self.keepScreenAwake(true)
            AccessibilityNotification.Announcement(
                "\(AppCopy.Pairing.codeTitle). \(AppCopy.Pairing.codeLabel) \(code.spoken)"
            ).post()
        }
        .onDisappear { Self.keepScreenAwake(false) }
    }

    /// Stops the phone from locking itself while the person looks at the Mac (iPhone only).
    static func keepScreenAwake(_ on: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}

#if os(iOS)
#Preview("Confirm on the Mac") {
    PairingCodePanel(code: PairingCode(digits: "035072") ?? PairingCode(pairTranscript: Data()), cancel: {})
        .padding()
}
#endif
