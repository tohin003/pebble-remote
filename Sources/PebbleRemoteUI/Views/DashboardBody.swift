import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A dashboard Pebble drew (DashboardRenderer.vue): its panels (metrics, tables, charts, plans, evidence) in one
/// column on a phone and in the dashboard's own columns when there is room. Live panels show what Pebble read from this
/// conversation, with when it read them; "Refresh Data" reads them again while the dashboard is live.
struct DashboardBody: View {
    let dashboard: NativeView.Dashboard
    let artifact: PebbleArtifact
    let canRefresh: Bool
    let isRefreshing: Bool
    let refresh: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let columns = sizeClass == .regular ? dashboard.columns : 1
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppCopy.Views.panels(dashboard.panels.count, live: dashboard.liveCount))
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
                Spacer(minLength: PebbleSpace.s2)
                if dashboard.liveCount > 0, canRefresh, artifact.isLive {
                    Button(action: refresh) {
                        Label(isRefreshing ? AppCopy.Views.refreshing : AppCopy.Views.refreshData, systemImage: ViewSymbol.refresh)
                    }
                    .buttonStyle(.pebbleSecondary)
                    .disabled(isRefreshing)
                }
            }
            if !artifact.isLive, let status = artifact.status {
                Text(AppCopy.Views.noLongerRefreshed(stopped: status == .stopped))
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: PebbleSpace.s3, alignment: .top), count: columns),
                alignment: .leading, spacing: PebbleSpace.s3
            ) {
                ForEach(dashboard.panels) { panel in
                    DashboardPanelView(panel: panel)
                }
            }
            Text(AppCopy.Views.dashboardFootnote)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.mutedText)
        }
    }
}
