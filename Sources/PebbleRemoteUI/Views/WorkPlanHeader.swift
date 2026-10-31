import PebbleDesign
import PebbleProtocol
import SwiftUI

/// The work view's header (WorkView.vue): a ring from the plan's steps, the run's state and time and the plan's
/// progress in words, and the plan's steps a tap away. The status line stays the one live region (spec rule 6), so this
/// updates in place, unannounced.
struct WorkPlanHeader: View {
    let plan: WorkPlan?
    /// Pebble's run state ("running", "completed" …).
    let state: String?
    /// Pebble's own count; nil in the transcript, where the run bar already shows the time.
    var seconds: Double? = nil
    /// While the run works (Details): where its time counts from, so the time runs on each second from the run bar's
    /// start instead of standing at Pebble's last count (U-58).
    var since: Date? = nil
    let isLive: Bool
    @State private var showsPlan = false

    var body: some View {
        if let plan {
            DisclosureGroup(isExpanded: $showsPlan) {
                PlanRail(steps: plan.steps)
                    .padding(.top, PebbleSpace.s1)
            } label: {
                line
            }
            .accessibilityHint(AppCopy.Views.showsPlan)
        } else {
            line
        }
    }

    private var line: some View {
        HStack(alignment: .center, spacing: PebbleSpace.s2) {
            PlanRing(plan: plan, isLive: isLive, word: AppCopy.Views.runWord(state))
            if isLive, let since {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    // Whole seconds, as the run bar shows them.
                    words(seconds: context.date.timeIntervalSince(since).rounded(.down))
                }
            } else {
                words(seconds: seconds)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func words(seconds: Double?) -> some View {
        Text(AppCopy.Views.headerLine(state: state, seconds: seconds, plan: plan))
            .font(PebbleFont.cardBody)
            .foregroundStyle(PebbleColor.secondaryText)
    }
}
