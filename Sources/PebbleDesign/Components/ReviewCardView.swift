import PebbleProtocol
import SwiftUI

/// A card Pebble holds for the person's review: the most safety-critical reading in the app.
///
/// Top to bottom: what kind of step it is (symbol and Pebble's name for the kind), one plain sentence saying what
/// approving does, the exact thing in monospaced type (command, path, address; selectable, never truncated without a
/// "Show More"), the conversation it belongs to, then the decision: Pebble's "Don't Allow" and an approve button that
/// names the action ("Run Command") with the Face ID glyph, because approving asks for Face ID.
///
/// Content layer: a `PebbleCard` with the pending border. Never glass. While `isBusy`, both buttons are disabled and
/// a progress indicator shows; the card never claims success itself (the screen removes it when Pebble confirms).
public struct ReviewCardView: View {
    let kind: CardKind
    let title: String
    let detail: String?
    let conversation: String?
    let created: Date?
    let isBusy: Bool
    let approveLabel: String?
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var expanded = false

    /// - Parameters:
    ///   - title: one plain sentence: what approving does (Pebble's lead sentence, `ReviewCopy.lead...`).
    ///   - detail: the exact thing to approve, shown monospaced.
    ///   - conversation: the conversation's title, when the card is shown outside it (the Reviews tab).
    ///   - approveLabel: overrides the approve button's words (default: `AppCopy.Reviews.approve(kind)`).
    public init(
        kind: CardKind, title: String, detail: String?, conversation: String?, created: Date?, isBusy: Bool,
        approveLabel: String? = nil, onApprove: @escaping () -> Void, onReject: @escaping () -> Void
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.conversation = conversation
        self.created = created
        self.isBusy = isBusy
        self.approveLabel = approveLabel
        self.onApprove = onApprove
        self.onReject = onReject
    }

    private static let collapsedLines = 8

    public var body: some View {
        PebbleCard(emphasis: .pending) {
            header
            Text(verbatim: title)
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let detail, !detail.isEmpty {
                ExactDetail(text: detail, expanded: $expanded, collapsedLines: Self.collapsedLines)
            }
            if let conversation {
                Label(AppCopy.Reviews.inConversation(conversation), systemImage: PebbleSymbol.conversation)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.mutedText)
                    .lineLimit(1)
            }
            decision
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
            Label(ReviewCopy.kindLabel(kind), systemImage: PebbleSymbol.card(kind))
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.accent)
            Spacer(minLength: PebbleSpace.s2)
            if let created {
                Text(created, style: .relative)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.mutedText)
                    .monospacedDigit()
            }
        }
    }

    private var decision: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PebbleSpace.s3) {
                rejectButton
                Spacer(minLength: 0)
                approveButton
            }
            VStack(spacing: PebbleSpace.s2) {
                approveButton.frame(maxWidth: .infinity)
                rejectButton.frame(maxWidth: .infinity)
            }
        }
        .disabled(isBusy)
        .overlay {
            if isBusy {
                ProgressView()
                    .accessibilityLabel(AppCopy.Reviews.working)
            }
        }
    }

    private var approveButton: some View {
        Button(action: onApprove) {
            Label(approveLabel ?? AppCopy.Reviews.approve(kind), systemImage: PebbleSymbol.approve)
        }
        .buttonStyle(.pebblePrimary)
        .accessibilityHint(AppCopy.Reviews.approveHint)
    }

    private var rejectButton: some View {
        Button(AppCopy.Reviews.reject, action: onReject)
            .buttonStyle(.pebbleSecondary)
            .accessibilityHint(AppCopy.Reviews.rejectHint)
    }
}

/// The exact thing to approve: monospaced on Pebble's code colour, selectable, collapsed after a few lines with a
/// "Show More" (never silently cut).
struct ExactDetail: View {
    let text: String
    @Binding var expanded: Bool
    let collapsedLines: Int

    private var isLong: Bool {
        text.count > 320 || text.split(separator: "\n", omittingEmptySubsequences: false).count > collapsedLines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Text(verbatim: text)
                .font(PebbleFont.cardDetail)
                .foregroundStyle(PebbleColor.text)
                .lineLimit(expanded || !isLong ? nil : collapsedLines)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PebbleSpace.s3)
                .background(PebbleColor.code, in: PebbleShapes.inset)
                .overlay { PebbleShapes.inset.stroke(PebbleColor.line, lineWidth: 1) }
                .accessibilityLabel(AppCopy.Reviews.exactDetail)
                // A path is read file first ("ThemeToggle.tsx in src/settings"); anything else as it is.
                .accessibilityValue(AppCopy.Paths.spoken(text) ?? text)
                .accessibilityHint(AppCopy.Accessibility.exactDetailHint)
            if isLong {
                Button(expanded ? AppCopy.Reviews.showLess : AppCopy.Reviews.showMore) {
                    expanded.toggle()
                }
                .font(PebbleFont.meta)
                .tint(PebbleColor.accent)
                .frame(minHeight: PebbleSize.minTap)
            }
        }
    }
}

#if os(iOS)
#Preview("Review cards") {
    ScrollView {
        VStack(spacing: PebbleSpace.s3) {
            ReviewCardView(
                kind: .command, title: ReviewCopy.leadCommand(writable: false), detail: "npm test",
                conversation: "Tidy the test suite", created: .now.addingTimeInterval(-90), isBusy: false,
                onApprove: {}, onReject: {})
            ReviewCardView(
                kind: .edit, title: ReviewCopy.leadEdit(newFile: false), detail: "src/auth/login.ts",
                conversation: nil, created: nil, isBusy: true, onApprove: {}, onReject: {})
            ReviewCardView(
                kind: .browserGrant, title: ReviewCopy.leadBrowserGrant(window: false), detail: "youtube.com",
                conversation: "Play the lecture", created: .now, isBusy: false, onApprove: {}, onReject: {})
        }
        .padding()
    }
}
#endif
