import PebbleDesign
import PebbleProtocol
import SwiftUI

/// One permission mode: Pebble's name for it and one line on what it does, with a checkmark when chosen (UX audit U-07).
/// Pebble's full copy for each mode sits one tap away, under "What Each Mode Allows"; that changing it asks for Face ID
/// is said once, in the section's footer, not with a glyph on every row (U-38). VoiceOver still hears it on each row.
struct ModeRow: View {
    let mode: PermissionMode
    let isSelected: Bool
    let isChanging: Bool
    var needsFaceID = false
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Text(ModeCopy.for(mode).name)
                        .font(.headline)
                        .foregroundStyle(PebbleColor.text)
                    Text(AppCopy.Modes.summary(mode))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isChanging {
                    ProgressView()
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.bold())
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(needsFaceID ? AppCopy.FaceID.asksFirst : "")
    }
}
