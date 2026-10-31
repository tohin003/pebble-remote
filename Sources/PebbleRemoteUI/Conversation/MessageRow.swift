import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A message in the transcript, with its long-press menu (`MessageMenuRules`) and, under it, the window's marker when
/// the person edited it or asked again ("Edited · new version below"; App.vue keeps them for the window, the phone for
/// the conversation's screen).
struct MessageRow: View {
    let message: MessageItem
    let menu: MessageMenu?
    let marker: String?
    /// A reply's source markers ([S1]) are links (the transcript opens them).
    var citesSources = false

    var body: some View {
        let isPerson = message.role == .user
        VStack(alignment: isPerson ? .trailing : .leading, spacing: PebbleSpace.s1) {
            MessageBubble(
                role: isPerson ? .person : .pebble, text: message.text, isStreaming: message.isStreaming, menu: menu,
                citesSources: citesSources && !isPerson)
            if let marker {
                Text(marker)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: isPerson ? .trailing : .leading)
    }
}
