import SwiftUI

/// How this iPhone reaches the Mac and the measured round trip: "Local network · 6 ms", "Tailscale · 41 ms".
/// Latency is visible because it is measured; a missing measurement shows only the route.
///
/// Map the store's `RouteKind` onto `Route` in the screen (this module doesn't see Kit types).
public struct RouteBadge: View {
    public enum Route: String, Sendable, Hashable, CaseIterable {
        case lan, tailscale, other, demo
    }

    let route: Route
    let roundTripMilliseconds: Double?
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(route: Route, roundTripMilliseconds: Double?) {
        self.route = route
        self.roundTripMilliseconds = roundTripMilliseconds
    }

    public var body: some View {
        // One line in a capsule. At accessibility sizes that line is wider than the phone, so the words wrap, in a
        // rounded rectangle (a capsule's round ends would cut into a second line).
        let wraps = typeSize.isAccessibilitySize
        // The glyph and the words side by side, drawn as they are: as a Label inside the overview's list row, the
        // words were left out and the badge showed an empty pill with only its glyph (UX audit U-02).
        HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s1 + 2) {
            Image(systemName: symbol)
            Text(words)
                .lineLimit(wraps ? nil : 1)
                .fixedSize(horizontal: !wraps, vertical: true)
                .layoutPriority(1)
        }
        .fixedSize(horizontal: !wraps, vertical: true)
        .font(PebbleFont.chip)
        .foregroundStyle(PebbleColor.secondaryText)
        .padding(.horizontal, PebbleSpace.s2 + 2)
        .padding(.vertical, PebbleSpace.s1)
        .background(
            PebbleColor.hover,
            in: wraps ? AnyShape(RoundedRectangle(cornerRadius: PebbleRadius.md)) : AnyShape(Capsule()))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppCopy.Connection.route)
        .accessibilityValue(
            roundTripMilliseconds.map { "\(name), \(AppCopy.Connection.roundTrip) \(AppCopy.Connection.milliseconds($0))" }
                ?? name)
    }

    /// The route, and the round trip when it was measured ("Local network · 6 ms").
    var words: String {
        if let ms = roundTripMilliseconds, ms.isFinite, ms >= 0 { return "\(name) · \(AppCopy.Connection.milliseconds(ms))" }
        return name
    }

    var name: String {
        switch route {
        case .lan: AppCopy.Connection.routeLocal
        case .tailscale: AppCopy.Connection.routeTailscale
        case .other: AppCopy.Connection.routeOther
        case .demo: AppCopy.Connection.routeDemo
        }
    }

    var symbol: String {
        switch route {
        case .lan: PebbleSymbol.routeLocal
        case .tailscale: PebbleSymbol.routeTailscale
        case .other: PebbleSymbol.routeOther
        case .demo: PebbleSymbol.routeDemo
        }
    }
}

#if os(iOS)
#Preview("Route badges") {
    VStack(alignment: .leading) {
        RouteBadge(route: .lan, roundTripMilliseconds: 6.2)
        RouteBadge(route: .tailscale, roundTripMilliseconds: 41)
        RouteBadge(route: .other, roundTripMilliseconds: nil)
        RouteBadge(route: .demo, roundTripMilliseconds: nil)
    }
    .padding()
}
#endif
