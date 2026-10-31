import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A chart's values as rows of words: the x value, then each series' name and value.
struct ChartDataTable: View {
    let chart: NativeView.Chart

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            ForEach(chart.rows) { row in
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Text(verbatim: row.x.plain ?? AppCopy.Views.emptyCell)
                        .font(PebbleFont.cardBody.bold())
                        .foregroundStyle(PebbleColor.text)
                    ForEach(Array(chart.yKeys.enumerated()), id: \.offset) { index, key in
                        if index < row.values.count {
                            LabeledContent(chart.name(of: key), value: ViewCell.plain(row.values[index]))
                                .font(PebbleFont.cardBody)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, PebbleSpace.s2)
    }
}
