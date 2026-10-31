import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// Lane N end to end: the real store and LiveClient against lane C2's mock bridge with proposal v0.5, over real TLS and
// signed Face ID proofs. The mock lists a test tree of its own (`--folders-root`), never this Mac's home folder.
// Skipped unless PEBBLE_MOCK_E2E=1:
//
//     PEBBLE_MOCK_E2E=1 scripts/swift.sh test --filter ProjectsE2ETests

@Suite("Lane N: Connect a project and new conversations, end to end with the mock bridge", .serialized)
struct ProjectsE2ETests {
    /// A home folder of the test's own: Projects holding a Git repository and a plain folder, and a hidden folder.
    private static func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pebble-remote-folders-\(UUID().uuidString)", isDirectory: true)
        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        for folder in ["app/.git", "notes"] {
            try FileManager.default.createDirectory(
                at: projects.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".hidden", isDirectory: true), withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    /// The bridge takes 20 calls in a burst and 10 a second after (contract 3.9); a script acts faster than a person,
    /// with the store's own reads in between, so it waits for the bucket to fill between steps.
    private static func pause() async throws {
        try await Task.sleep(for: .seconds(2.5))
    }

    @MainActor
    @Test(.enabled(if: MockBridgeE2ETests.enabled), .timeLimit(.minutes(1)))
    func browsesConnectsAndStartsConversationsInTheMacsFolders() async throws {
        let tree = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: tree) }
        let mock = try await MockBridgeProcess.launch(extraArguments: ["--folders-root", tree.path])
        defer { mock.stop() }
        let link = try #require(PairingLink(string: mock.pairingLink))
        let keys = RecordingKeyProvider()
        let client = LiveClient(
            keys: keys, pairingReason: { "Pair with \($0)" }, unlockReason: "Unlock Pebble",
            connector: NetworkSocketConnector(), pathWatcher: StillPathWatcher(), discovery: NoBridgeDiscovery(),
            device: DeviceDescription(model: "iPhone18,3", os: "iOS 26.1", app: "1.0 (1)"),
            configuration: LiveClient.Configuration(backoff: Backoff(initial: .milliseconds(100), maximum: .seconds(1))))
        let mac = try await client.pair(link, deviceName: "Test iPhone")
        let store = RemoteStore(client: client, pairedMac: mac)
        store.start()
        #expect(await eventually(.seconds(15)) { store.pebble != nil && store.bridge?.methods.contains("remote.folders") == true })

        // The Mac's folders, from the home folder (no path): the hidden one is left out, the repository is marked.
        try await Self.pause()
        let home = try await store.folders(at: nil)
        #expect(home.isHome && home.parent == nil)
        #expect(home.folders.map(\.name) == ["Projects"])
        let projects = try await store.folders(at: try #require(home.folders.first).path)
        #expect(projects.parent == home.path)
        #expect(projects.folders.map(\.name) == ["app", "notes"] && projects.folders.map(\.isProject) == [true, false])
        await #expect(throws: RemoteCallError.self) { _ = try await store.folders(at: "/etc") }
        #expect(store.notice?.code == "not_allowed")
        store.notice = nil

        // A new conversation in a folder no conversation uses: one new_chat with Face ID, then its first message.
        try await Self.pause()
        let app = try #require(projects.folders.first)
        #expect(!store.isKnownProject(app.path))
        let draft = store.newDraft(in: ProjectRef(app))
        try store.attachURL("https://docs.example.com/guide", to: draft)
        let chat = try #require(try await store.send("Add a settings screen", from: draft))
        #expect(keys.reasons.contains("Connect a project: app"))
        #expect(store.transcript(for: chat).workspace == app.path)
        #expect(store.isKnownProject(app.path))

        // Moving a conversation: Pebble refuses while a task runs, so the first message's task stops first. Then back to
        // Companion with the unlock alone, and into a new folder with Face ID.
        try await store.stop(chat: chat)
        #expect(await eventually(.seconds(15)) { !store.isPebbleWorking })
        try await Self.pause()
        let signed = keys.reasons.count
        try await store.setWorkspace(chat, to: nil)
        #expect(store.transcript(for: chat).workspace == nil)
        #expect(keys.reasons.count == signed)  // no Face ID for Companion
        let notes = try #require(projects.folders.last)
        try await store.setWorkspace(chat, to: ProjectRef(notes))  // a new folder: Face ID
        #expect(keys.reasons.last == "Connect a project: notes")
        #expect(store.transcript(for: chat).workspace == notes.path)

        // The composer's "+" menu: a web page for the next message, and a terminal command for Pebble's review.
        try await Self.pause()
        let page = try await store.attachURL("https://docs.example.com/guide", to: chat)
        #expect(page.kind == "url" && store.attachments[chat]?.contains(page) == true)
        try await store.proposeTerminalCommand("git status --short", network: false, in: chat)
        #expect(keys.reasons.last == "Terminal command: git status --short")
        #expect(
            await eventually(.seconds(10)) {
                store.waiting.contains { if case .review(let card) = $0 { card.chatID == chat } else { false } }
            })
        await client.disconnect()
    }
}
