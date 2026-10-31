import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A row in Settings › Across Conversations (a schedule, a schedule's notice or a shared window) that opens its own
/// conversation's Details on Tools, the one home for its controls (the lead's IA decision, 2026-10-31 02:30). It acts on
/// nothing in place.
struct ToolsLinkRow<Content: View>: View {
    let chatID: ChatID
    @ViewBuilder let content: Content
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            router.showDetails(DetailsOpening.tools(of: chatID))
        } label: {
            HStack(spacing: PebbleSpace.s3) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .contentShape(.rect)
        }
        .accessibilityHint(AppCopy.Details.opensTools)
    }
}
