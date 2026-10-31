import PebbleRemoteKit

/// Which conversation's Details to show, on which task and tab, for `sheet(item:)`. The run is nil for a conversation
/// that has no task yet (Details then lists what it has, such as Tools).
struct RunDetailsRequest: Identifiable, Hashable {
    let chatID: ChatID
    let runID: RunID?
    var tab: DetailsTab = .activity
    var id: String { "\(chatID)/\(runID ?? "-")/\(tab.rawValue)" }
}
