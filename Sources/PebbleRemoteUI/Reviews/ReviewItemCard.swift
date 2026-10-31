import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A card Pebble holds for review, wired to the store: Approve (the store's elevated call asks for Face ID) and Reject.
/// Under it, what the card holds ("View Diff", "View the Check", "Technical Details" or "Details") and, on a Shell or
/// file card that offers it, "Always Allow" (App.vue `grantAndApprove`: the card's hosts and folders allowed from now on,
/// then the card approved once; Face ID). Used inline in the transcript and on the Reviews tab.
struct ReviewItemCard: View {
    let item: ReviewItem
    /// The chat's title above the card (the Reviews tab lists cards from every chat).
    var showsConversation = false
    /// Opens what the card holds on the screen that shows it.
    var present: RecoveryPresenter? = nil
    @Environment(RemoteStore.self) private var store
    @State private var isBusy = false
    @State private var approvals = 0
    @State private var rejections = 0

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            ReviewCardView(
                kind: item.kind, title: item.title, detail: item.detail,
                conversation: showsConversation ? item.chatTitle : nil, created: item.created, isBusy: isBusy,
                onApprove: approve, onReject: reject
            )
            let extras = CardExtras(item: item, offers: store.bridgeOffers, canPresent: present != nil)
            if extras.details != nil || extras.alwaysAllow {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PebbleSpace.s3) { extraButtons(extras) }
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) { extraButtons(extras) }
                }
                .disabled(isBusy)
            }
        }
        .sensoryFeedback(PebbleHaptics.approved, trigger: approvals)
        .sensoryFeedback(PebbleHaptics.rejected, trigger: rejections)
    }

    @ViewBuilder
    private func extraButtons(_ extras: CardExtras) -> some View {
        if let details = extras.details {
            Button {
                present?(.cardDetails(item))
            } label: {
                Label(details, systemImage: "doc.text.magnifyingglass")
                    .tapTarget(alignment: .leading)
            }
            .buttonStyle(.borderless)
            .tint(PebbleColor.accent)
        }
        if extras.alwaysAllow {
            Button(action: alwaysAllow) {
                Label(RecoveryCopy.AlwaysAllow.button, systemImage: PebbleSymbol.faceID)
            }
            .buttonStyle(.pebbleSecondary)
            .accessibilityHint(RecoveryCopy.AlwaysAllow.hint)
        }
    }

    private func approve() {
        run {
            try await store.approve(item)
            approvals += 1
        }
    }

    private func reject() {
        run {
            try await store.reject(item)
            rejections += 1
        }
    }

    private func alwaysAllow() {
        run {
            try await store.alwaysAllow(item)
            approvals += 1
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            await store.attempt(work)
            isBusy = false
        }
    }
}

/// What shows under a review card: the button to what it holds, and "Always allow" where Pebble offers it.
struct CardExtras: Equatable {
    /// The details button's words ("View Diff", "View the Check", "Technical Details", "Details"), when there are some.
    var details: String?
    var alwaysAllow = false

    init(item: ReviewItem, offers: (String) -> Bool, canPresent: Bool) {
        if canPresent { details = CardDetailCopy.detail(kind: item.kind, payload: item.payload)?.button }
        alwaysAllow = item.offersAlwaysAllow && offers("shell_grant_add") && offers("approve")
    }
}
