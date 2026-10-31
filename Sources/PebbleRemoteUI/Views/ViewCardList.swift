import PebbleDesign
import PebbleProtocol
import SwiftUI

/// The views a run drew, as cards in the transcript. A form opens in its sheet; every other view opens full screen.
struct ViewCardList: View {
    let views: [PebbleArtifact]
    /// The screen's opener, when the screen has one (`viewOpening()`); else the list opens them itself.
    @Environment(ViewOpener.self) private var opener: ViewOpener?
    @State private var opened: PebbleArtifact?
    @State private var answering: PebbleArtifact?

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            ForEach(views) { view in
                ViewCard(artifact: view) { open(view) }
            }
        }
        .sheet(item: $answering) { form in
            FormSheet(artifact: form)
                .lockCover()
        }
        .viewCover(item: $opened)
    }

    private func open(_ view: PebbleArtifact) {
        if let opener {
            opener.open(view)
        } else if view.kind == "form", view.form != nil {
            answering = view
        } else {
            opened = view
        }
    }
}
