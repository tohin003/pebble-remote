#if os(iOS)
import PebbleRemoteKit
import SwiftUI

// Previews of the value-driven views, with PreviewFixtures. iOS only (Xcode's canvas); screens that read the store are
// previewed against lane A's demo store once it lands.

#Preview("Chat rows") {
    List {
        ChatRow(chat: PreviewFixtures.idleChat)
        ChatRow(chat: PreviewFixtures.liveChat)
        ChatRow(chat: PreviewFixtures.waitingChat)
    }
    .environment(RemoteStore.demo())  // a row asks the store whether its task is held
}

#Preview("Run end lines") {
    VStack(alignment: .leading) {
        RunEndLine(state: .completed, seconds: 42, note: nil, recap: RunRecap(steps: 6, retries: 1, waitedSeconds: 60))
        RunEndLine(state: .stopped, seconds: 12, note: nil, recap: nil)
        RunEndLine(state: .failed, seconds: 30, note: "The tests could not start.", recap: nil)
    }
    .padding()
}
#endif
