import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

/// TR-10: a reply's source marker ([S1]) opens the page its run recorded, on the iPhone; otherwise the phone says what
/// Pebble's window says (App.vue `openCitation`).
@MainActor
struct SourceMarkerTests {
    @Test func theDemosWeatherReplyOpensItsFirstSourceAndNamesTheOther() async throws {
        let store = await DetailsKitTests.demo()
        let page = await store.sourcePage("S1", in: DemoData.weatherChat, run: "r-weather")
        #expect(page?.absoluteString == "https://www.ipma.pt/en/otempo/prev.localidade.hora/")
        #expect(store.notice == nil)
        // http, not https: named instead, as on the Mac.
        #expect(await store.sourcePage("S2", in: DemoData.weatherChat, run: "r-weather") == nil)
        #expect(store.notice?.message == "S2 is Lisbon weekend outlook.")
        #expect(await store.sourcePage("S9", in: DemoData.weatherChat, run: "r-weather") == nil)
        #expect(store.notice?.message == "Pebble has no record of S9 for this reply.")
    }

    @Test func aReplyWithoutItsRunAsksForTheConversationsNewest() async throws {
        let store = await DetailsKitTests.demo()
        let page = await store.sourcePage("S1", in: DemoData.weatherChat, run: nil)
        #expect(page?.host() == "www.ipma.pt")
    }

    @Test func aSourceWithNothingToNameSaysItHasNoAddress() async throws {
        let (store, fake) = await Self.store(sources: [["source_id": "S3", "kind": "file", "url": "", "title": "  ", "domain": ""]])
        #expect(await store.sourcePage("S3", in: "c1", run: "r1") == nil)
        #expect(fake.calls("research_sources").last?.params == ["id": "c1", "run_id": "r1"])
        #expect(store.notice?.message == "S3 has no web address to open.")
    }

    @Test func aNameIsOneLineOfAtMost80Characters() async throws {
        let long = String(repeating: "word ", count: 30)
        let (store, _) = await Self.store(sources: [["source_id": "S1", "url": "ftp://files.example/a", "title": .string("A\n\n" + long)]])
        #expect(await store.sourcePage("S1", in: "c1", run: "r1") == nil)
        let message = try #require(store.notice?.message)
        #expect(!message.contains("\n") && message.hasPrefix("S1 is A word word"))
        #expect(message.count == "S1 is ".count + 80 + ".".count)
    }

    /// The sentences are Pebble's window's, when `PEBBLE_CHECKOUT` names Pebble's checkout.
    @Test func theWordsArePebblesWindows() throws {
        let checkout = ProcessInfo.processInfo.environment["PEBBLE_CHECKOUT"] ?? ""
        guard !checkout.isEmpty,
              let window = try? String(contentsOfFile: checkout + "/src/App.vue", encoding: .utf8)
        else { return }
        for words in [
            StoreWords.sourceNotRecorded("${id}"), StoreWords.sourceNamed("${id}", "${name}"),
            StoreWords.sourceWithoutAddress("${id}"), StoreWords.sourceNotOpened("${id}"),
        ] {
            #expect(window.contains(words), "\(words)")
        }
    }

    /// A store connected to a fake bridge whose `research_sources` answers these sources.
    static func store(sources: [JSONValue]) async -> (RemoteStore, FakeClient) {
        let fake = FakeClient { method, _ in
            switch method {
            case "state": return Fixture.stateJSON()
            case "get_chat", "remote.chat_tail": return Fixture.chatDetail()
            case "research_sources": return ["sources": .array(sources)]
            default: return .bool(true)
            }
        }
        let store = RemoteStore(client: fake)
        fake.push(.status(ConnectionStatus(phase: .connected, route: .lan, roundTrip: 6)))
        fake.push(
            .welcome(
                BridgeInfo(
                    bridgeVersion: "0.1", macName: "Studio Mac", pebbleRunning: true, pebbleVersion: "1.9.29",
                    methods: ["state", "get_chat", "research_sources"], elevated: [], resumed: false)))
        _ = await eventually { store.pebble != nil }
        return (store, fake)
    }
}
