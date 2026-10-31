import Foundation
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import Synchronization
import Testing

@testable import PebbleRemoteUI

/// Lane Q: a quiz on the phone. When the run that made the quiz has finished, a share comes back as Pebble's words to
/// send, and they reach that conversation's message box (Pebble's window only says the share wasn't confirmed); the
/// session's states read in Pebble's window's words.
struct QuizUITests {
    nonisolated static let row: JSONValue = [
        "id": "quiz-1", "chat_id": "chat-a", "title": "Science", "kind": "quiz", "revision": 1, "status": "ready",
        "data": [
            "duration_minutes": 10,
            "questions": [
                ["id": "q1", "question": "Which gas do plants absorb?", "choices": ["Oxygen", "Carbon dioxide"]],
                ["id": "q2", "question": "Water boils at sea level at?", "choices": ["90 °C", "100 °C", "110 °C"]],
            ],
        ],
    ]
    nonisolated static let words = "My result for the quiz \"Science\" (revision 1): 1 of 2 correct.\nQ1: correct (chose B)\nQ2: incorrect (no answer)"

    @Test func aComposedShareGoesToTheConversationsMessageBoxOnce() async throws {
        let client = ComposingQuizClient()
        let store = RemoteStore(client: client)
        client.push(
            .welcome(
                BridgeInfo(
                    bridgeVersion: "1.9.29", macName: "Studio Mac", pebbleRunning: true, pebbleVersion: "1.9.29",
                    methods: ["quiz_attempt", "quiz_start", "quiz_save", "quiz_submit", "quiz_share", "send"],
                    elevated: ["quiz_share"], resumed: true)))
        for _ in 0..<300 where store.bridge == nil { try await Task.sleep(for: .milliseconds(5)) }
        let view = try #require(PebbleArtifact(json: Self.row))
        let session = QuizSession(view: view, store: store)
        await session.load()
        #expect(session.result?.score == 1 && session.canShare)

        let words = try #require(await session.share(composing: true))
        #expect(words == Self.words && session.attempt?.shared == false && session.actionError == nil)
        // What the view does with them (ViewScreen `writeQuizResult`): the conversation shows, its composer takes them.
        let router = Router()
        router.tab = .pebble
        router.write(words, in: view.chatID)
        #expect(router.tab == .chats && router.chatsPath == [ChatRoute(chatID: "chat-a")])
        #expect(router.takeComposerWords(for: "chat-a", on: .chats) == Self.words)
        #expect(router.takeComposerWords(for: "chat-a", on: .chats) == nil)
        #expect(ComposerWords.merged("Thanks!", words) == "Thanks!\n" + Self.words)
    }

    @Test func theSessionsStatesReadInPebblesWords() {
        #expect(QuizWords.note(.said("This view changed to revision 2.")) == "This view changed to revision 2.")
        #expect(QuizWords.note(.reply(.invalid)) == AppCopy.Views.invalidAttempt)
        #expect(QuizWords.note(.reply(.otherView)) == AppCopy.Views.otherView)
        #expect(QuizWords.note(.reply(.otherConversation)) == AppCopy.Views.otherConversation)
        #expect(QuizWords.note(.reply(.notConfirmed)) == AppCopy.Views.shareNotConfirmed)
        #expect(QuizWords.saveState(.idle) == nil && QuizWords.saveState(.saving) == AppCopy.Views.saving)
        #expect(QuizWords.saveState(.failed) == AppCopy.Views.draftNotSaved)
        let states: [QuizReviewRow.State] = [.correct, .incorrect, .unanswered, .notGraded]
        #expect(states.map(QuizWords.review) == ["Correct", "Incorrect", "Unanswered", "Not graded"])
        #expect(Set(states.map(QuizWords.reviewSymbol)).count == 4)
    }
}

/// Pebble with one graded attempt whose share it can't hand to the run that made the quiz (that run has finished).
nonisolated final class ComposingQuizClient: RemoteClient {
    let updates: AsyncStream<ClientUpdate>
    private let sink: AsyncStream<ClientUpdate>.Continuation

    init() {
        (updates, sink) = AsyncStream.makeStream(of: ClientUpdate.self)
    }

    func push(_ update: ClientUpdate) { sink.yield(update) }

    func connect(to mac: PairedMac) async {}
    func disconnect() async {}

    func call(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        try answer(method)
    }

    func callElevated(_ method: String, _ params: JSONValue, reason: String) async throws -> JSONValue {
        try answer(method)
    }

    private func answer(_ method: String) throws -> JSONValue {
        switch method {
        case "quiz_attempt":
            return [
                "attempt_id": "att-1", "artifact_id": "quiz-1", "revision": 1, "status": "submitted", "deadline": 1_761_759_600,
                "answers": ["q1": 1], "shared": false,
                "result": [
                    "score": 1, "total": 2,
                    "per_question": [
                        ["id": "q1", "chosen": 1, "correct": true, "answer": 1, "explanation": "Plants take in carbon dioxide."],
                        ["id": "q2", "chosen": .null, "correct": false, "answer": 1, "explanation": "At one atmosphere."],
                    ],
                ],
            ]
        case "quiz_share":
            return [
                "status": "compose", "shared": false, "reason": "The run that made this quiz has finished.",
                "text": .string(QuizUITests.words),
            ]
        default:
            throw RemoteCallError.refused(PersonFacingError(message: "Not in this test."))
        }
    }

    func pair(_ link: PairingLink, deviceName: String) async throws -> PairedMac {
        throw RemoteCallError.notImplemented("pair")
    }
}
