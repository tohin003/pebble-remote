import PebbleDesign
import SwiftUI

/// A web search (WorkCard.vue): its queries, then each site it used, by host name only.
struct WebDetails: View {
    let queries: [String]
    let sites: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            if !queries.isEmpty {
                Text(verbatim: queries.joined(separator: " \u{00B7} "))
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.text)
            }
            if !sites.isEmpty {
                ChipFlow {
                    ForEach(sites, id: \.self) { site in
                        ViewChip(site)
                    }
                }
            }
        }
    }
}
