import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The preview of a long press on a conversation in Chats: its title and its last line, never the transcript (lane Z
/// brief, item 1). The last line is read when the preview opens (`RemoteStore.lastLine(of:)`); until it comes, a
/// placeholder of the same height keeps the preview from changing size. With no line to show, the title stands alone.
struct ChatPreview: View {
    let chat: ChatSummary
    /// Reads the conversation's last line.
    let lastLine: () async -> ChatLastLine?
    @State private var line: ChatLastLine?
    @State private var isReading = true

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Text(chat.title.isEmpty ? AppCopy.Chats.untitled : chat.title)
                .font(.headline)
                .foregroundStyle(PebbleColor.text)
                .lineLimit(3)
            if let line {
                Text(line.fromPerson ? AppCopy.ChatMenu.fromYou(line.text) : line.text)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
                    .lineLimit(3)
            } else if isReading {
                Text(verbatim: String(repeating: "\u{2014} ", count: 24))
                    .font(PebbleFont.cardBody)
                    .lineLimit(2)
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            }
        }
        .padding(PebbleSpace.s4)
        .frame(width: 320, alignment: .leading)
        .background(PebbleColor.panel)
        .task {
            line = await lastLine()
            isReading = false
        }
    }
}
