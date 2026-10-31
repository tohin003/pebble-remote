import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// "Try the demo" with lane N's work: the demo Mac's folders, a conversation started in a folder no conversation used
// (Face ID agrees in the demo), the composer's "+" menu, and Pebble's own refusals. Pace 0: scripts run without waiting.

@MainActor
private func demoStore() async -> RemoteStore {
    let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.start()
    _ = await eventually { store.pebble != nil && store.chats.count == DemoData.seededChats }
    return store
}

/// The demo opens with a task working, and Pebble runs one task at a time.
@MainActor
private func stopTheLoginRun(_ store: RemoteStore) async throws {
    try await store.stop(chat: DemoData.loginChat)
    #expect(await eventually { !store.liveRuns.contains { $0.id == DemoData.loginRun } })
}

@MainActor
@Test func theDemoListsItsMacsFolders() async throws {
    let store = await demoStore()
    #expect(store.bridge?.methods.isSuperset(of: ["remote.folders", "set_workspace", "attach_url", "terminal_propose"]) == true)
    let home = try await store.folders(at: nil)
    #expect(home.isHome && home.path == DemoFolders.home && home.parent == nil)
    #expect(home.folders.map(\.name) == ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Projects"])
    let projects = try await store.folders(at: DemoFolders.home + "/Projects")
    #expect(projects.parent == DemoFolders.home)
    #expect(projects.folders.map(\.name) == ["pebble-docs", "pebble-ios", "pebble-site", "pebble-web", "sketches"])
    #expect(projects.folders.filter(\.isProject).map(\.name) == ["pebble-docs", "pebble-ios", "pebble-site", "pebble-web"])
    await #expect(throws: RemoteCallError.self) { _ = try await store.folders(at: "/etc") }
    #expect(store.notice?.code == BridgeErrorCode.notAllowed.rawValue)
}

@MainActor
@Test func aDemoConversationStartsInAFolderNoConversationUsed() async throws {
    let store = await demoStore()
    try await stopTheLoginRun(store)
    #expect(!store.isKnownProject(DemoFolders.newProject))
    let draft = store.newDraft(in: ProjectRef(folder: DemoFolders.newProject))
    try store.attachURL("https://docs.example.com/guide", to: draft)
    let chat = try #require(try await store.send("Add a settings screen", from: draft))
    #expect(draft.isSent && store.isKnownProject(DemoFolders.newProject))
    #expect(store.recentProjects.first?.name == "pebble-ios")
    let transcript = store.transcript(for: chat)
    #expect(transcript.workspace == DemoFolders.newProject && transcript.project == "pebble-ios")
    #expect(
        await eventually {
            transcript.items.contains { if case .runEnd(_, _, .completed, _, _) = $0 { true } else { false } }
        })
    // Listed under Recent Conversations, in its project (the demo's clock stands still, so not necessarily first).
    #expect(await eventually { store.chats.contains { $0.id == chat && $0.project == "pebble-ios" } })
}

@MainActor
@Test func theDemoRefusesWhatPebbleRefuses() async throws {
    let store = await demoStore()
    // Pebble's own words for the home folder.
    await #expect(throws: RemoteCallError.self) {
        _ = try await store.newChat(firstMessage: nil, in: ProjectRef(folder: DemoFolders.home))
    }
    #expect(store.notice?.message == "Choose a project folder rather than your home folder or disk root.")
    // A conversation's project doesn't change while a task runs.
    await #expect(throws: RemoteCallError.self) {
        try await store.setWorkspace(DemoData.weatherChat, to: ProjectRef(folder: DemoFolders.home + "/Projects/pebble-web"))
    }
    #expect(store.notice?.message == "Stop the current task before changing its project.")
    try await stopTheLoginRun(store)
    // A terminal command needs a project: the weather conversation is in Companion.
    await #expect(throws: RemoteCallError.self) {
        try await store.proposeTerminalCommand("ls", network: false, in: DemoData.weatherChat)
    }
    #expect(store.notice?.message == "Choose a project folder for this conversation first.")
}

@MainActor
@Test func aDemoConversationMovesAndReadsAWebPage() async throws {
    let store = await demoStore()
    try await stopTheLoginRun(store)
    let web = ProjectRef(folder: DemoFolders.home + "/Projects/pebble-web")
    try await store.setWorkspace(DemoData.weatherChat, to: web)
    #expect(store.chats.first { $0.id == DemoData.weatherChat }?.project == "pebble-web")
    try await store.setWorkspace(DemoData.weatherChat, to: nil)
    #expect(store.chats.first { $0.id == DemoData.weatherChat }?.project == nil)
    let page = try await store.attachURL("https://docs.example.com/guide", to: DemoData.weatherChat)
    #expect(page.kind == "url" && store.attachments[DemoData.weatherChat]?.contains(page) == true)
    await #expect(throws: RemoteCallError.self) {
        _ = try await store.attachURL("http://intranet.local", to: DemoData.weatherChat)
    }
    #expect(store.notice?.message == "Enter a public https:// URL without credentials or a custom port.")
}

@MainActor
@Test func theDemosTerminalCommandWaitsForPebblesReview() async throws {
    let store = await demoStore()
    try await stopTheLoginRun(store)
    let before = store.waiting.count
    try await store.proposeTerminalCommand("git status --short", network: false, in: DemoData.commitsChat)
    let card = try #require(
        store.waiting.compactMap { item -> ReviewItem? in
            if case .review(let card) = item, card.chatID == DemoData.commitsChat { card } else { nil }
        }.first)
    #expect(store.waiting.count == before + 1)
    #expect(card.kind == .command && card.title == "Run git status --short" && card.detail == "git status --short")
    try await store.approve(card)
    #expect(await eventually { store.waiting.count == before })
}
