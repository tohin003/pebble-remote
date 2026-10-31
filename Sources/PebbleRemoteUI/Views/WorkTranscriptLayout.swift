import PebbleProtocol
import PebbleRemoteKit

/// Where the work view and the conversation's views go in the transcript: activity lines folded into an earlier card
/// are left out; a live run's plan header goes above its first line; each view goes under the end line of the run that
/// drew it, and views whose run has no end line here go at the end.
struct WorkTranscriptLayout {
    /// The transcript's items to draw, in order.
    let items: [TranscriptItem]
    /// A transcript item's id → the live run whose plan header goes above it.
    let headerRuns: [String: RunID]
    /// A run end's transcript item id → the views that run drew.
    let viewsAfter: [String: [PebbleArtifact]]
    /// Views without an end line here (their run works, or isn't in the transcript).
    let trailingViews: [PebbleArtifact]

    init(_ transcript: Transcript) {
        var shown: [TranscriptItem] = []
        var headers: [String: RunID] = [:]
        var seen = Set<RunID>()
        var ends: [RunID: String] = [:]
        let live = transcript.run?.id
        for item in transcript.items {
            switch item {
            case .activity(let id, let runID, _, _):
                if case .folded? = transcript.workLines[id] { continue }
                if let runID, seen.insert(runID).inserted, runID == live, transcript.plans[runID] != nil {
                    headers[item.id] = runID
                }
            case .runEnd(_, let runID, _, _, _):
                ends[runID] = item.id
            default:
                break
            }
            shown.append(item)
        }
        // A waiting form already stands in place as its question's card: one place for it (IA rule 4).
        let waitingForms = Set(
            transcript.items.compactMap { item -> String? in
                if case .question(let card) = item { card.form?.id } else { nil }
            })
        var after: [String: [PebbleArtifact]] = [:]
        var trailing: [PebbleArtifact] = []
        for view in transcript.views where !(view.waitsForAnswer && waitingForms.contains(view.id)) {
            if let run = view.ownerRunID, let end = ends[run] {
                after[end, default: []].append(view)
            } else {
                trailing.append(view)
            }
        }
        items = shown
        headerRuns = headers
        viewsAfter = after
        trailingViews = trailing
    }
}
