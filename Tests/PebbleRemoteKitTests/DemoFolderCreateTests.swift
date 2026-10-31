import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// "Try the demo" with "New Folder" (lane F, proposal v0.6): the demo Mac makes folders as the bridge does, with Face ID,
// in the bridge's words, and a folder made here connects with the unlock alone for ten minutes. Pace 0, the demo's clock
// a test's own.

private let projects = DemoFolders.home + "/Projects"

@MainActor
private func demoStore(now: @escaping @Sendable () -> Date = { Fixture.t0 }) async -> RemoteStore {
    let client = DemoClient(pace: 0, autoplay: false, now: now)
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.start()
    _ = await eventually { store.pebble != nil && store.chats.count == DemoData.seededChats }
    return store
}

/// A connected demo client, for the calls the store does not make (a plain call for a folder made a moment ago).
private func demoClient(now: @escaping @Sendable () -> Date = { Fixture.t0 }) async -> DemoClient {
    let client = DemoClient(pace: 0, autoplay: false, now: now)
    await client.connect(to: DemoClient.pairedMac(at: Fixture.t0))
    return client
}

@MainActor
@Test func theDemoMakesAFolderAndListsItWhereItSorts() async throws {
    let store = await demoStore()
    #expect(store.bridge?.methods.contains("remote.folder_create") == true)
    #expect(store.bridge?.elevated.contains("remote.folder_create") == true)
    let made = try await store.createFolder(named: "my-ideas", in: projects)
    #expect(made == FolderEntry(name: "my-ideas", path: projects + "/my-ideas", isProject: false))
    let listing = try await store.folders(at: projects)
    #expect(listing.folders.map(\.name) == ["my-ideas", "pebble-docs", "pebble-ios", "pebble-site", "pebble-web", "sketches"])
    #expect(listing.folders.first { $0.name == "my-ideas" }?.isProject == false)
    // The new folder opens empty, with its parent above it.
    let inside = try await store.folders(at: made.path)
    #expect(inside.folders.isEmpty && inside.parent == projects && inside.home == DemoFolders.home)
    // The home folder is a parent too, and a made folder can hold another.
    let top = try await store.createFolder(named: "Scratch", in: DemoFolders.home)
    #expect(try await store.folders(at: nil).folders.map(\.name).contains("Scratch"))
    let nested = try await store.createFolder(named: "inner", in: top.path)
    #expect(try await store.folders(at: top.path).folders == [nested])
}

@MainActor
@Test func theDemoRefusesWhatTheBridgeRefuses() async throws {
    let store = await demoStore()
    // A name already there (the Mac ignores case), in the bridge's words and with no code.
    for name in ["pebble-web", "PEBBLE-WEB"] {
        await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: name, in: projects) }
        #expect(store.notice?.message == "A folder with that name is already there." && store.notice?.code == nil)
        store.notice = nil
    }
    // A parent that is gone, and one outside the home folder.
    await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: "x", in: projects + "/nowhere") }
    #expect(store.notice?.message == "That folder isn't on your Mac anymore.")
    store.notice = nil
    for parent in ["/etc", DemoFolders.home + "/..", "/"] {
        await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: "x", in: parent) }
        #expect(store.notice?.code == BridgeErrorCode.notAllowed.rawValue, "\(parent)")
        store.notice = nil
    }
    // A name no folder can have never reaches the demo Mac.
    await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: ".hidden", in: projects) }
    #expect(store.notice?.message == StoreWords.folderNameDot)
    #expect(!(try await store.folders(at: projects)).folders.contains { $0.name == ".hidden" })
}

@MainActor
@Test func theDemoNeedsFaceIDToMakeAFolderAndTheDemoAlwaysAgrees() async throws {
    let client = await demoClient()
    await #expect(throws: RemoteCallError.self) {
        _ = try await client.call("remote.folder_create", ["parent": .string(projects), "name": "plain"])
    }
    do {
        _ = try await client.call("remote.folder_create", ["parent": .string(projects), "name": "plain"])
    } catch RemoteCallError.refused(let refusal) {
        #expect(refusal.code == BridgeErrorCode.proofRequired.rawValue)
    }
    let made = try await client.callElevated(
        "remote.folder_create", ["parent": .string(projects), "name": "proven"], reason: "Create a folder: proven")
    #expect(made["path"]?.string == projects + "/proven" && made["is_project"]?.bool == false)
    #expect(Set(made.object?.keys.map { $0 } ?? []) == ["path", "name", "is_project"])
    // Not a string: the bridge's generic refusal.
    do {
        _ = try await client.callElevated("remote.folder_create", ["parent": .string(projects)], reason: "x")
        Issue.record("a call without a name was accepted")
    } catch RemoteCallError.refused(let refusal) {
        #expect(refusal.code == BridgeErrorCode.badRequest.rawValue)
    }
}

@MainActor
@Test func aFolderMadeInTheDemoConnectsWithTheUnlockAloneForTenMinutes() async throws {
    let clock = DemoClock()
    let client = await demoClient(now: { clock.date })
    let made = try await client.callElevated(
        "remote.folder_create", ["parent": .string(projects), "name": "fresh"], reason: "Create a folder: fresh")
    let path = try #require(made["path"]?.string)
    // Not yet known to any conversation: a plain call for another new folder wants Face ID, this one does not.
    let other = DemoFolders.newProject
    do {
        _ = try await client.call("new_chat", ["workspace": .string(other)])
        Issue.record("a folder no conversation uses was accepted without Face ID")
    } catch RemoteCallError.refused(let refusal) {
        #expect(refusal.code == BridgeErrorCode.proofRequired.rawValue)
    }
    clock.advance(RemoteStore.madeFolderMemory)  // exactly ten minutes: still counted
    let chat = try await client.call("new_chat", ["workspace": .string(path)])
    #expect(chat["workspace"]?.string == path)
    // Ten minutes and a second later, another folder made then asks again.
    let later = try await client.callElevated(
        "remote.folder_create", ["parent": .string(projects), "name": "later"], reason: "Create a folder: later")
    clock.advance(RemoteStore.madeFolderMemory + 1)
    do {
        _ = try await client.call("new_chat", ["workspace": .string(try #require(later["path"]?.string))])
        Issue.record("a folder made ten minutes ago was accepted without Face ID")
    } catch RemoteCallError.refused(let refusal) {
        #expect(refusal.code == BridgeErrorCode.proofRequired.rawValue)
    }
}

@MainActor
@Test func theStoreConnectsAFolderMadeInTheDemoWithoutAsking() async throws {
    let store = await demoStore()
    try await store.stop(chat: DemoData.loginChat)  // Pebble runs one task at a time
    #expect(await eventually { !store.liveRuns.contains { $0.id == DemoData.loginRun } })
    let made = try await store.createFolder(named: "from-the-phone", in: projects)
    try await store.setWorkspace(DemoData.weatherChat, to: ProjectRef(made))
    #expect(store.chats.first { $0.id == DemoData.weatherChat }?.project == "from-the-phone")
    #expect(store.isKnownProject(made.path))
    // And a conversation started there: the draft's first message makes it.
    let second = try await store.createFolder(named: "second", in: projects)
    let draft = store.newDraft(in: ProjectRef(second))
    let chat = try #require(try await store.send("Start here", from: draft))
    #expect(store.transcript(for: chat).workspace == second.path)
}

/// The demo's clock, moved by the test.
private final class DemoClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Fixture.t0
    var date: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
