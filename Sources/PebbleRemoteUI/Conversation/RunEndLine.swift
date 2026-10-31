import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// How a run ended, in Pebble's words ("Worked for 42 s", "Stopped after 12 s", "Hit a problem after 30 s"), with
/// Pebble's note when it gave one. A quick reply with nothing to say gets no line, as on the Mac.
struct RunEndLine: View {
    let state: RunState
    let seconds: Double?
    let note: String?
    let recap: RunRecap?

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            if let line = RunCopy.endLine(
                state: state, seconds: seconds, steps: recap?.steps ?? 0, retries: recap?.retries ?? 0,
                waitedSeconds: recap?.waitedSeconds ?? 0, countsKnown: recap?.steps != nil)
            {
                Label(line, systemImage: symbol)
                    .font(PebbleFont.activity)
                    .foregroundStyle(state == .failed ? AnyShapeStyle(PebbleColor.danger) : AnyShapeStyle(.secondary))
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(PebbleFont.activity)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        switch state {
        case .completed: PebbleSymbol.finished
        case .failed: PebbleSymbol.status(.error)
        case .paused: PebbleSymbol.status(.paused)
        default: PebbleSymbol.stopEverything
        }
    }
}
