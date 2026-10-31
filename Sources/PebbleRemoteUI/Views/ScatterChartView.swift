import Charts
import PebbleDesign
import SwiftUI

/// Points over numeric x values (a scatter chart's rows all have a number for x).
struct ScatterChartView: View {
    let points: [ChartPoint]
    let xName: String
    let multiSeries: Bool
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 260

    var body: some View {
        let series = AppCopy.Views.chartData
        Chart(points.filter { $0.number != nil }) { point in
            PointMark(x: .value(xName, point.number ?? 0), y: .value(point.series, point.value))
                .foregroundStyle(by: .value(series, point.series))
        }
        .chartLegend(multiSeries ? .visible : .hidden)
        .chartXAxisLabel(xName)
        .frame(minHeight: height)
    }
}
