import Foundation
import PebbleProtocol
import Testing

@testable import PebbleDesign

/// Lane G: the views' words that are Pebble's own appear word for word in Pebble's sources (read from the Pebble
/// checkout when it is on this Mac), so a change in Pebble's work view or renderers fails here until the phone follows.
@Suite(.enabled(if: PebbleCheckout.url != nil))
struct ViewsCopyParityTests {
    typealias V = AppCopy.Views

    static let pebbles: [String: [String]] = [
        "src/workView.ts": [
            V.state(.waiting), V.state(.held), V.searchedTheWeb, V.whatYourRequestRequires, V.aCommand, V.anAppWindow,
            V.runWord("budget_exhausted"), V.runWord("needs_reconciliation"), V.runWord("verification_required"),
            V.runWord("failed"),
        ],
        "src/components/WorkCard.vue": [
            V.outputWasLonger, V.metAfterRepair, V.notAllMet, V.allMet, V.wherePebblePressed, V.lastLines, V.withNetwork,
            V.noNetwork, V.changesHistory, V.publishes, V.verdict(.nothingChanged), V.verdict(.uncertain),
            V.verdict(.refused), V.notConfirmedYet, V.inProgress, V.aPrivateFile,
        ],
        "src/components/WorkView.vue": [V.whatPebbleIsDoing, V.whatPebbleDid],
        "src/components/NativeArtifactRenderer.vue": [
            V.answersBecomeInput, V.completeEveryField, V.noActiveRequest, V.submitAnswers, V.noRows,
        ],
        "src/components/PrototypeRenderer.vue": [V.mockUpNote, V.nothingSaved],
        // Lane Q: taking a quiz on the phone.
        "src/components/QuizRenderer.vue": [
            V.quizLead, V.generatedByAI, V.invalidQuiz, V.historicalQuiz, V.loadingAttempt, V.quizChangedWhileAnswering,
            V.timeRanOut, V.openDesktopApp, V.startQuiz, V.startAgain, V.starting, V.questionsAnswered, V.jumpToQuestion,
            V.saving, V.draftSaved, V.draftNotSaved, V.timeIsUp, V.back, V.next, V.checking, V.submitAnswers,
            V.gradedByPebble, V.gradedWhenTimeRanOut, V.correct, V.incorrect, V.unanswered, V.notGraded, V.shareResult,
            V.sharing, V.sharedWithPebble, V.shareNote, V.retakeQuiz, V.invalidAttemptPebble, V.otherViewPebble,
            V.otherConversationPebble, V.shareNotConfirmedPebble,
        ],
        "src/components/VisualChart.vue": [V.chartData],
        "src/components/VisualDiagram.vue": [V.diagramAsText],
    ]

    @Test func viewsWordsArePebblesWordForWord() throws {
        for (file, words) in Self.pebbles {
            let text = try PebbleParityTests.read(file)
            for word in words {
                #expect(text.contains(word), "\(file) no longer says: \(word)")
            }
        }
    }

    /// Lane Q: the quiz's sentences that Pebble's window breaks over lines or fills in. A sentence is compared with the
    /// window's text with its white space run together; a filled-in one by its fixed parts around sample values.
    @Test func quizSentencesArePebblesWordForWord() throws {
        let text = PebbleParityTests.collapse(try PebbleParityTests.read("src/components/QuizRenderer.vue"))
        #expect(text.contains(V.quizIntro), "QuizRenderer.vue no longer says: \(V.quizIntro)")
        let filled: [(String, [String])] = [
            (V.quizChanged(after: 7), ["7"]),
            (V.quizIs("stopped"), ["stopped"]),
            (V.timeLeft(271), ["04:31"]),
            (V.questionOf(3, 9), ["3", "9"]),
            (V.questionInList(3, answered: true), ["3"]),
            (V.answeredCount(4, of: 9), ["4", "9"]),
            (V.draftNotSavedBecause("REASON"), ["REASON"]),
            (V.score(4, of: 9), ["4", "9"]),
            (V.reviewHeading(3, V.incorrect), ["3", V.incorrect]),
            (V.yourAnswer("CHOICE"), ["CHOICE"]),
            (V.correctAnswer("CHOICE"), ["CHOICE"]),
        ]
        for (sentence, values) in filled {
            for piece in Self.pieces(of: sentence, around: values) {
                #expect(text.contains(piece), "QuizRenderer.vue no longer says “\(piece)” (from “\(sentence)”)")
            }
        }
    }

    /// The fixed parts of `sentence` between the sample `values`, in order (each value once).
    static func pieces(of sentence: String, around values: [String]) -> [String] {
        var pieces: [String] = []
        var rest = Substring(sentence)
        for value in values {
            guard let range = rest.range(of: value) else { continue }
            pieces.append(String(rest[..<range.lowerBound]))
            rest = rest[range.upperBound...]
        }
        pieces.append(String(rest))
        return pieces.filter { !$0.isEmpty }
    }
}
