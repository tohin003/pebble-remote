import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A metric (DashboardRenderer.vue): the number large, its unit, its change with its sign (and the same in words), and
/// its caption.
struct MetricPanel: View {
    let metric: NativeView.Metric

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s1) {
                Text(AppCopy.Views.number(metric.value))
                    .font(.largeTitle.bold())
                    .foregroundStyle(PebbleColor.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let unit = metric.unit {
                    Text(verbatim: unit)
                        .font(PebbleFont.cardBody)
                        .foregroundStyle(PebbleColor.secondaryText)
                }
            }
            if let delta = metric.delta, delta != 0 {
                ToneLabel(AppCopy.Views.delta(delta), tone: .neutral, showsMark: false)
            }
            if let caption = metric.caption {
                Text(verbatim: caption)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
