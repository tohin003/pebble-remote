import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A chart Pebble drew (VisualChart.vue): bars, lines, areas, stacked bars, points, or a pie or donut, with Swift
/// Charts, its caption, and "Chart data" with every value in words (spec rule 6: every mark has words).
struct ChartBody: View {
    let chart: NativeView.Chart
    @State private var showsData = false

    var body: some View {
        let points = ChartPoint.points(chart)
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            if let caption = chart.caption {
                Text(verbatim: caption)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            let series = chart.yKeys.map { chart.name(of: $0) }
            switch chart.style {
            case .pie, .donut:
                PieChartView(points: points, donut: chart.style == .donut, xName: chart.name(of: chart.xKey))
                    .pebbleChartColours(points.map(\.category), fadesRepeats: true)
            case .scatter:
                ScatterChartView(points: points, xName: chart.name(of: chart.xKey), multiSeries: chart.yKeys.count > 1)
                    .pebbleChartColours(series)
            case .bar, .line, .area, .stacked:
                SeriesChartView(
                    points: points, style: chart.style, xName: chart.name(of: chart.xKey),
                    yName: chart.yKeys.count == 1 ? chart.name(of: chart.yKeys[0]) : nil, unit: chart.unit)
                    .pebbleChartColours(series)
            }
            DisclosureGroup(AppCopy.Views.chartData, isExpanded: $showsData) {
                ChartDataTable(chart: chart)
            }
            .font(PebbleFont.cardBody)
        }
    }
}
