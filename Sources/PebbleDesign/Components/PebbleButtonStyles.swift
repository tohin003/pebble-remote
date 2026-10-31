import SwiftUI

// Button styles. Two layers, two families (docs/DESIGN.md, "Liquid Glass"):
// - Content (cards, lists, empty states): system bordered styles in Pebble's sage, never glass.
// - The navigation and control layer (toolbars, the run bar, floating controls): Liquid Glass, tinted only for the one
//   primary action. Glass never sits on glass, and never on a card.
// Labels on the sage fill use `onAccent`, so the text keeps 4.5:1 in both appearances (iOS would draw white, which
// fails on the dark appearance's light sage).

/// The one primary action in a piece of content: Approve, Send Answer, Pair. Sage fill, `onAccent` label, capsule.
public struct PebblePrimaryButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(PebbleColor.accent)
    }
}

/// A second choice next to the primary one (Don't Allow, Not Now): a quiet tinted fill, sage-on-soft.
public struct PebbleSecondaryButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.text)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(PebbleColor.secondaryText)
    }
}

/// An action that stops or removes something (Stop Everything, Forget This Mac). Use with `role: .destructive`
/// and a confirmation where it can't be undone.
public struct PebbleDestructiveButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role ?? .destructive, action: configuration.trigger) {
            configuration.label
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.danger)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(PebbleColor.danger)
    }
}

/// A control-layer button: plain Liquid Glass (Stop and Pause in the run bar, floating controls).
public struct PebbleGlassButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .frame(minWidth: PebbleSize.minTap - 12, minHeight: PebbleSize.minTap - 12)
        }
        .buttonStyle(.glass)
    }
}

/// The one primary action in the control layer (Send in the composer): sage-tinted Liquid Glass.
public struct PebbleGlassProminentButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .foregroundStyle(PebbleColor.onAccent)
                .frame(minWidth: PebbleSize.minTap - 12, minHeight: PebbleSize.minTap - 12)
        }
        .buttonStyle(.glassProminent)
        .tint(PebbleColor.accent)
    }
}

extension PrimitiveButtonStyle where Self == PebblePrimaryButtonStyle {
    /// Content layer: the one primary action (sage fill).
    public static var pebblePrimary: PebblePrimaryButtonStyle { PebblePrimaryButtonStyle() }
}

extension PrimitiveButtonStyle where Self == PebbleSecondaryButtonStyle {
    /// Content layer: the second choice.
    public static var pebbleSecondary: PebbleSecondaryButtonStyle { PebbleSecondaryButtonStyle() }
}

extension PrimitiveButtonStyle where Self == PebbleDestructiveButtonStyle {
    /// Content layer: stopping or removing something.
    public static var pebbleDestructive: PebbleDestructiveButtonStyle { PebbleDestructiveButtonStyle() }
}

extension PrimitiveButtonStyle where Self == PebbleGlassButtonStyle {
    /// Control layer only: plain glass.
    public static var pebbleGlass: PebbleGlassButtonStyle { PebbleGlassButtonStyle() }
}

extension PrimitiveButtonStyle where Self == PebbleGlassProminentButtonStyle {
    /// Control layer only: the one tinted glass action.
    public static var pebbleGlassProminent: PebbleGlassProminentButtonStyle { PebbleGlassProminentButtonStyle() }
}

extension View {
    /// A toolbar button that isn't the screen's one primary action (Done or Cancel in a sheet): the system's primary
    /// label colour on its glass. The app's sage tint, which every bar button would otherwise take from the root, fails
    /// contrast on glass (the UX audit's accessibility rows) and isn't for buttons other than the primary action.
    public func pebbleBarButton() -> some View {
        tint(.primary)
    }
}

#if os(iOS)
#Preview("Buttons") {
    VStack(spacing: PebbleSpace.s4) {
        HStack {
            Button(AppCopy.Reviews.reject) {}.buttonStyle(.pebbleSecondary)
            Button(AppCopy.Reviews.approve(.command), systemImage: PebbleSymbol.approve) {}.buttonStyle(.pebblePrimary)
        }
        Button(AppCopy.Control.stopEverything, systemImage: PebbleSymbol.stopEverything) {}.buttonStyle(.pebbleDestructive)
        HStack {
            Button(AppCopy.Conversation.stop, systemImage: PebbleSymbol.stop) {}
                .buttonStyle(.pebbleGlass)
                .labelStyle(.iconOnly)
            Button(AppCopy.Conversation.send, systemImage: PebbleSymbol.send) {}
                .buttonStyle(.pebbleGlassProminent)
                .labelStyle(.iconOnly)
        }
    }
    .padding()
}
#endif
