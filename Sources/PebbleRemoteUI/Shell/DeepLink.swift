import Foundation
import PebbleRemoteKit

/// A `pebble-remote://` link the system opened: a pairing link (a scanned code or a tapped link), a conversation
/// (`pebble-remote://chat/<id>`, from an alert later), or the Reviews tab (`pebble-remote://reviews`).
enum DeepLink: Equatable {
    case pair(PairingLink)
    case chat(ChatID)
    case reviews

    init?(url: URL) {
        guard url.scheme?.lowercased() == "pebble-remote" else { return nil }
        switch url.host()?.lowercased() {
        case "pair":
            guard let link = PairingLink(url: url) else { return nil }
            self = .pair(link)
        case "chat":
            // One path segment, decoded once: pebble-remote://chat/<percent-encoded id>
            let id = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty, !id.contains("/") else { return nil }
            self = .chat(id)
        case "reviews":
            self = .reviews
        default:
            return nil
        }
    }
}
