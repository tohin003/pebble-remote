import SwiftUI

/// A setting's name with Pebble's explanation under it, for a `Toggle`, a `Picker` row, a `NavigationLink` or a plain
/// row in a `Form`. The explanation wraps (never truncated); the name keeps Pebble's words.
///
/// ```swift
/// Toggle(isOn: $on) { SettingLabel(SettingsCopy.Appearance.reduceMotion, detail: SettingsCopy.Appearance.reduceMotionDetail) }
/// ```
public struct SettingLabel: View {
    let title: String
    let detail: String?
    let systemImage: String?
    let needsFaceID: Bool

    /// - Parameter needsFaceID: shows the Face ID glyph after the name when the next change asks for Face ID.
    public init(_ title: String, detail: String? = nil, systemImage: String? = nil, needsFaceID: Bool = false) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.needsFaceID = needsFaceID
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(PebbleColor.accent)
                    .frame(minWidth: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s1 + 2) {
                    Text(verbatim: title)
                        .foregroundStyle(PebbleColor.text)
                    if needsFaceID {
                        Image(systemName: PebbleSymbol.faceID)
                            .imageScale(.small)
                            .foregroundStyle(PebbleColor.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(needsFaceID ? AppCopy.FaceID.asksFirst : "")
    }
}

#if os(iOS)
#Preview("Setting labels") {
    Form {
        Toggle(isOn: .constant(true)) {
            SettingLabel(SettingsCopy.Appearance.reduceMotion, detail: SettingsCopy.Appearance.reduceMotionDetail)
        }
        Toggle(isOn: .constant(false)) {
            SettingLabel(
                SettingsCopy.Permissions.toolName("web"), detail: SettingsCopy.Permissions.toolNote("web"),
                needsFaceID: true)
        }
        SettingLabel(SettingsCopy.Memory.enabled, detail: SettingsCopy.Memory.enabledDetail, systemImage: "brain")
    }
}
#endif
