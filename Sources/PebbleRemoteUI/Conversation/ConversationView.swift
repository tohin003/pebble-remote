import PebbleRemoteKit
import SwiftUI

/// One conversation, live: pushed by every tab that opens a chat. The store keeps one Transcript per chat, loading it
/// on first use and keeping it current while connected.
struct ConversationView: View {
    let chatID: ChatID
    @Environment(RemoteStore.self) private var store

    var body: some View {
        TranscriptScreen(transcript: store.transcript(for: chatID))
    }
}
