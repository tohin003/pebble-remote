import SwiftUI

/// The unlock (claude-w's C1): reading needs nothing; before Pebble acts on what this iPhone sends, Face ID unlocks it
/// for a few minutes. Locked, this row says so and offers Unlock (with the Face ID glyph); unlocked, it says how long
/// is left. Put it above the composer and at the top of Control while locked; it is content, not glass.
public struct UnlockPrompt: View {
    let remainingMinutes: Int?
    let onUnlock: () -> Void

    /// - Parameter remainingMinutes: nil while locked; otherwise the whole minutes left in the unlock.
    public init(remainingMinutes: Int?, onUnlock: @escaping () -> Void) {
        self.remainingMinutes = remainingMinutes
        self.onUnlock = onUnlock
    }

    public var body: some View {
        HStack(spacing: PebbleSpace.s3) {
            Image(systemName: remainingMinutes == nil ? PebbleSymbol.locked : PebbleSymbol.unlocked)
                .font(.title3)
                .foregroundStyle(PebbleColor.accent)
                .accessibilityHidden(true)
            Text(verbatim: remainingMinutes.map(AppCopy.Unlock.remaining(minutes:)) ?? AppCopy.Unlock.locked)
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if remainingMinutes == nil {
                Button(action: onUnlock) {
                    Label(AppCopy.Unlock.button, systemImage: PebbleSymbol.faceID)
                }
                .buttonStyle(.pebblePrimary)
                .controlSize(.regular)
                .accessibilityHint(AppCopy.Unlock.why)
            }
        }
        .padding(PebbleSpace.s3)
        .background(PebbleColor.soft, in: PebbleShapes.card)
        .accessibilityElement(children: .contain)
    }
}

#if os(iOS)
#Preview("Unlock") {
    VStack(spacing: PebbleSpace.s3) {
        UnlockPrompt(remainingMinutes: nil) {}
        UnlockPrompt(remainingMinutes: 12) {}
    }
    .padding()
}
#endif
