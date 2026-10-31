import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// One step in Details › Activity, as Pebble's step list shows it (ThinkingDisclosure.vue): its mark, its name with
/// what it took, when it happened in the run ("+3.2 s"), and its own words under it. Long words fold behind Show More.
struct ActivityStepRow: View {
    let item: RunActivityItem
    let runIsLive: Bool
    @State private var showsAll = false

    var body: some View {
        // Lane G: a step Pebble drew as a card shows its card (pebble-ui-spec v1), one line with its details a tap away.
        if let card = WorkCardWords.card(for: item) {
            WorkCardView(card: card, runIsLive: runIsLive, showsTime: true, isBoxed: false)
        } else {
            plainStep
        }
    }

    /// The step as Pebble's step list shows it, when Pebble drew no card for it.
    @ViewBuilder private var plainStep: some View {
        let phase = StepPhase(status: item.status, runIsLive: runIsLive)
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s3) {
                Image(systemName: Self.symbol(phase, activity: item.activity))
                    .foregroundStyle(phase == .failed ? AnyShapeStyle(PebbleColor.danger) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                StepLine(
                    name: phase == .running ? item.label : AppCopy.Details.stepName(item.label, took: item.duration),
                    time: AppCopy.Details.offset(item.at))
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(phase.word)
            if let detail = item.detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(PebbleFont.cardDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(showsAll ? nil : 3)
                    .textSelection(.enabled)
                    .padding(.leading, Self.indent)
                if Self.isLong(detail) {
                    Button {
                        showsAll.toggle()
                    } label: {
                        Text(showsAll ? AppCopy.Details.showLess : AppCopy.Details.showMore)
                            .font(PebbleFont.meta)
                            .tapTarget(alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, Self.indent)
                }
            }
            if item.hasUnreadableView {  // lane G: a view this version can't draw (spec rule 1)
                Label(AppCopy.Views.updateTheApp, systemImage: ViewSymbol.update)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Self.indent)
            }
        }
    }

    /// Lines under the mark start where the name does.
    static let indent: CGFloat = 28

    /// Words that three lines may not hold.
    static func isLong(_ text: String) -> Bool {
        text.count > 160 || text.split(separator: "\n", omittingEmptySubsequences: false).count > 3
    }

    static func symbol(_ phase: StepPhase, activity: StatusKey?) -> String {
        switch phase {
        case .done: "checkmark.circle"
        case .failed: PebbleSymbol.status(.error)
        case .running: activity.map(PebbleSymbol.status) ?? "circle.dotted"
        case .unfinished: "circle.dashed"
        }
    }
}

/// Folded steps (activity.ts `groupRows`): "Explored · read 3 files, 2 searches", opened to list each one with its time.
struct ActivityGroupRow: View {
    let label: String
    let items: [RunActivityItem]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(items) { item in
                StepLine(name: item.label, time: AppCopy.Details.offset(item.at), nameFont: PebbleFont.meta)
                    .accessibilityElement(children: .combine)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s3) {
                Image(systemName: ActivityStepRow.symbol(.done, activity: nil))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                StepLine(name: label, time: items.first.flatMap { AppCopy.Details.offset($0.at) })
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(AppCopy.Details.stepDone)
        }
    }
}
