import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// "New Folder" in Connect a project (lane F, proposal v0.6): the store's call and its Face ID, the names it refuses
// before asking, the Mac's own refusals, and the ten minutes in which a folder this phone made connects with the unlock
// alone (one Face ID for "make it and connect it"). Against a small Pebble that answers as the bridge does.

private let projects = "/Users/me/Projects"
private let fresh = "/Users/me/Projects/fresh"
private let web = "/Users/me/Projects/pebble-web"
private let docs = "/Users/me/Projects/pebble-docs"

/// The phone's clock, moved by the test.
private final class TestClock: Sendable {
    private let now = Mutex(Fixture.t0)
    var date: Date { now.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { now.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// Pebble's conversations and the bridge's `remote.folder_create`, as the mock answers it. `refuse` makes the next call of
/// a method fail.
private final class FolderPebble: Sendable {
    struct Row: Sendable {
        var id: String
        var workspace: String?
        var listed: Bool
    }

    private let rows = Mutex<[Row]>([
        Row(id: "c1", workspace: web, listed: true), Row(id: "c2", workspace: docs, listed: true),
        Row(id: "c3", workspace: nil, listed: true),
    ])
    private let made = Mutex(0)
    private let refusals = Mutex<[String: RemoteCallError]>([:])

    func refuse(_ method: String, with error: RemoteCallError) { refusals.withLock { $0[method] = error } }

    func answer(_ method: String, _ params: JSONValue) throws -> JSONValue {
        if let error = refusals.withLock({ $0.removeValue(forKey: method) }) { throw error }
        let id = params["id"]?.string ?? ""
        switch method {
        case "state":
            let listed = rows.withLock { $0.filter(\.listed) }
            return Fixture.stateJSON(chats: listed.map { Fixture.chatRow($0.id, "Chat \($0.id)", workspace: $0.workspace) })
        case "get_chat", "remote.chat_tail":
            return chat(id)
        case "new_chat":
            let number = made.withLock { count in
                count += 1
                return count
            }
            let row = Row(id: "c-new\(number)", workspace: params["workspace"]?.string, listed: false)
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
        case "remote.folder_create":
            let parent = params["parent"]?.string ?? "", name = params["name"]?.string ?? ""
            return ["path": .string(parent + "/" + name), "name": .string(name), "is_project": false]
        default:
            return .bool(true)
        }
    }

    private func chat(_ id: String) -> JSONValue {
        let row = rows.withLock { $0.first { $0.id == id } }
        return [
            "id": .string(id), "title": .string("Chat \(id)"), "workspace": row?.workspace.map(JSONValue.string) ?? .null,
            "updated": .double(Fixture.t0.timeIntervalSince1970), "trashed": false, "messages": [], "actions": [],
            "artifacts": [], "runs": [], "questions": [], "plan": .null,
        ]
    }
}

/// A store connected to `pebble` through a bridge that offers `remote.folder_create`, on a clock the test moves.
@MainActor
private func folderStore(
    methods extra: Set<String> = ["remote.folders", "remote.folder_create"]
) async -> (RemoteStore, FakeClient, FolderPebble, TestClock) {
    let pebble = FolderPebble()
    let fake = FakeClient { method, params in try pebble.answer(method, params) }
    var methods = BridgeInfo.test().methods
    methods.formUnion(["set_workspace", "attach_url", "terminal_propose"])
    methods.formUnion(extra)
    let store = RemoteStore(client: fake)
    let clock = TestClock()
    store.clock = { clock.date }
    fake.push(
        .welcome(
            BridgeInfo(
                bridgeVersion: "0.6", macName: "Studio Mac", pebbleRunning: true, pebbleVersion: "1.9.29",
                methods: methods, elevated: ["approve", "approve_simple", "setting", "remote.folder_create"],
                resumed: false)))
    _ = await eventually { store.pebble != nil }
    return (store, fake, pebble, clock)
}

private func proofRequired() -> RemoteCallError {
    .refused(PersonFacingError(message: "Confirm with Face ID to do this.", code: BridgeErrorCode.proofRequired.rawValue))
}

// MARK: - The call

@MainActor
@Test func aNewFolderIsMadeWithFaceIDAndAnsweredAsTheMacListsIt() async throws {
    let (store, fake, _, _) = await folderStore()
    let made = try await store.createFolder(named: "  fresh \n", in: projects)
    let call = try #require(fake.calls("remote.folder_create").last)
    #expect(call.elevated && call.reason == "Create a folder: fresh")
    #expect(call.params == ["parent": .string(projects), "name": "fresh"])  // trimmed, and exactly these two
    #expect(made == FolderEntry(name: "fresh", path: fresh, isProject: false))
    #expect(store.notice == nil)
    #expect(fake.calls.filter { $0.method == "remote.folder_create" }.count == 1)  // no plain try first
}

@MainActor
@Test func theFaceIDSentenceIsOneLineEvenForALongOrOddName() async throws {
    let (store, fake, _, _) = await folderStore()
    let long = String(repeating: "x", count: 200)
    try await store.createFolder(named: long, in: projects)
    let reason = try #require(fake.calls("remote.folder_create").last?.reason)
    #expect(reason.hasPrefix("Create a folder: xxx") && reason.count <= "Create a folder: ".count + StoreWords.faceIDDetailLength)
    #expect(!reason.contains("\n"))
}

@MainActor
@Test func aNameNoFolderCanHaveIsRefusedBeforeFaceIDInTheBridgesWords() async throws {
    let (store, fake, _, _) = await folderStore()
    let cases: [(String, String)] = [
        ("", StoreWords.folderNameEmpty), ("   \n ", StoreWords.folderNameEmpty), (".", StoreWords.folderNameDot),
        ("..", StoreWords.folderNameDot), (".hidden", StoreWords.folderNameDot), ("a/b", StoreWords.folderNameSeparator),
        ("a:b", StoreWords.folderNameSeparator), ("line\nbreak", StoreWords.folderNameControl),
        ("bell\u{7}", StoreWords.folderNameControl), (String(repeating: "x", count: 256), StoreWords.folderNameTooLong),
        (String(repeating: "\u{E9}", count: 128), StoreWords.folderNameTooLong),
    ]
    for (name, words) in cases {
        await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: name, in: projects) }
        #expect(store.notice?.message == words, "\(name.prefix(12).debugDescription)")
        store.notice = nil
    }
    #expect(fake.calls("remote.folder_create").isEmpty)  // not one of them asked for Face ID
    #expect(store.madeFolders.isEmpty)
}

@MainActor
@Test func theMacsRefusalIsShownInItsWordsAndRemembersNothing() async throws {
    let (store, fake, pebble, _) = await folderStore()
    pebble.refuse(
        "remote.folder_create", with: .refused(PersonFacingError(message: "A folder with that name is already there.")))
    await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: "fresh", in: projects) }
    #expect(store.notice?.message == "A folder with that name is already there.")
    #expect(fake.calls("remote.folder_create").last?.elevated == true)  // it did ask for Face ID: the Mac said no
    #expect(!store.isRecentlyMade(fresh))
    store.notice = nil
    pebble.refuse(
        "remote.folder_create",
        with: .refused(PersonFacingError(message: "Pebble Remote shows folders inside your home folder only.", code: "not_allowed")))
    await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: "x", in: "/etc") }
    #expect(store.notice?.code == "not_allowed")
}

@MainActor
@Test func cancellingFaceIDIsNotAFailureAndRemembersNothing() async throws {
    let (store, _, pebble, _) = await folderStore()
    pebble.refuse("remote.folder_create", with: .cancelledByPerson)
    await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: "fresh", in: projects) }
    #expect(store.notice == nil)
    #expect(!store.isRecentlyMade(fresh) && store.madeFolders.isEmpty)
}

@MainActor
@Test func anAnswerThatIsNotAFolderIsUnreadable() async throws {
    let fake = FakeClient { method, _ in method == "remote.folder_create" ? ["ok": true] : .bool(true) }
    let store = RemoteStore(client: fake)
    await #expect(throws: RemoteCallError.self) { _ = try await store.createFolder(named: "fresh", in: projects) }
    #expect(store.notice?.code == StoreWords.Code.unreadable)
    #expect(!store.isRecentlyMade(fresh))
}

// MARK: - The ten minutes: one Face ID for "make it and connect it"

@MainActor
@Test func aFolderMadeHereConnectsWithTheUnlockAlone() async throws {
    let (store, fake, _, _) = await folderStore()
    let one = try await store.createFolder(named: "one", in: projects)
    let two = try await store.createFolder(named: "two", in: projects)
    #expect(store.isRecentlyMade(one.path) && !store.isKnownProject(one.path))
    // Moving a conversation there: a plain call, no second Face ID.
    try await store.setWorkspace("c3", to: ProjectRef(one))
    let moved = try #require(fake.calls("set_workspace").last)
    #expect(!moved.elevated && moved.params == ["id": "c3", "path": .string(one.path)])
    // A new conversation there (a draft's first message): the same.
    let draft = store.newDraft(in: ProjectRef(two))
    _ = try await store.send("Add a README", from: draft)
    let opened = try #require(fake.calls("new_chat").last)
    #expect(!opened.elevated && opened.params == ["workspace": .string(two.path)])
    #expect(fake.calls("remote.folder_create").count == 2)  // and each Face ID was for making a folder
}

@MainActor
@Test func onlyThatExactFolderCountsForThePhoneThatMadeIt() async throws {
    let (store, fake, _, _) = await folderStore()
    let made = try await store.createFolder(named: "fresh", in: projects)
    for path in [made.path + "/", made.path + "/inner", projects, projects + "/lib", "/Users/me"] {
        try await store.setWorkspace("c3", to: ProjectRef(folder: path))
        let call = try #require(fake.calls("set_workspace").last)
        #expect(call.elevated, "\(path)")  // a folder no conversation uses and this phone didn't make: Face ID
    }
    // A project a conversation uses still goes plain, as before.
    try await store.setWorkspace("c3", to: ProjectRef(folder: docs))
    #expect(fake.calls("set_workspace").last?.elevated == false)
}

@MainActor
@Test func tenMinutesAfterMakingItTheFolderAsksForFaceIDAgain() async throws {
    let (store, fake, _, clock) = await folderStore()
    let made = try await store.createFolder(named: "fresh", in: projects)
    clock.advance(TimeInterval(RemoteStore.madeFolderMemory))  // exactly ten minutes: the bridge still counts it
    #expect(store.isRecentlyMade(made.path))
    clock.advance(1)
    #expect(!store.isRecentlyMade(made.path))
    try await store.setWorkspace("c3", to: ProjectRef(made))
    let call = try #require(fake.calls("set_workspace").last)
    #expect(call.elevated && call.reason == "Connect a project: fresh")
}

@MainActor
@Test func aBridgeThatDoesNotRememberTheFolderGetsFaceIDOnceMore() async throws {
    let (store, fake, pebble, _) = await folderStore()
    let made = try await store.createFolder(named: "fresh", in: projects)
    pebble.refuse("set_workspace", with: proofRequired())  // an older bridge, or the ten minutes ended on the Mac
    try await store.setWorkspace("c3", to: ProjectRef(made))
    #expect(fake.calls("set_workspace").map(\.elevated) == [false, true])
    #expect(store.notice == nil)
    #expect(store.transcript(for: "c3").workspace == made.path)
}

@MainActor
@Test func theStoreKeepsAtMostSixtyFourMadeFoldersAndDropsTheOld() async throws {
    let (store, _, _, clock) = await folderStore()
    for number in 0..<70 {
        try await store.createFolder(named: "f\(number)", in: projects)
        clock.advance(1)
    }
    #expect(store.madeFolders.count == RemoteStore.madeFoldersKept)
    #expect(!store.isRecentlyMade(projects + "/f0") && !store.isRecentlyMade(projects + "/f5"))
    #expect(store.isRecentlyMade(projects + "/f6") && store.isRecentlyMade(projects + "/f69"))
    clock.advance(RemoteStore.madeFolderMemory)  // the rest are old by now: the next one forgets them
    try await store.createFolder(named: "latest", in: projects)
    #expect(store.madeFolders.keys.sorted() == [projects + "/latest"])
}

// MARK: - The name's rules

@Test func theNameIsTrimmedLikeTheBridgeTrimsIt() {
    for (typed, trimmed) in [
        ("  app ", "app"), ("\t\napp\r\n", "app"), ("\u{A0}app\u{2003}", "app"), ("\u{2028}app\u{2029}", "app"),
        ("\u{85}app", "app"), ("\u{B}app\u{C}", "app"), ("\u{3000}app\u{3000}", "app"), ("a b", "a b"), ("   ", ""),
        ("a\nb", "a\nb"), ("\u{200B}app", "\u{200B}app"),
    ] {
        #expect(NewFolderName.trimmed(typed) == trimmed, "\(typed.debugDescription)")
    }
}

@Test func theNamesTheBridgeTakes() {
    for name in [
        "app", "my app", "v1.2", "a.b", "name.", "caf\u{E9}", "\u{1F4C1} notes", "\u{9879}\u{76EE}", "-dash", "_under",
        String(repeating: "x", count: 255), String(repeating: "\u{E9}", count: 127),
        String(repeating: "\u{1F4C1}", count: 63), String(repeating: "a", count: 200) + String(repeating: "\u{E9}", count: 27),
        "\u{200D}\u{1F468}\u{200D}\u{1F469}",
    ] {
        #expect(NewFolderName.problem(in: name) == nil, "\(name.prefix(12).debugDescription)")
    }
    #expect(NewFolderName.problem(in: "  padded  ") == nil)  // judged trimmed
}

@Test func theNamesItDoesNot() {
    typealias Problem = NewFolderName.Problem
    let cases: [(String, Problem)] = [
        ("", .empty), ("  \n", .empty), (String(repeating: "x", count: 256), .tooLong),
        (String(repeating: "\u{E9}", count: 128), .tooLong), (String(repeating: "\u{1F4C1}", count: 64), .tooLong),
        ("/", .separator), ("a/b", .separator), ("a:b", .separator), (":", .separator), ("a/b\u{0}", .separator),
        ("a\u{0}b", .control), ("a\nb", .control), ("a\tb", .control), ("\u{7F}x", .control), ("a\u{85}b", .control),
        ("a\u{9F}b", .control), (".", .leadingDot), ("..", .leadingDot), (".git", .leadingDot), (".hidden", .leadingDot),
        (" .padded ", .leadingDot),
    ]
    for (name, problem) in cases {
        #expect(NewFolderName.problem(in: name) == problem, "\(name.prefix(12).debugDescription)")
    }
}

/// The words the phone says first are the words the mock bridge says when a name reaches it: one table, two copies.
@Test func theWordsAreTheMockBridgesWords() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("bridge-mock/mock_bridge.py"), encoding: .utf8)
    let start = try #require(source.range(of: "NAME_WORDS = {"))
    let block = try #require(source[start.upperBound...].range(of: "\n}"))
    var table: [String: String] = [:]
    for line in source[start.upperBound..<block.lowerBound].split(separator: "\n") {
        let parts = line.trimmingCharacters(in: .whitespaces)
        guard let key = parts.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false).dropFirst().first,
            let colon = parts.firstIndex(of: ":")
        else { continue }
        var words = parts[parts.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if words.hasSuffix(",") { words.removeLast() }
        let quote = try #require(words.first)
        words = String(words.dropFirst().dropLast())
        #expect(quote == "'" || quote == "\"")
        table[String(key)] = words
    }
    typealias Problem = NewFolderName.Problem
    #expect(table["empty"] == Problem.empty.words)
    #expect(table["long"] == Problem.tooLong.words)
    #expect(table["separator"] == Problem.separator.words)
    #expect(table["control"] == Problem.control.words)
    #expect(table["dot"] == Problem.leadingDot.words)
    #expect(table.count == 7)  // empty, encoding, long, separator, control, dot, private: the phone says five of them
}
