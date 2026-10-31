import PebbleDesign
import SwiftUI

/// One of the quiz's notes (QuizRenderer.vue `quiz-note`): what happened to an attempt, or what applies now.
struct QuizNoteText: View {
    let words: String

    init(_ words: String) {
        self.words = words
    }

    var body: some View {
        Text(words)
            .font(PebbleFont.cardBody)
            .foregroundStyle(PebbleColor.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
