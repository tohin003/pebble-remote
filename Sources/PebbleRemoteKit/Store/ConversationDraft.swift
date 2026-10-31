import Foundation
import Observation

/// A new conversation that isn't on the Mac yet: what "New conversation" opens on the phone. It holds where the
/// conversation will start (Companion or a project) and the photos, files and web pages to send with its first
/// message. Pebble makes the conversation only when that message is sent (`RemoteStore.send(_:from:)`), so a draft
/// left unsent leaves nothing on the Mac.
///
/// The store keeps each draft by `id` (`RemoteStore.draft(_:)`), so a screen pushed by id finds it again.
@MainActor
@Observable
public final class ConversationDraft: Identifiable {
    public nonisolated let id: String
    /// Where the conversation starts: a project folder, or nil for Companion.
    public internal(set) var place: ProjectRef?
    /// What goes with the first message, kept on this phone until then.
    public internal(set) var pending: [DraftAttachment] = []
    /// The conversation on the Mac, once Pebble made it. A send that made it and then failed (a refused folder, a photo
    /// Pebble didn't take, the message itself) leaves it here, and the next send continues in it.
    public internal(set) var chatID: ChatID?
    /// The first message went through: the screen shows the conversation now.
    public internal(set) var isSent = false

    /// Where the made conversation is on the Mac (`chatID`'s folder), when it was made before the person chose
    /// another place.
    @ObservationIgnored var madeIn: String?

    init(id: String = "draft-" + UUID().uuidString, place: ProjectRef?) {
        self.id = id
        self.place = place
    }

    /// Where the conversation starts, as the screens name it: the project's folder name, or nil for Companion.
    public var placeName: String? { place?.name }
}
