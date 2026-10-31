import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// Lane F end to end: the real store and LiveClient against the mock bridge with proposal v0.6, over real TLS and signed
// Face ID proofs. The mock makes its folders in a test tree of its own (`--folders-root`), never in this Mac's home
// folder. Skipped unless PEBBLE_MOCK_E2E=1:
//
//     PEBBLE_MOCK_E2E=1 scripts/swift.sh test --filter FolderCreateE2ETests

@Suite("Lane F: New Folder, end to end with the mock bridge", .serialized)
struct FolderCreateE2ETests {
    private static func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pebble-remote-newfolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Projects/app/.git", isDirectory: true), withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    /// The bridge takes 20 calls in a burst and 10 a second after (contract 3.9): the script waits for the bucket to fill.
    private static func pause() async throws {
        try await Task.sleep(for: .seconds(2.5))
    }

    @MainActor
    @Test(.enabled(if: MockBridgeE2ETests.enabled), .timeLimit(.minutes(1)))
    func makesAFolderOnTheMacAndConnectsItWithOneFaceID() async throws {
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
        #expect(
            await eventually(.seconds(15)) {
                store.pebble != nil && store.bridge?.methods.contains("remote.folder_create") == true
            })
        #expect(store.bridge?.elevated.contains("remote.folder_create") == true)  // the bridge says it needs Face ID

        // New Folder in Projects: one Face ID, "Create a folder: <name>", and a real, empty folder on the Mac.
        try await Self.pause()
        let home = try await store.folders(at: nil)
        let projects = try #require(home.folders.first { $0.name == "Projects" })
        let signed = keys.reasons.count
        let made = try await store.createFolder(named: "  from the phone \n", in: projects.path)
        #expect(made == FolderEntry(name: "from the phone", path: projects.path + "/from the phone", isProject: false))
        #expect(keys.reasons.count == signed + 1 && keys.reasons.last == "Create a folder: from the phone")
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: made.path, isDirectory: &isFolder) && isFolder.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: made.path).isEmpty)
        #expect(store.isRecentlyMade(made.path))

        // It is listed, and opens empty with its parent above it.
        let listing = try await store.folders(at: projects.path)
        #expect(listing.folders.contains(made))
        let inside = try await store.folders(at: made.path)
        #expect(inside.folders.isEmpty && inside.parent == projects.path)

        // Connecting it needs no second Face ID: a draft's first message makes the conversation there with the unlock alone.
        try await Self.pause()
        let draft = store.newDraft(in: ProjectRef(made))
        let chat = try #require(try await store.send("Add a README", from: draft))
        #expect(keys.reasons.count == signed + 1)  // still only the creation's Face ID
        #expect(store.transcript(for: chat).workspace == made.path)
        try await store.stop(chat: chat)
        #expect(await eventually(.seconds(15)) { !store.isPebbleWorking })

        // The Mac's own refusals come back in its words; a name no folder can have never asks for Face ID.
        try await Self.pause()
        await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: "from the phone", in: projects.path) }
        #expect(store.notice?.message == "A folder with that name is already there.")
        store.notice = nil
        await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: "x", in: "/etc") }
        #expect(store.notice?.code == "not_allowed")
        store.notice = nil
        let before = keys.reasons.count
        await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: ".hidden", in: projects.path) }
        #expect(keys.reasons.count == before)  // no Face ID for a name that can't work
        await client.disconnect()
    }
}
