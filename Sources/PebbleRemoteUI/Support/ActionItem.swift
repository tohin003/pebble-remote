/// One row of an ActionList: something Pebble keeps on the Mac (a shared window, a kept tool, a schedule, a paired
/// phone, a deleted chat) and the one thing the phone can do to it.
struct ActionItem: Identifiable, Hashable {
    let id: String
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    /// The button's words ("Revoke", "Remove", "Pause", "Restore").
    let actionTitle: String
    var actionSymbol: String? = nil
    var isDestructive = false
    /// A question to confirm first when the action can't be undone; nil acts at once.
    var confirmation: String? = nil
}
