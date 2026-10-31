import CoreGraphics

/// Pebble's 4-point rhythm (tokens.css `--space-1` ... `--space-6`, Phase 22). Use these inside PebbleDesign's own
/// components and for gaps the system does not own. Lists, Forms, toolbars and stacks of system controls keep the
/// system's spacing: leave the length out (`.padding()`, `VStack { }`), as Apple's HIG asks.
nonisolated public enum PebbleSpace {
    /// 4 pt: a hairline gap, an icon to its text inside a chip.
    public static let s1: CGFloat = 4
    /// 8 pt: between related lines in a card.
    public static let s2: CGFloat = 8
    /// 12 pt: between groups inside a card; between cards.
    public static let s3: CGFloat = 12
    /// 16 pt: a card's inner padding.
    public static let s4: CGFloat = 16
    /// 24 pt: between sections of a custom screen.
    public static let s5: CGFloat = 24
    /// 32 pt: around a hero (the avatar on the Pebble tab).
    public static let s6: CGFloat = 32
}

/// Pebble's three radii, "tighter inside, softer outside" (tokens.css `--radius-sm/md/lg`: 6, 8, 12 px), mapped onto
/// iOS 26's rounder geometry. Next to a screen or sheet edge, prefer `ConcentricRectangle` (see `PebbleShape.card`).
nonisolated public enum PebbleRadius {
    /// Code blocks and inline fills inside a card (Pebble 6 px).
    public static let sm: CGFloat = 8
    /// Rows and small controls inside a card (Pebble 8 px).
    public static let md: CGFloat = 12
    /// Cards (Pebble 12 px), and the floor for concentric card corners.
    public static let lg: CGFloat = 18
    /// Message bubbles. The trailing bottom corner of your own bubble is `bubbleTail` (Pebble's 13/13/3/13 px).
    public static let bubble: CGFloat = 20
    public static let bubbleTail: CGFloat = 6
}

/// Sizes that carry a rule.
nonisolated public enum PebbleSize {
    /// Apple's minimum hit region on iOS. Every tappable PebbleDesign component keeps at least this.
    public static let minTap: CGFloat = 44
    /// The avatar on the Pebble tab.
    public static let avatarHero: CGFloat = 148
    /// The avatar in an empty state.
    public static let avatarEmpty: CGFloat = 96
    /// The avatar in a run bar or status line.
    public static let avatarInline: CGFloat = 28
    /// Below this the avatar draws without glass, highlight, shimmer and ping, with a thicker rim (Avatar.vue's 64 px).
    public static let avatarFineDetail: CGFloat = 64
    /// A readable line length for long text on wide screens.
    public static let readableWidth: CGFloat = 680
}
