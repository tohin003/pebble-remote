import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// One card of the work view (WorkCard.vue), calm and compact as the Mac draws it: one line by default (what, and its
/// state in words), its details a tap away. Display only (pebble-ui-spec v1, rule 4): its one control shows what the
/// card already holds; nothing on it acts. The transcript draws it boxed; Details › Activity draws it as a row.
struct WorkCardView: View {
    let card: WorkCard<RunActivityItem>
    let runIsLive: Bool
    var showsTime = false
    var isBoxed = true
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let disclosure = DisclosureGroup(isExpanded: $isExpanded.animation(reduceMotion ? nil : PebbleMotion.standard)) {
            WorkCardDetails(card: card, runIsLive: runIsLive)
                .padding(.top, PebbleSpace.s2)
        } label: {
            WorkCardLine(card: card, runIsLive: runIsLive, showsTime: showsTime)
        }
        .accessibilityHint(isExpanded ? AppCopy.Views.hideDetails : AppCopy.Views.showDetails)
        if isBoxed {
            disclosure
                .padding(.horizontal, PebbleSpace.s3)
                .padding(.vertical, PebbleSpace.s2)
                .background(PebbleColor.panel, in: .rect(cornerRadius: PebbleRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: PebbleRadius.md)
                        .stroke(card.hasFailed ? PebbleColor.dangerLine : PebbleColor.line, lineWidth: 1)
                }
        } else {
            disclosure
        }
    }
}
