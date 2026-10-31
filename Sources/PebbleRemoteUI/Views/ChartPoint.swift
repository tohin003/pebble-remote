import PebbleDesign
import PebbleProtocol

/// One value of a chart's series, flattened for Swift Charts: its row's x (as a category, and as a number when it is
/// one), the series' name and the value.
struct ChartPoint: Identifiable, Hashable {
    let id: Int
    let category: String
    let number: Double?
    let series: String
    let value: Double

    /// Every row's value of every series, in the rows' order.
    static func points(_ chart: NativeView.Chart) -> [ChartPoint] {
        var out: [ChartPoint] = []
        for row in chart.rows {
            for (index, key) in chart.yKeys.enumerated() where index < row.values.count {
                out.append(
                    ChartPoint(
                        id: row.id * 8 + index, category: row.x.plain ?? AppCopy.Views.emptyCell, number: row.x.number,
                        series: chart.name(of: key), value: row.values[index]))
            }
        }
        return out
    }
}
