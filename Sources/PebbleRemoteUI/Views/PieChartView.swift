import Charts
import PebbleDesign
import SwiftUI

/// A pie or donut: one series, 2 to 8 slices, each named by its row's x value in the legend.
struct PieChartView: View {
    let points: [ChartPoint]
    let donut: Bool
    let xName: String
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 260

    var body: some View {
        Chart(points) { point in
            SectorMark(angle: .value(point.series, point.value), innerRadius: donut ? .ratio(0.6) : .automatic, angularInset: 1)
                .foregroundStyle(by: .value(xName, point.category))
        }
        .chartLegend(.visible)
        .frame(minHeight: height)
    }
}
