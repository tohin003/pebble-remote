import Charts
import PebbleDesign
import SwiftUI

extension View {
    /// Pebble's series colours (VisualChart.vue's .s0 to .s5: --chart-1 to --chart-6), in the order the names come:
    /// the chart's y keys, or a pie's rows. A pie's slices past the sixth repeat them at 60 %, as Pebble's "alt" slices
    /// do. A name that comes twice keeps its first colour.
    func pebbleChartColours(_ names: [String], fadesRepeats: Bool = false) -> some View {
        let palette = PebbleColor.chartSeries
        var seen = Set<String>()
        var domain: [String] = []
        var range: [Color] = []
        for (index, name) in names.enumerated() where seen.insert(name).inserted {
            let colour = palette[index % palette.count]
            domain.append(name)
            range.append(fadesRepeats && index >= palette.count ? colour.opacity(0.6) : colour)
        }
        return chartForegroundStyleScale(domain: domain, range: range)
    }
}
