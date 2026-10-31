import PebbleProtocol
import SwiftUI

/// The permission mode as a chip: Pebble's name for the mode ("Ask for approval") with its symbol. Full access's symbol
/// reads in Pebble's danger colour (in content its words too), so the widest mode is never mistaken for the default.
/// Wrap it in a Button or Menu to make it tappable; the chip keeps a 44 pt hit region. VoiceOver: "Permissions: Ask for
/// approval".
///
/// The chip says its mode in words next to the symbol, in a toolbar too (the UX audit's U-01). It is drawn as a symbol
/// and a text side by side, not as a `Label`: an iOS 26 toolbar draws any Label in it as its icon alone, whatever its
/// label style (the re-check's r01-012). At accessibility text sizes the words give way, as a navigation bar has no room
/// for them there; the VoiceOver label and the large content viewer still say them.
///
/// In a toolbar (`onGlass`) the chip has no fill of its own and its words are the system's vibrant `.primary`, with the
/// mode's colour on the symbol (DESIGN §2.1: text on glass uses `.primary`). Sage words on the `soft` fill read faint
/// once the toolbar's glass lightened the fill in dark mode (the re-check's U-65). In content it is a soft capsule with
/// its words in the mode's colour.
public struct ModeChip: View {
    let mode: PermissionMode
    let onGlass: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(mode: PermissionMode, onGlass: Bool = false) {
        self.mode = mode
        self.onGlass = onGlass
    }

    public var body: some View {
        let tint = mode == .full ? PebbleColor.danger : PebbleColor.accent
        HStack(spacing: PebbleSpace.s1) {
            Image(systemName: PebbleSymbol.mode(mode))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            if !typeSize.isAccessibilitySize {
                Text(verbatim: mode.copy.name)
                    .foregroundStyle(onGlass ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .font(PebbleFont.chip)
        .padding(.horizontal, onGlass ? 0 : PebbleSpace.s3)
        .padding(.vertical, onGlass ? 0 : PebbleSpace.s2 - 2)
        .background(onGlass ? Color.clear : mode == .full ? PebbleColor.hover : PebbleColor.soft, in: .capsule)
        .frame(minHeight: PebbleSize.minTap)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppCopy.Control.permissionsLabel(mode))
        .accessibilityShowsLargeContentViewer {
            Label(mode.copy.name, systemImage: PebbleSymbol.mode(mode))
        }
    }
}

#if os(iOS)
#Preview("Mode chips") {
    VStack(alignment: .leading) {
        ForEach(ModeCopy.order, id: \.self) { ModeChip(mode: $0) }
        ForEach(ModeCopy.order, id: \.self) { ModeChip(mode: $0, onGlass: true) }
    }
    .padding()
}
#endif
