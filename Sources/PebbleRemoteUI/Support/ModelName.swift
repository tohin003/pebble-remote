import PebbleRemoteKit

extension RemoteStore {
    /// The model Pebble uses now, by the name Pebble's model list gives it ("GPT-5.1", "Qwen 3.5 9B"), so one model has
    /// one name on every screen: the chip, its menu and Control's Model row (UX audit U-26). Before the list is read,
    /// Pebble's own model name.
    var currentModelName: String? {
        if let id = currentModelID, let choice = models.first(where: { $0.id == id }), !choice.name.isEmpty {
            return choice.name
        }
        return pebble?.modelName
    }
}
