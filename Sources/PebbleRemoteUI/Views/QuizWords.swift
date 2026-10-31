import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The words, marks and colours for what a quiz's session says (PebbleDesign can't see the Kit's types), all from
/// Pebble's window (QuizRenderer.vue).
enum QuizWords {
    /// A failed call, under the quiz: Pebble's or the bridge's own words, or the phone's about a reply it won't use.
    static func note(_ note: QuizSession.Note) -> String {
        switch note {
        case .said(let words): words
        case .reply(.invalid): AppCopy.Views.invalidAttempt
        case .reply(.otherView): AppCopy.Views.otherView
        case .reply(.otherConversation): AppCopy.Views.otherConversation
        case .reply(.notConfirmed): AppCopy.Views.shareNotConfirmed
        }
    }

    /// The draft's state beside the question's number: nothing before the first choice.
    static func saveState(_ state: QuizSession.SaveState) -> String? {
        switch state {
        case .idle: nil
        case .saving: AppCopy.Views.saving
        case .saved: AppCopy.Views.draftSaved
        case .failed: AppCopy.Views.draftNotSaved
        }
    }

    static func review(_ state: QuizReviewRow.State) -> String {
        switch state {
        case .correct: AppCopy.Views.correct
        case .incorrect: AppCopy.Views.incorrect
        case .unanswered: AppCopy.Views.unanswered
        case .notGraded: AppCopy.Views.notGraded
        }
    }

    static func reviewSymbol(_ state: QuizReviewRow.State) -> String {
        switch state {
        case .correct: ViewSymbol.reviewCorrect
        case .incorrect: ViewSymbol.reviewIncorrect
        case .unanswered: ViewSymbol.reviewUnanswered
        case .notGraded: ViewSymbol.reviewNotGraded
        }
    }

    /// Right in the accent and wrong in danger, as in Pebble's window; the words always say it too.
    static func reviewColor(_ state: QuizReviewRow.State) -> Color {
        switch state {
        case .correct: PebbleColor.accent
        case .incorrect: PebbleColor.danger
        case .unanswered, .notGraded: PebbleColor.mutedText
        }
    }
}
