import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Photos, files and web pages waiting to go with the conversation's next message, each with a small preview (a web
/// page shows "Read: " and its site, as Pebble's chip does) and Remove.
struct PendingAttachmentsBar: View {
    let attachments: [AttachmentRef]
    /// Removes one; nil hides Remove (the bridge doesn't offer it).
    let remove: ((AttachmentRef) -> Void)?
    @ScaledMetric(relativeTo: .body) private var thumbnail = 36

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: PebbleSpace.s2) {
                ForEach(attachments) { attachment in
                    HStack(spacing: PebbleSpace.s2) {
                        AttachmentThumbnail(attachment: attachment)
                            .frame(width: thumbnail, height: thumbnail)
                        Text(attachment.kind == "url" ? AppCopy.WebSource.chip(attachment.name) : attachment.name)
                            .font(PebbleFont.meta)
                            .lineLimit(1)
                        if let remove {
                            // The 44 pt region on the label: a frame outside a borderless button didn't widen the tap
                            // (the re-check's U-64, a 17 pt target).
                            Button { remove(attachment) } label: {
                                Image(systemName: "xmark.circle.fill").tapTarget()
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(AppCopy.Control.remove)
                        }
                    }
                    // Insets that keep the square thumbnail inside the capsule's round end, and the name off the
                    // trailing edge when there is no Remove button to pad it.
                    .padding(.leading, PebbleSpace.s3)
                    .padding(.trailing, remove == nil ? PebbleSpace.s3 : 0)
                    .frame(minHeight: PebbleSize.minTap)
                    .background(.quaternary, in: .capsule)
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }
}
