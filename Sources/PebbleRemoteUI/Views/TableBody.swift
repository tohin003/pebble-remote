import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A table Pebble drew (NativeArtifactRenderer.vue): its caption, then a grid that scrolls both ways, every cell
/// literal ("—" when empty). Each row is read out with its columns' names.
struct TableBody: View {
    let table: NativeView.Table

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            if let caption = table.caption {
                Text(verbatim: caption)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            if table.rows.isEmpty {
                Text(AppCopy.Views.noRows)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: PebbleSpace.s4, verticalSpacing: PebbleSpace.s2) {
                    GridRow {
                        ForEach(table.columns) { column in
                            Text(verbatim: column.label)
                                .font(PebbleFont.cardBody.bold())
                                .foregroundStyle(PebbleColor.text)
                        }
                    }
                    Divider()
                    ForEach(table.rows) { row in
                        GridRow {
                            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                                Text(verbatim: cell.plain ?? AppCopy.Views.emptyCell)
                                    .font(cell.number != nil ? PebbleFont.cardBody.monospacedDigit() : PebbleFont.cardBody)
                                    .foregroundStyle(cell == .empty ? PebbleColor.mutedText : PebbleColor.text)
                                    .lineLimit(4)
                                    .frame(maxWidth: 280, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.vertical, PebbleSpace.s1)
                // VoiceOver reads one row at a time with its columns' names. A GridRow's own modifiers would reach each
                // of its cells (it lays out like a Group), so the grid gives its rows as plain elements instead.
                .accessibilityRepresentation {
                    VStack(alignment: .leading) {
                        ForEach(table.rows) { row in
                            Text(verbatim: Self.spoken(row, columns: table.columns))
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
            Text(AppCopy.Views.rows(table.rows.count))
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.mutedText)
        }
    }

    /// "File: session.py, Lines: 212".
    static func spoken(_ row: NativeView.Table.Row, columns: [NativeView.Table.Column]) -> String {
        zip(columns, row.cells).map { column, cell in "\(column.label): \(cell.plain ?? AppCopy.Views.emptyCell)" }
            .joined(separator: ", ")
    }
}
