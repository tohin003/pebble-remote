import Charts
import PebbleDesign
import SwiftUI

/// Areas per series, stacked.
struct AreaSeriesChart: View {
    let points: [ChartPoint]
    let xName: String
    let yName: String?

    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value(xName, point.category), y: .value(yName ?? point.series, point.value))
                .foregroundStyle(by: .value(AppCopy.Views.chartData, point.series))
        }
    }
}
