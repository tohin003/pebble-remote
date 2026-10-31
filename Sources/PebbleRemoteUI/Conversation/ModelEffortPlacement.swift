import SwiftUI

/// Where a conversation (or a new one) puts Pebble's model and effort: chips above the composer, or, at accessibility
/// text sizes, the ⋯ menu. Decided once by the screen, from its own text size, and handed to both the bottom bar and the
/// menu, so exactly one of them shows the two (the re-check's U-52). A toolbar caps the text size of what it holds, so
/// a menu that decided for itself saw a standard size while the bottom bar saw an accessibility size: the chips went and
/// the menu never took them.
enum ModelEffortPlacement: Hashable {
    case chips
    case menu

    init(textSize: DynamicTypeSize) {
        self = textSize.isAccessibilitySize ? .menu : .chips
    }

    /// The chips above the composer.
    var showsChips: Bool { self == .chips }

    /// The Model and Effort submenus in the ⋯ menu.
    var showsInMenu: Bool { self == .menu }
}
