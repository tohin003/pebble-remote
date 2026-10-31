import SwiftUI

/// A switch for one of Pebble's settings that changes only when Pebble confirms, and that asks for Face ID first when
/// the change widens what Pebble may do (turning a tool on, Keep Awake on battery, a schedule's resume).
///
/// The switch shows Pebble's state, never a hoped-for one: flipping it calls `onChange` with the wanted value, a spinner
/// shows while the screen asks Face ID and Pebble, and the switch moves when the new state arrives. The Face ID glyph
/// after the name says the next change asks for Face ID; VoiceOver hears it as a hint.
///
/// ```swift
/// GuardedToggle(
///     SettingsCopy.Permissions.toolName("web"), detail: SettingsCopy.Permissions.toolNote("web"),
///     isOn: tools["web"] == true, faceID: .whenTurningOn, isBusy: busy == "web"
/// ) { wanted in Task { await store.setTool("web", on: wanted) } }
/// ```
public struct GuardedToggle: View {
    /// When a change asks for Face ID.
    public enum FaceIDRule: Sendable, Hashable {
        /// Never (narrowing settings, presentation switches).
        case never
        /// Only turning it on (it widens what Pebble may do).
        case whenTurningOn
        /// Every change.
        case always
    }

    let title: String
    let detail: String?
    let isOn: Bool
    let faceID: FaceIDRule
    let isBusy: Bool
    let isDisabled: Bool
    let onChange: (Bool) -> Void

    /// - Parameters:
    ///   - isOn: Pebble's current value.
    ///   - isBusy: a change is on its way (Face ID, then Pebble).
    ///   - isDisabled: Pebble refuses changes now (a task runs, Reduce motion wins); say why in `detail`.
    public init(
        _ title: String, detail: String? = nil, isOn: Bool, faceID: FaceIDRule = .never, isBusy: Bool = false,
        isDisabled: Bool = false, onChange: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.detail = detail
        self.isOn = isOn
        self.faceID = faceID
        self.isBusy = isBusy
        self.isDisabled = isDisabled
        self.onChange = onChange
    }

    private var nextNeedsFaceID: Bool {
        switch faceID {
        case .never: false
        case .whenTurningOn: !isOn
        case .always: true
        }
    }

    /// The switch reads Pebble's value; a flip only asks for the change.
    private var request: Binding<Bool> {
        Binding(get: { isOn }, set: { wanted in if wanted != isOn { onChange(wanted) } })
    }

    public var body: some View {
        Toggle(isOn: request) {
            HStack(spacing: PebbleSpace.s2) {
                SettingLabel(title, detail: detail, needsFaceID: nextNeedsFaceID)
                if isBusy {
                    Spacer(minLength: 0)
                    ProgressView()
                        .accessibilityLabel(AppCopy.FaceID.waiting)
                }
            }
        }
        .tint(PebbleColor.accent)
        .disabled(isBusy || isDisabled)
        .sensoryFeedback(PebbleHaptics.selection, trigger: isOn)
    }
}

#if os(iOS)
#Preview("Guarded toggles") {
    @Previewable @State var web = false
    @Previewable @State var busy = false
    Form {
        GuardedToggle(
            SettingsCopy.Permissions.toolName("web"), detail: SettingsCopy.Permissions.toolNote("web"), isOn: web,
            faceID: .whenTurningOn, isBusy: busy
        ) { wanted in
            busy = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                web = wanted
                busy = false
            }
        }
        GuardedToggle(
            SettingsCopy.Appearance.followPointer, detail: SettingsCopy.Appearance.followPointerOffDetail, isOn: false,
            isDisabled: true
        ) { _ in }
    }
}
#endif
