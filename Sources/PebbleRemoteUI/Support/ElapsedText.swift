import Foundation
import PebbleDesign
import SwiftUI

/// Time since a run started, in Pebble's exact form ("12 s", "1 min 05 s", "1 h 02 min"), ticking once a second.
/// Shows nothing under a second, as Pebble does.
struct ElapsedText: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(StatusCopy.formatExactElapsed(context.date.timeIntervalSince(since)) ?? "")
                .monospacedDigit()
        }
    }
}
