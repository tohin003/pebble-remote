import PebbleDesign
import SwiftUI

/// One row of an ActionList: what it is, a detail line, and its action button.
struct ActionRow: View {
    let item: ActionItem
    let isWorking: Bool
    let act: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                if let symbol = item.symbol {
                    Label(item.title, systemImage: symbol)
                } else {
                    Text(item.title)
                }
                if let detail = item.detail {
                    Text(detail)
                        .font(PebbleFont.meta)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isWorking {
                ProgressView()
            } else {
                Button(role: item.isDestructive ? .destructive : nil, action: act) {
                    Text(item.actionTitle)
                        .tapTarget()
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
