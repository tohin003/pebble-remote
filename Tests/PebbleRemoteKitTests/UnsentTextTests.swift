import Foundation
import Testing

@testable import PebbleRemoteKit

// The person, 2026-10-31: words written and not sent stay where they were written, as in a messaging app, even when the
// keyboard closes. A conversation's and Ask Pebble's are kept across launches; forgetting the Mac deletes them.

@MainActor
struct UnsentTextTests {
    @Test func wordsStayUntilTheyAreCleared() {
        let unsent = UnsentText()
        unsent[.chat("c1")] = "Half a thought"
        #expect(unsent[.chat("c1")] == "Half a thought")
        #expect(unsent[.chat("c2")].isEmpty)
        #expect(unsent.hasWords(.chat("c1")))
        unsent[.chat("c1")] = ""
        #expect(unsent[.chat("c1")].isEmpty)
        #expect(!unsent.hasWords(.chat("c1")))
    }

    @Test func spacesAndLineBreaksAreKeptButAreNoWords() {
        let unsent = UnsentText()
        unsent[.askPebble] = "  \n "
        #expect(unsent[.askPebble] == "  \n ")
        #expect(!unsent.hasWords(.askPebble))
    }

    @Test func aConversationsAndAskPebblesWordsComeBackAfterARelaunch() {
        let file = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let first = UnsentText(file: file)
        first[.chat("c1")] = "Line one\nLine two"
        first[.chat("a:b")] = "An id with a colon"
        first[.askPebble] = "Ask this"
        first[.newConversation("d1")] = "Not a conversation yet"
        first.saveNow()

        let second = UnsentText(file: file)
        #expect(second[.chat("c1")] == "Line one\nLine two")
        #expect(second[.chat("a:b")] == "An id with a colon")
        #expect(second[.askPebble] == "Ask this")
        #expect(second[.newConversation("d1")].isEmpty)
    }

    @Test func aChangeIsWrittenAMomentAfterTheTypingStops() async throws {
        let file = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let unsent = UnsentText(file: file)
        unsent[.chat("c1")] = "W"
        unsent[.chat("c1")] = "Wo"
        try await Task.sleep(for: .milliseconds(1_000))
        #expect(UnsentText(file: file)[.chat("c1")] == "Wo")
    }

    @Test func removeAllDeletesTheWordsAndTheFile() {
        let file = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let unsent = UnsentText(file: file)
        unsent[.chat("c1")] = "Words"
        unsent[.askPebble] = "More"
        unsent.saveNow()
        #expect(FileManager.default.fileExists(atPath: file.path))
        unsent.removeAll()
        #expect(unsent[.chat("c1")].isEmpty)
        #expect(unsent[.askPebble].isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aFileThatIsntOursIsIgnored() throws {
        let file = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(UnsentText(file: file)[.askPebble].isEmpty)
        try Data(#"{"chat:":"no id","other":"no place","ask":""}"#.utf8).write(to: file)
        let unsent = UnsentText(file: file)
        #expect(unsent[.chat("")].isEmpty)
        #expect(unsent[.askPebble].isEmpty)
    }

    @Test func theStoreForgetsTheWordsWithTheMac() async {
        let store = RemoteStore.demo(pace: 0)
        store.unsent[.chat("c1")] = "Words for the old Mac"
        store.unsent[.askPebble] = "And these"
        await store.forgetMac()
        #expect(store.unsent[.chat("c1")].isEmpty)
        #expect(store.unsent[.askPebble].isEmpty)
    }

    private static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "unsent-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "unsent.json", directoryHint: .notDirectory)
    }
}
