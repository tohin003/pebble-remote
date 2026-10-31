import Foundation
import SwiftUI

/// Links tapped inside the app's own views. Pebble's replies show Markdown links, and a reply is text a model wrote,
/// maybe from a web page Pebble read. So only web links leave the app (in the browser). A `pebble-remote://` link in a
/// reply never acts (a pairing link there would open the pairing sheet with addresses and a key the page chose), and
/// other apps' links (Shortcuts, phone, messages, FaceTime) are not followed either (security review 2026-10-30,
/// S-03). Links the system opens from outside the app still arrive through `onOpenURL`, and a pairing link from there
/// still asks the person to confirm.
enum InAppLinks {
    static func opensInBrowser(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return url.host() != nil
    }

    static func handle(_ url: URL) -> OpenURLAction.Result {
        opensInBrowser(url) ? .systemAction : .discarded
    }
}
