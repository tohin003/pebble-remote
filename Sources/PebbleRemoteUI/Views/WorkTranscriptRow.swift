import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A transcript line that isn't a message, with the work view where Pebble sent one (contract 3.12): an activity line
/// drawn as its card (or its words with "Update the app to see this view"), a live run's plan header above its first
/// line, a settled run's summary under its end line, and the views that run drew. Everything else is TranscriptRow's.
struct WorkTranscriptRow: View {
    let item: TranscriptItem
    let transcript: Transcript
    let layout: WorkTranscriptLayout
    var showDetails: ((RunID) -> Void)? = nil
    var present: RecoveryPresenter? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            if let run = layout.headerRuns[item.id], let plan = transcript.plans[run] {
                WorkPlanHeader(plan: plan, state: transcript.run?.state.rawValue, isLive: true)
            }
            switch item {
            case .activity(let id, let runID, let text, let status):
                switch transcript.workLines[id] {
                case .card(let card)?:
                    WorkCardView(card: card, runIsLive: runID != nil && runID == transcript.run?.id)
                case .unreadable?:
                    UnreadableActivityLine(text: text, status: status)
                default:
                    TranscriptRow(item: item, recaps: transcript.recaps, showDetails: showDetails, present: present)
                }
            case .runEnd(_, let runID, _, _, _):
                WorkRunEnd(runID: runID) {
                    TranscriptRow(item: item, recaps: transcript.recaps, showDetails: showDetails, present: present)
                }
            default:
                TranscriptRow(item: item, recaps: transcript.recaps, showDetails: showDetails, present: present)
            }
            if let views = layout.viewsAfter[item.id] {
                ViewCardList(views: views)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
