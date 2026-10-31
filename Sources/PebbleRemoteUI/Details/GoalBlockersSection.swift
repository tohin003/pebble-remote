import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// What holds the goal up (GoalPanel.vue's Blockers table, DT-13), as `goal_get` lists it: Pebble's label, the kind,
/// the step it names, and the note or question words. A review's "Review" opens the waiting card itself over this
/// screen (the same card Reviews shows); a question waits in the conversation and on Reviews; anything else is in
/// Activity, where the task's steps are.
struct GoalBlockersSection: View {
    let goal: GoalRecord
    /// Review: the screen opens the waiting card (a section can't present a sheet of its own in a List).
    let review: (GoalBlocker) -> Void

    var body: some View {
        if !goal.blockerItems.isEmpty {
            Section(AppCopy.Goals.blockers) {
                ForEach(goal.blockerItems) { blocker in
                    row(blocker)
                }
            }
        }
    }

    private func row(_ blocker: GoalBlocker) -> some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(verbatim: blocker.label)
                Text(
                    verbatim: [AppCopy.Goals.blockerKind(blocker.kind), blocker.stepID.map(AppCopy.Goals.blockerStep)]
                        .compactMap { $0 }.joined(separator: " \u{00B7} ")
                )
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
                if let detail = blocker.detail {
                    Text(verbatim: detail)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.secondaryText)
                    if blocker.detailOrigin == "agent" {
                        Text(AppCopy.Goals.writtenByPebble)
                            .font(PebbleFont.meta)
                            .foregroundStyle(PebbleColor.mutedText)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            switch blocker.kind {
            case "approval":
                Button(AppCopy.Goals.review) { review(blocker) }
                    .buttonStyle(.borderless)
                    .frame(minHeight: PebbleSize.minTap, alignment: .leading)
                    .accessibilityHint(AppCopy.Goals.reviewHint)
            case "question":
                Text(AppCopy.Goals.answerInConversation)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            default:
                Text(AppCopy.Goals.inspectInActivity)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        }
    }

}

/// A waiting card opened from a goal's blocker: the card as Reviews shows it, with its own Approve (Face ID) and
/// Reject, over Details. Once it is decided it no longer waits, and the sheet says so.
struct ReviewCardSheet: View {
    let item: ReviewItem
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PebbleSpace.s4) {
                    if let current {
                        ReviewItemCard(item: current)
                    } else {
                        Text(AppCopy.Goals.reviewGone)
                            .font(PebbleFont.cardBody)
                            .foregroundStyle(PebbleColor.secondaryText)
                    }
                }
                .padding()
                .frame(maxWidth: PebbleSize.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(AppCopy.Goals.review)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.Common.done) { dismiss() }
                        .pebbleBarButton()
                }
            }
        }
    }

    /// The card while it still waits (the store drops it once it is decided, here or anywhere).
    private var current: ReviewItem? {
        for waiting in store.waiting {
            if case .review(let review) = waiting, review.id == item.id { return review }
        }
        return nil
    }
}
