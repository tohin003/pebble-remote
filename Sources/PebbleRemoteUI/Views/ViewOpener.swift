import PebbleProtocol
import SwiftUI

/// Opens Pebble's views from a screen that stays put (the transcript, Reviews), not from a row of a lazy stack, which
/// can be unloaded while what it opened is still on screen. A form opens in its sheet; any other view full screen.
@Observable
final class ViewOpener {
    var opened: PebbleArtifact?
    var answering: PebbleArtifact?

    func open(_ artifact: PebbleArtifact) {
        if artifact.kind == "form", artifact.form != nil {
            answering = artifact
        } else {
            opened = artifact
        }
    }
}
