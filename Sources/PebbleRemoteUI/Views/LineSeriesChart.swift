import Charts
import PebbleDesign
import SwiftUI

/// A line per series, with a mark at each value.
struct LineSeriesChart: View {
    let points: [ChartPoint]
    let xName: String
    let yName: String?

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value(xName, point.category), y: .value(yName ?? point.series, point.value))
                .foregroundStyle(by: .value(AppCopy.Views.chartData, point.series))
                .symbol(by: .value(AppCopy.Views.chartData, point.series))
        }
    }
}
