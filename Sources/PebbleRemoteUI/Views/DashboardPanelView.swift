import PebbleDesign
import PebbleProtocol
import SwiftUI

/// One dashboard panel: its title (literal), Live or Snapshot, then its content, or why it has none.
struct DashboardPanelView: View {
    let panel: NativeView.Dashboard.Panel

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: panel.title ?? AppCopy.Views.untitledPanel)
                    .font(PebbleFont.cardTitle)
                    .foregroundStyle(PebbleColor.text)
                Spacer(minLength: PebbleSpace.s2)
                Text(panel.isLive ? AppCopy.Views.live : AppCopy.Views.snapshot)
                    .font(PebbleFont.chip)
                    .foregroundStyle(panel.isLive ? PebbleColor.ok : PebbleColor.secondaryText)
            }
            switch panel.state {
            case .ready(let content):
                DashboardContentView(content: content)
            case .waiting:
                Text(AppCopy.Views.waitingForData)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            case .failed(let words):
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    ToneLabel(AppCopy.Views.panelUnavailable, tone: .bad)
                    if let words {
                        Text(verbatim: words)
                            .font(PebbleFont.meta)
                            .foregroundStyle(PebbleColor.secondaryText)
                    }
                }
            case .invalid:
                Text(AppCopy.Views.panelInvalid)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            if let source = panel.source {
                Text(verbatim: Self.stamp(source: source, asOf: panel.asOf))
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.mutedText)
            }
        }
        .padding(PebbleSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PebbleColor.panel, in: .rect(cornerRadius: PebbleRadius.md))
        .overlay { RoundedRectangle(cornerRadius: PebbleRadius.md).stroke(PebbleColor.line, lineWidth: 1) }
    }

    /// "Recent runs · as of 14:05".
    static func stamp(source: String, asOf: Date?) -> String {
        let name = AppCopy.Views.source(source)
        guard let asOf else { return name }
        return "\(name) \u{00B7} \(AppCopy.Views.asOf(asOf.formatted(date: .omitted, time: .shortened)))"
    }
}
