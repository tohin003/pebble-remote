import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A view of Pebble's, drawn natively by its kind (contract 3.12): never code or HTML from it. A kind this version
/// doesn't draw shows its title with "Update the app to see this view"; a page shows an honest "Open on Your Mac".
struct NativeViewBody: View {
    let artifact: PebbleArtifact
    let canRefresh: Bool
    let isRefreshing: Bool
    let refresh: () -> Void
    /// Opens a form's sheet.
    let answer: () -> Void
    /// An app demo's Send Feedback, with its screen's id.
    var feedback: ((String) -> Void)?
    /// A quiz result Pebble couldn't give its run: Pebble's words for the message box (lane Q).
    var compose: ((String) -> Void)?

    var body: some View {
        switch artifact.view {
        case .form:
            Button(FormAnswers.isOpen(artifact) ? AppCopy.Views.answerForm : AppCopy.Views.yourAnswers, action: answer)
                .buttonStyle(.pebblePrimary)
        case .table(let table):
            TableBody(table: table)
        case .chart(let chart):
            ChartBody(chart: chart)
        case .plan(let plan):
            PlanBody(plan: plan)
        case .evidence(let evidence):
            EvidenceBody(evidence: evidence)
        case .quiz:
            QuizBody(artifact: artifact, compose: compose)
        case .diagram(let diagram):
            DiagramBody(diagram: diagram)
        case .dashboard(let dashboard):
            DashboardBody(
                dashboard: dashboard, artifact: artifact, canRefresh: canRefresh, isRefreshing: isRefreshing,
                refresh: refresh)
        case .prototype(let prototype):
            PrototypeBody(prototype: prototype, feedback: feedback)
        case .macOnly:
            MacOnlyBody(artifact: artifact)
        case .unsupported:
            UnsupportedViewNote(artifact: artifact)
        }
    }
}
