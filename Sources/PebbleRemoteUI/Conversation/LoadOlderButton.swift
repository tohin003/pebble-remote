import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// At the top of a long transcript: loads the messages before the first one shown.
struct LoadOlderButton: View {
    let transcript: Transcript
    @State private var isLoading = false

    var body: some View {
        Button(action: load) {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Text(AppCopy.Conversation.loadEarlier)
                }
                Spacer()
            }
            .frame(minHeight: PebbleSize.minTap)
        }
        .buttonStyle(.borderless)
        .disabled(isLoading)
    }

    private func load() {
        isLoading = true
        Task {
            await transcript.loadOlder()
            isLoading = false
        }
    }
}
