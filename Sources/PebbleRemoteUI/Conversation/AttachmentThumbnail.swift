import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// An attachment's small preview (Pebble's JPEG for an image), or a symbol for its kind.
struct AttachmentThumbnail: View {
    let attachment: AttachmentRef

    var body: some View {
        if let data = attachment.preview, let image = MacScreenCapture.decode(data) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .clipShape(.rect(cornerRadius: PebbleRadius.sm))
        } else {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var symbol: String {
        switch attachment.kind {
        case "image": "photo"
        case "spreadsheet": "tablecells"
        case "archive": "doc.zipper"
        case "text": "doc.text"
        case "url": "globe"
        default: "doc"
        }
    }
}
