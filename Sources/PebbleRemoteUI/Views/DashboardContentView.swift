import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A panel's content: a metric, or a table, chart, plan or evidence drawn as their own views are.
struct DashboardContentView: View {
    let content: NativeView.Dashboard.Content

    var body: some View {
        switch content {
        case .metric(let metric):
            MetricPanel(metric: metric)
        case .table(let table):
            TableBody(table: table)
        case .chart(let chart):
            ChartBody(chart: chart)
        case .plan(let plan):
            PlanBody(plan: plan)
        case .evidence(let evidence):
            EvidenceBody(evidence: evidence)
        }
    }
}
