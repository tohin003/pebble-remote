import SwiftUI

/// The four tabs, in the order the tab bar shows them.
enum AppTab: String, Hashable, CaseIterable {
    case pebble, chats, reviews, control
}

extension EnvironmentValues {
    /// The tab a screen sits in (`MainTabs` sets it on each tab). Tabs keep their screens while hidden, so one
    /// conversation can be open on two tabs at once; a hand-off meant for the tab on screen checks this.
    @Entry var appTab: AppTab?
}
