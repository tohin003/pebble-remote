import PebbleProtocol
import SwiftUI

/// Puts a `ViewOpener` in the environment and presents what it opens.
struct ViewOpening: ViewModifier {
    @State private var opener = ViewOpener()

    func body(content: Content) -> some View {
        content
            .environment(opener)
            .sheet(item: $opener.answering) { form in
                FormSheet(artifact: form)
                    .lockCover()
            }
            .viewCover(item: $opener.opened)
    }
}

extension View {
    /// Rows below open Pebble's views through this screen (lane G).
    func viewOpening() -> some View {
        modifier(ViewOpening())
    }
}
