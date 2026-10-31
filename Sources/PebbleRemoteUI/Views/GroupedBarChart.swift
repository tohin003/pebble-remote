import Charts
import PebbleDesign
import SwiftUI

/// Bars side by side per x value, one per series.
struct GroupedBarChart: View {
    let points: [ChartPoint]
    let xName: String
    let yName: String?

    var body: some View {
        Chart(points) { point in
            BarMark(x: .value(xName, point.category), y: .value(yName ?? point.series, point.value))
                .foregroundStyle(by: .value(AppCopy.Views.chartData, point.series))
                .position(by: .value(AppCopy.Views.chartData, point.series))
        }
    }
}
