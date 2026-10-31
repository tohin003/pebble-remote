import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A quiz Pebble made, taken on the phone as in Pebble's window (QuizRenderer.vue): Pebble times the attempt, keeps its
/// draft and grades it on the Mac, and the phone shows one question at a time, then the result with each question's
/// review and Share. The answer key reaches the phone only inside a graded result.
struct QuizBody: View {
    let artifact: PebbleArtifact
    /// Puts Pebble's words in the conversation's message box, when Pebble couldn't give a shared result to the run
    /// that made the quiz (nil where Pebble takes no messages from this iPhone).
    let compose: ((String) -> Void)?
    @Environment(RemoteStore.self) private var store

    var body: some View {
        QuizFlow(artifact: artifact, store: store, compose: compose)
    }
}
