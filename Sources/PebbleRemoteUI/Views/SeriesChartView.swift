import Charts
import PebbleDesign
import PebbleProtocol
import SwiftUI

/// Bars (grouped side by side when there are several series), stacked bars, lines or areas over the rows' x values.
/// Each style is its own chart, so no chart holds a condition.
struct SeriesChartView: View {
    let points: [ChartPoint]
    let style: NativeView.Chart.Style
    let xName: String
    /// The one series' name; nil when there are several (the legend names them).
    let yName: String?
    let unit: String?
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 260

    var body: some View {
        Group {
            switch style {
            case .line:
                LineSeriesChart(points: points, xName: xName, yName: yName)
            case .area:
                AreaSeriesChart(points: points, xName: xName, yName: yName)
            case .stacked:
                StackedBarChart(points: points, xName: xName, yName: yName)
            default:
                GroupedBarChart(points: points, xName: xName, yName: yName)
            }
        }
        .chartLegend(yName == nil ? .visible : .hidden)
        .chartYAxisLabel(unit ?? yName ?? "")
        .chartXAxisLabel(xName)
        .frame(minHeight: height)
    }
}
