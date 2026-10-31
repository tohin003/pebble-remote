import SwiftUI

/// Stealth Lockdown's switch, as Pebble's Settings shows it: the pebble wearing the Veil while it's on (cast and
/// released as on the Mac), Pebble's description, the state line in the Veil's ink, and the honest line under it,
/// always. Like `GuardedToggle`, the switch shows Pebble's state and moves when Pebble confirms. In a `Form` row it
/// also takes the Veil's soft background.
public struct StealthToggleRow: View {
    let isOn: Bool
    let isBusy: Bool
    let onChange: (Bool) -> Void

    public init(isOn: Bool, isBusy: Bool = false, onChange: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.isBusy = isBusy
        self.onChange = onChange
    }

    private var request: Binding<Bool> {
        Binding(get: { isOn }, set: { wanted in if wanted != isOn { onChange(wanted) } })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Toggle(isOn: request) {
                HStack(spacing: PebbleSpace.s3) {
                    PebbleAvatar(pose: .idle, stealth: isOn)
                        .frame(width: 40, height: 40)
                    SettingLabel(AppCopy.Stealth.name, detail: AppCopy.Stealth.description)
                    if isBusy {
                        Spacer(minLength: 0)
                        ProgressView()
                    }
                }
            }
            .tint(PebbleColor.avatarStealth)
            .disabled(isBusy)
            Text(verbatim: isOn ? AppCopy.Stealth.onText : AppCopy.Stealth.offText)
                .font(PebbleFont.meta)
                .foregroundStyle(isOn ? PebbleColor.stealthInk : PebbleColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Text(verbatim: AppCopy.Stealth.honest)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(
            LinearGradient(
                colors: [PebbleColor.stealthSoft, PebbleColor.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
        .sensoryFeedback(PebbleHaptics.selection, trigger: isOn)
    }
}

#if os(iOS)
#Preview("Stealth Lockdown") {
    @Previewable @State var on = false
    Form {
        StealthToggleRow(isOn: on) { on = $0 }
    }
}
#endif
