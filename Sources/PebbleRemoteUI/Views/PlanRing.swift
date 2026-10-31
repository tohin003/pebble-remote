import PebbleDesign
import PebbleProtocol
import SwiftUI

/// The header's ring (WorkView.vue): the share of the plan's steps done; without a plan, an open ring while the run
/// works and a full one once it settled. Its words are read out; it never moves under Reduce Motion (it doesn't move).
struct PlanRing: View {
    let plan: WorkPlan?
    let isLive: Bool
    let word: String
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 20

    var body: some View {
        let share: Double = plan.map { Double($0.done) / Double(max(1, $0.total)) } ?? (isLive ? 0.25 : 1)
        ZStack {
            Circle()
                .stroke(PebbleColor.line, lineWidth: 3)
            Circle()
                .trim(from: 0, to: share)
                .stroke(PebbleColor.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(plan.map { AppCopy.Views.planStepsDone(done: $0.done, total: $0.total) } ?? (isLive ? AppCopy.Views.inProgress : word))
    }
}
