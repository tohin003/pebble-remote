import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Where conversations start (lane N): the Mac sidebar's project rule, "Connect a project" over the Mac's folders
// (proposal v0.5, `remote.folders`), the composer's "+" menu, and new conversations that reach the Mac only with their
// first message (drafts). Against a small Pebble whose conversations change as Pebble's do.

private let web = "/Users/me/Projects/pebble-web"
private let docs = "/Users/me/Projects/pebble-docs"
private let ios = "/Users/me/Projects/pebble-ios"

/// Pebble's conversations and their folders, changing with new_chat, set_workspace and send as Pebble's would (state()
/// lists only conversations that hold something, as LISTED_CHATS does). `refuse` makes the next call of a method fail.
private final class ProjectsPebble: Sendable {
    struct Row: Sendable {
        var id: String
        var title: String
        var workspace: String?
        var updated: Double
        var listed: Bool
    }

    private let rows: Mutex<[Row]>
    private let refusals = Mutex<[String: Int]>([:])
    private let made = Mutex(0)

    init(_ rows: [Row]) {
        self.rows = Mutex(rows)
    }

    /// The next `count` calls of `method` are refused, as Pebble refuses.
    func refuse(_ method: String, times count: Int = 1) {
        refusals.withLock { $0[method] = count }
    }

    func answer(_ method: String, _ params: JSONValue) throws -> JSONValue {
        if refusals.withLock({ left in
            guard let count = left[method], count > 0 else { return false }
            left[method] = count - 1
            return true
        }) {
            let code = method == "set_workspace" || method == "new_chat" ? "proof_required" : nil
            throw RemoteCallError.refused(PersonFacingError(message: "Refused by Pebble.", code: code))
        }
        let id = params["id"]?.string ?? ""
        switch method {
        case "state":
            let listed = rows.withLock { $0.filter(\.listed) }
            return Fixture.stateJSON(
                chats: listed.map { Fixture.chatRow($0.id, $0.title, workspace: $0.workspace, updated: $0.updated) })
        case "get_chat", "remote.chat_tail":
            return chat(id)
        case "new_chat":
            let number = made.withLock { count in
                count += 1
                return count
            }
            let row = Row(
                id: "c-new\(number)", title: "New conversation", workspace: params["workspace"]?.string, updated: 500,
                listed: false)
            rows.withLock { $0.append(row) }
            return chat(row.id)
        case "set_workspace":
            rows.withLock { list in
                if let index = list.firstIndex(where: { $0.id == id }) { list[index].workspace = params["path"]?.string }
            }
            return chat(id)
        case "send":
            rows.withLock { list in
                if let index = list.firstIndex(where: { $0.id == id }) { list[index].listed = true }
            }
            return ["message_id": .string("m-\(id)"), "run_id": .string("r-\(id)")]
        case "attach_bytes":
            return ["id": .string("src-\(params["name"]?.string ?? "")"), "name": params["name"] ?? "", "kind": "file"]
        case "attach_url":
            return ["id": "src-url", "name": params["url"] ?? "", "characters": 2400]
        case "terminal_propose":
            return ["status": "pending", "action_id": "a-cmd"]
        default:
            return .bool(true)
        }
    }

    /// Pebble's chat(): the head of the conversation with its folder.
    private func chat(_ id: String) -> JSONValue {
        let row = rows.withLock { $0.first { $0.id == id } }
        return [
            "id": .string(id), "title": .string(row?.title ?? ""), "workspace": row?.workspace.map(JSONValue.string) ?? .null,
            "updated": .double(Fixture.t0.timeIntervalSince1970 + (row?.updated ?? 0)), "trashed": false, "messages": [],
            "actions": [], "artifacts": [], "runs": [], "questions": [], "plan": .null,
        ]
    }
}

/// A store connected to `pebble` through a bridge that offers proposal v0.5's methods.
@MainActor
private func projectsStore(
    _ rows: [ProjectsPebble.Row] = [
        .init(id: "c1", title: "Fix the login redirect loop", workspace: web, updated: 10, listed: true),
        .init(id: "c2", title: "Update the README", workspace: docs, updated: 5, listed: true),
    ],
    elevated: Set<String> = ["approve", "approve_simple", "setting"],
    extra: @escaping @Sendable (String, JSONValue) throws -> JSONValue? = { _, _ in nil }
) async -> (RemoteStore, FakeClient, ProjectsPebble) {
    let pebble = ProjectsPebble(rows)
    let fake = FakeClient { method, params in try extra(method, params) ?? pebble.answer(method, params) }
    var methods = BridgeInfo.test().methods
    methods.formUnion(["set_workspace", "attach_url", "attach_bytes", "remove_source", "terminal_propose", "remote.folders"])
    let store = RemoteStore(client: fake)
    fake.push(
        .welcome(
            BridgeInfo(
                bridgeVersion: "0.5", macName: "Studio Mac", pebbleRunning: true, pebbleVersion: "1.9.29",
                methods: methods, elevated: elevated, resumed: false)))
    _ = await eventually { store.pebble != nil }
    return (store, fake, pebble)
}

// MARK: - The domain

@Test func folderListingsReadTheBridgesShape() throws {
    let home = try #require(
        FolderListing(json: [
            "home": "/Users/me", "path": "/Users/me", "parent": .null,
            "folders": [
                ["name": "Projects", "path": "/Users/me/Projects", "is_project": false],
                ["path": "/Users/me/pebble", "is_project": true],  // no name: its last path component
                ["name": "no path"],  // not a folder Pebble Remote can open: left out
            ],
        ]))
    #expect(home.isHome && home.parent == nil && home.name == "me")
    #expect(home.folders.map(\.name) == ["Projects", "pebble"])
    #expect(home.folders.map(\.isProject) == [false, true])
    let inside = try #require(
        FolderListing(json: ["home": "/Users/me", "path": "/Users/me/Projects", "parent": "/Users/me", "folders": []]))
    #expect(!inside.isHome && inside.parent == "/Users/me" && inside.name == "Projects" && inside.folders.isEmpty)
    #expect(FolderListing(json: ["home": "/Users/me", "folders": []]) == nil)  // no path: unreadable
}

@Test func aFolderIsNamedByItsLastPathComponent() {
    #expect(ProjectRef.folderName(web) == "pebble-web")
    #expect(ProjectRef.folderName(web + "/") == "pebble-web")
    #expect(ProjectRef(folder: ios) == ProjectRef(path: ios, name: "pebble-ios"))
    #expect(ProjectRef(FolderEntry(name: "Pebble iOS", path: ios, isProject: true)).name == "Pebble iOS")
}

@Test func onlyAddressesPebbleReadsAreKeptForADraft() {
    #expect(RemoteStore.isReadableWebAddress("https://docs.example.com/guide"))
    #expect(RemoteStore.isReadableWebAddress("https://docs.example.com:443/guide?x=1"))
    for refused in [
        "http://docs.example.com", "https://user:secret@docs.example.com", "https://docs.example.com:8443/",
        "https:///nohost", "docs.example.com", "https://docs.example.com/a b", "",
    ] {
        #expect(!RemoteStore.isReadableWebAddress(refused), "\(refused)")
    }
}

// MARK: - Your space: the Mac sidebar's projects

@MainActor
@Test func recentProjectsFollowPebblesSidebarRule() async {
    // Seven conversations in six folders (project-2 twice) and one in Companion: each folder once, newest first, at
    // most five, as App.vue's recentProjects.
    var rows = (1...6).map {
        ProjectsPebble.Row(id: "c\($0)", title: "t\($0)", workspace: "/p/project-\($0)", updated: Double($0), listed: true)
    }
    rows.append(.init(id: "c7", title: "t7", workspace: "/p/project-2", updated: 100, listed: true))
    rows.append(.init(id: "c8", title: "Companion", workspace: nil, updated: 200, listed: true))
    let (store, _, _) = await projectsStore(rows)
    #expect(store.recentProjects.map(\.name) == ["project-2", "project-6", "project-5", "project-4", "project-3"])
    // The Mac takes five, then leaves out the open conversation's own project (it has its own row).
    #expect(store.recentProjects(leavingOut: "/p/project-6").map(\.name) == ["project-2", "project-5", "project-4", "project-3"])
    #expect(store.isKnownProject("/p/project-1") && !store.isKnownProject("/p/elsewhere"))
}

// MARK: - Connect a project: the Mac's folders

@MainActor
@Test func theMacsFoldersComeFromRemoteFolders() async throws {
    let (store, fake, _) = await projectsStore(extra: { method, params in
        guard method == "remote.folders" else { return nil }
        let path = params["path"]?.string ?? "/Users/me"
        return [
            "home": "/Users/me", "path": .string(path), "parent": path == "/Users/me" ? .null : "/Users/me",
            "folders": [["name": "pebble-ios", "path": .string(ios), "is_project": true]],
        ]
    })
    let home = try await store.folders(at: nil)
    #expect(fake.calls("remote.folders").last?.params == [:])  // the home folder: no path
    #expect(home.isHome && home.folders.first?.isProject == true)
    let projects = try await store.folders(at: "/Users/me/Projects")
    #expect(fake.calls("remote.folders").last?.params == ["path": "/Users/me/Projects"])
    #expect(projects.parent == "/Users/me")
    #expect(fake.calls("remote.folders").allSatisfy { !$0.elevated })  // it needs the unlock only
}

@MainActor
@Test func aFolderTheBridgeWontListSaysWhyInItsWords() async {
    let (store, _, _) = await projectsStore(extra: { method, _ in
        guard method == "remote.folders" else { return nil }
        throw RemoteCallError.refused(
            PersonFacingError(message: "Pebble Remote shows folders inside your home folder only.", code: "not_allowed"))
    })
    await #expect(throws: RemoteCallError.self) { _ = try await store.folders(at: "/etc") }
    #expect(store.notice?.message == "Pebble Remote shows folders inside your home folder only.")
}

@MainActor
@Test func movingAConversationAsksFaceIDOnlyForAFolderNoConversationUses() async throws {
    let (store, fake, _) = await projectsStore()
    // A project another conversation uses: the unlock is enough.
    try await store.setWorkspace("c1", to: ProjectRef(folder: docs))
    let known = try #require(fake.calls("set_workspace").last)
    #expect(known.params == ["id": "c1", "path": .string(docs)] && !known.elevated)
    #expect(store.chats.first { $0.id == "c1" }?.project == "pebble-docs")  // returned once the store shows it
    // A folder no conversation uses: Face ID at once, naming the folder.
    try await store.setWorkspace("c1", to: ProjectRef(folder: ios))
    let new = try #require(fake.calls("set_workspace").last)
    #expect(new.elevated && new.reason == "Connect a project: pebble-ios")
    #expect(store.chats.first { $0.id == "c1" }?.project == "pebble-ios")
    // Back to Companion (Pebble's `path: null`).
    try await store.setWorkspace("c1", to: nil)
    let companion = try #require(fake.calls("set_workspace").last)
    #expect(companion.params == ["id": "c1", "path": .null] && !companion.elevated)
    #expect(store.chats.first { $0.id == "c1" }?.project == nil)
}

@MainActor
@Test func aBridgeThatWantsFaceIDForAMoveGetsItOnce() async throws {
    let (store, fake, pebble) = await projectsStore()
    pebble.refuse("set_workspace")  // proof_required on the plain call
    try await store.setWorkspace("c2", to: ProjectRef(folder: web))
    let calls = fake.calls("set_workspace")
    #expect(calls.map(\.elevated) == [false, true])
    #expect(calls.last?.reason == "Connect a project: pebble-web")
    #expect(store.notice == nil)
}

// MARK: - The composer's "+" menu

@MainActor
@Test func aWebSourceIsPebblesSourceForTheNextTask() async throws {
    let (store, fake, _) = await projectsStore()
    let source = try await store.attachURL("  https://docs.example.com/guide ", to: "c1")
    #expect(fake.calls("attach_url").last?.params == ["id": "c1", "url": "https://docs.example.com/guide"])
    #expect(source.kind == "url" && source.id == "src-url" && source.name == "https://docs.example.com/guide")
    #expect(store.attachments["c1"]?.map(\.id) == ["src-url"])
    try await store.send("Summarize the guide", in: "c1")
    #expect(fake.calls("send").last?.params["source_ids"] == ["src-url"])
    #expect(store.attachments["c1"] == nil)
}

@MainActor
@Test func aTerminalCommandGoesToPebblesReviewWithFaceID() async throws {
    let (store, fake, _) = await projectsStore(elevated: ["approve", "setting", "terminal_propose"])
    try await store.proposeTerminalCommand(" git status --short ", network: true, in: "c1")
    let call = try #require(fake.calls("terminal_propose").last)
    #expect(call.elevated && call.reason == "Terminal command: git status --short")
    #expect(call.params == ["id": "c1", "command": "git status --short", "network": true])
    // It returns once the conversation was read again, with Pebble's card in it.
    let methods = fake.methods
    let proposed = try #require(methods.lastIndex(of: "terminal_propose"))
    #expect(methods[proposed...].contains("remote.chat_tail"))
    try await store.proposeTerminalCommand("   ", network: false, in: "c1")
    #expect(fake.calls("terminal_propose").count == 1)  // no command: nothing sent
}

@MainActor
@Test func anOlderBridgeTakesTheCommandPlainOrAsksOnce() async throws {
    let (store, fake, pebble) = await projectsStore()
    try await store.proposeTerminalCommand("npm test", network: false, in: "c1")
    #expect(fake.calls("terminal_propose").map(\.elevated) == [false])
    pebble.refuse("terminal_propose")
    await #expect(throws: RemoteCallError.self) {
        try await store.proposeTerminalCommand("npm test", network: false, in: "c1")
    }
    #expect(store.notice?.message == "Refused by Pebble.")  // not proof_required: no second try
}

// MARK: - New conversations (drafts)

/// Calls that act on the Mac for a conversation (reads after connecting may still be under way, and don't count).
private let acting: Set<String> = ["new_chat", "set_workspace", "attach_bytes", "attach_url", "send", "terminal_propose"]

@MainActor
@Test func aDraftReachesTheMacOnlyWithItsFirstMessage() async throws {
    let (store, fake, _) = await projectsStore()
    let draft = store.newDraft()
    #expect(draft.place == nil && draft.chatID == nil && !draft.isSent)
    #expect(store.draft(draft.id) === draft)
    store.move(draft, to: store.recentProjects.first)
    try store.attach(Data([1, 2, 3]), name: "notes.txt", to: draft)
    try store.attachURL("https://docs.example.com/guide", to: draft)
    #expect(store.pendingAttachments(for: draft).map(\.kind) == ["file", "url"])
    #expect(try await store.send("   ", from: draft) == nil)  // no words: nothing to send
    #expect(!fake.calls.contains { acting.contains($0.method) })  // nothing reached the Mac
    store.discardDraft(draft.id)
    #expect(store.draft(draft.id) == nil)
}

@MainActor
@Test func aDraftBecomesAConversationWithItsFirstMessage() async throws {
    let (store, fake, _) = await projectsStore()
    let draft = store.newDraft(in: store.recentProjects.first)
    #expect(draft.place?.path == web)
    try store.attach(Data([1, 2, 3]), name: "notes.txt", to: draft)
    try store.attachURL("https://docs.example.com/guide", to: draft)
    let chat = try #require(try await store.send("Read these and fix the login", from: draft))
    let order = fake.methods.filter { ["new_chat", "attach_bytes", "attach_url", "send"].contains($0) }
    #expect(order == ["new_chat", "attach_bytes", "attach_url", "send"])
    let made = try #require(fake.calls("new_chat").last)
    #expect(made.params == ["workspace": .string(web)] && !made.elevated)
    #expect(fake.calls("attach_bytes").last?.params["id"] == .string(chat))
    #expect(fake.calls("attach_url").last?.params == ["id": .string(chat), "url": "https://docs.example.com/guide"])
    let sent = try #require(fake.calls("send").last)
    #expect(sent.params["id"] == .string(chat) && sent.params["text"] == "Read these and fix the login")
    #expect(sent.params["source_ids"] == ["src-notes.txt", "src-url"])
    #expect(draft.isSent && draft.chatID == chat && draft.pending.isEmpty)
    let transcript = store.transcript(for: chat)
    #expect(transcript.workspace == web && transcript.hasMessages)
    #expect(await eventually { store.chats.contains { $0.id == chat && $0.project == "pebble-web" } })
}

@MainActor
@Test func aDraftInCompanionStartsWithoutAFolder() async throws {
    let (store, fake, _) = await projectsStore()
    let draft = store.newDraft()
    let chat = try #require(try await store.send("What's the weather in Lisbon?", from: draft))
    #expect(fake.calls("new_chat").last?.params == [:])
    #expect(store.transcript(for: chat).workspace == nil)
}

@MainActor
@Test func aDraftInAFolderNoConversationUsesIsMadeWithOneFaceID() async throws {
    let (store, fake, _) = await projectsStore()
    let draft = store.newDraft(in: ProjectRef(folder: ios))
    let chat = try #require(try await store.send("Add a settings screen", from: draft))
    let made = try #require(fake.calls("new_chat").last)
    #expect(made.elevated && made.reason == "Connect a project: pebble-ios")
    #expect(made.params == ["workspace": .string(ios)])
    #expect(fake.calls("set_workspace").isEmpty)  // one call, no empty conversation left behind on a refusal
    #expect(store.transcript(for: chat).workspace == ios)
    #expect(await eventually { store.isKnownProject(ios) })
}

@MainActor
@Test func aSendCutShortGoesOnInTheSameConversation() async throws {
    // Pebble made the conversation, then refused the message. The person moves the draft to Companion and sends
    // again: no second conversation; the made one moves there, then the message goes.
    let (store, fake, pebble) = await projectsStore()
    let draft = store.newDraft(in: store.recentProjects.first)
    pebble.refuse("send")
    await #expect(throws: RemoteCallError.self) { _ = try await store.send("First try", from: draft) }
    let made = try #require(draft.chatID)
    #expect(!draft.isSent)
    store.move(draft, to: nil)
    let chat = try #require(try await store.send("Second try", from: draft))
    #expect(chat == made)
    #expect(fake.calls("new_chat").count == 1)
    #expect(fake.calls("set_workspace").last?.params == ["id": .string(made), "path": .null])
    #expect(fake.calls("send").last?.params["text"] == "Second try")
    #expect(draft.isSent)
}

@MainActor
@Test func aDraftTakesUpToTenAttachmentsAndOnlyAddressesPebbleReads() async throws {
    let (store, _, _) = await projectsStore()
    let draft = store.newDraft()
    #expect(throws: RemoteCallError.self) { try store.attachURL("http://docs.example.com", to: draft) }
    #expect(store.notice?.message == "Enter a public https:// URL without credentials or a custom port.")
    for index in 0..<10 { try store.attach(Data([UInt8(index)]), name: "f\(index).txt", to: draft) }
    #expect(throws: RemoteCallError.self) { try store.attachURL("https://docs.example.com", to: draft) }
    #expect(store.notice?.message == "Use up to ten attachments per message.")
    let first = try #require(store.pendingAttachments(for: draft).first)
    try await store.removeAttachment(first, from: draft)
    #expect(draft.pending.count == 9)
}

@MainActor
@Test func aTerminalCommandInADraftMakesTheConversationFirst() async throws {
    let (store, fake, _) = await projectsStore(elevated: ["approve", "setting", "terminal_propose"])
    let draft = store.newDraft(in: store.recentProjects.first)
    try store.attachURL("https://docs.example.com/guide", to: draft)
    let chat = try await store.proposeTerminalCommand("git status --short", network: false, from: draft)
    let order = fake.methods.filter { ["new_chat", "attach_url", "terminal_propose"].contains($0) }
    #expect(order == ["new_chat", "attach_url", "terminal_propose"])
    #expect(fake.calls("terminal_propose").last?.params["id"] == .string(chat))
    #expect(draft.isSent && draft.chatID == chat)
    #expect(store.attachments[chat]?.map(\.id) == ["src-url"])  // the page waits for the next message
}

@MainActor
@Test func newChatStillStartsInAProjectByItsPath() async throws {
    let (store, fake, _) = await projectsStore()
    _ = try await store.newChat(firstMessage: "Hello", in: ProjectRef(folder: docs))
    #expect(fake.calls("new_chat").last?.params == ["workspace": .string(docs)])
    #expect(fake.calls("new_chat").last?.elevated == false)
    #expect(fake.calls("send").last?.params["text"] == "Hello")
}
