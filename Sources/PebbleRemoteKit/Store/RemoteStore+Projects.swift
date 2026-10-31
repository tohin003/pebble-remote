import Foundation
import PebbleProtocol

// Where conversations start, as Pebble's own window places them (read-only Pebble checkout: src/App.vue createChat,
// openProject, chooseProject, detachProject, recentProjects, attachUrl, proposeCommand; backend/pebble/app.py
// new_chat, set_workspace, attach_url, terminal_propose), plus the Mac's folders for "Connect a project" (proposal v0.5,
// `remote.folders`) and the new folders "Connect a project" makes there (proposal v0.6, `remote.folder_create`). Every
// call returns once the store shows Pebble's answer; failures become `notice` in Pebble's or the bridge's words and are
// rethrown, as everywhere in the store.

extension RemoteStore {
    // MARK: Projects

    /// How many projects Pebble's sidebar lists under YOUR SPACE.
    public nonisolated static let recentProjectLimit = 5

    /// The projects Pebble's sidebar lists under YOUR SPACE (App.vue `recentProjects`): the folders of the
    /// conversations, newest first, at most five.
    public var recentProjects: [ProjectRef] { Array(projects.prefix(Self.recentProjectLimit)) }

    /// The recent projects without the open conversation's own (the Mac gives that one its own row).
    public func recentProjects(leavingOut path: String?) -> [ProjectRef] {
        recentProjects.filter { $0.path != path }
    }

    /// A folder some conversation already works in. Pebble's bridge lets the phone start or move conversations there
    /// with the unlock alone; any other folder widens what Pebble may read, so it asks for Face ID (proposal v0.5).
    public func isKnownProject(_ path: String) -> Bool {
        projects.contains { $0.path == path }
    }

    /// How long the bridge counts a folder this phone made as known to it (proposal v0.6, item 2).
    public nonisolated static let madeFolderMemory: TimeInterval = 600
    /// How many made folders the store remembers at once (the bridge keeps no more for one phone).
    nonisolated static let madeFoldersKept = 64

    /// A folder this phone made on the Mac in the last ten minutes (`createFolder`). The person proved themselves for that
    /// very folder when it was made, so the bridge lets the phone connect it with the unlock alone: one Face ID for "make
    /// it and connect it". Only that exact path counts.
    public func isRecentlyMade(_ path: String) -> Bool {
        guard let made = madeFolders[path] else { return false }
        return clock().timeIntervalSince(made) <= Self.madeFolderMemory
    }

    /// Whether connecting this folder asks for Face ID: a folder no conversation uses yet, which this phone didn't just
    /// make. (A bridge that wants it anyway gets it once: `act` retries on `proof_required`.)
    func connectNeedsFaceID(_ path: String) -> Bool {
        !isKnownProject(path) && !isRecentlyMade(path)
    }

    /// Moves a conversation into a project, or back to Companion (nil): `set_workspace {id, path}`, as Pebble's window
    /// does when the person picks a project for an empty conversation, or Companion for any. A folder no conversation
    /// uses yet asks for Face ID ("Connect a project"), unless this phone made it a moment ago (`isRecentlyMade`); a
    /// bridge that wants Face ID for another folder gets it too. Pebble refuses while a task runs. Returns once the store
    /// shows the conversation where Pebble put it.
    public func setWorkspace(_ chat: ChatID, to project: ProjectRef?) async throws {
        let params: JSONValue = ["id": .string(chat), "path": project.map { .string($0.path) } ?? .null]
        let isNew = project.map { connectNeedsFaceID($0.path) } ?? false
        let result = try await act(
            "set_workspace", params, reason: StoreWords.workspaceReason(project?.name), elevate: isNew)
        if let detail = ChatDetailDTO(json: result) {
            publish(world.load(detail))
        } else {
            await readChat(chat)
        }
        await refreshState()
    }

    /// The subfolders of a folder on the Mac, for "Connect a project" (`remote.folders`, proposal v0.5): the home
    /// folder's when `path` is nil. Folder names only, never files; the bridge wants the unlock, as for a screenshot.
    public func folders(at path: String?) async throws -> FolderListing {
        let params: JSONValue = path.map { ["path": .string($0)] } ?? [:]
        guard let listing = FolderListing(json: try await answer("remote.folders", params)) else { throw unreadable() }
        return listing
    }

    /// "New Folder" in "Connect a project": one empty folder on the Mac inside `parent` (`remote.folder_create`, proposal
    /// v0.6). It writes to the Mac's disk, so it asks for Face ID ("Create a folder: <name>"). The name is trimmed, and a
    /// name no folder can have (`NewFolderName`) is refused here, in the bridge's words and before Face ID. Returns the
    /// folder as the Mac lists it. For ten minutes the bridge counts that folder as known to this phone, so connecting it
    /// asks for no second Face ID. A refusal (a name already there, a parent that isn't allowed) becomes `notice` in the
    /// bridge's words and is rethrown; the person cancelling Face ID leaves none.
    @discardableResult
    public func createFolder(named name: String, in parent: String) async throws -> FolderEntry {
        let trimmed = NewFolderName.trimmed(name)
        if let problem = NewFolderName.problem(in: trimmed) { throw refuse(problem.words) }
        let params: JSONValue = ["parent": .string(parent), "name": .string(trimmed)]
        let result = try await answerElevated(
            "remote.folder_create", params, reason: StoreWords.createFolderReason(trimmed))
        guard let folder = FolderEntry(json: result) else { throw report(unreadable()) }
        rememberMade(folder.path)
        return folder
    }

    /// Keeps the folder this phone just made for `madeFolderMemory`; older ones, and any beyond `madeFoldersKept`, go.
    private func rememberMade(_ path: String) {
        let now = clock()
        madeFolders = madeFolders.filter { now.timeIntervalSince($0.value) <= Self.madeFolderMemory }
        madeFolders[path] = now
        let extra = madeFolders.count - Self.madeFoldersKept
        if extra > 0 {
            for (oldest, _) in madeFolders.sorted(by: { $0.value < $1.value }).prefix(extra) { madeFolders[oldest] = nil }
        }
    }

    // MARK: The composer's "+" menu

    /// "Read a web source": Pebble reads a public web page (`attach_url {id, url}`) for the conversation's next message
    /// that starts a task. Returns the source once the store lists it with the conversation's attachments.
    @discardableResult
    public func attachURL(_ url: String, to chat: ChatID) async throws -> AttachmentRef {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await answer("attach_url", ["id": .string(chat), "url": .string(address)])
        guard let id = result["id"]?.string, !id.isEmpty else { throw unreadable() }
        let source = AttachmentRef(id: id, name: result["name"]?.string ?? address, kind: "url")
        attachments[chat, default: []].append(source)
        return source
    }

    /// "Terminal command": one command in the conversation's project (`terminal_propose {id, command, network}`),
    /// which goes through Pebble's review like any of its cards. Face ID (proposal v0.5). Returns once the store has
    /// read the conversation again, with Pebble's card in it (or the command's output, when Pebble ran it at once).
    public func proposeTerminalCommand(_ command: String, network: Bool, in chat: ChatID) async throws {
        let words = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        let params: JSONValue = ["id": .string(chat), "command": .string(words), "network": .bool(network)]
        _ = try await act("terminal_propose", params, reason: StoreWords.terminalCommandReason(words))
        await readChat(chat)
        await refreshState()
    }

    // MARK: New conversations (drafts)

    /// How many drafts the store keeps; the oldest goes first.
    nonisolated static let draftLimit = 12

    /// "New conversation": a conversation in Companion (nil) or a project, made on the Mac only when its first message
    /// is sent.
    public func newDraft(in place: ProjectRef? = nil) -> ConversationDraft {
        let draft = ConversationDraft(place: place)
        drafts.append((draft.id, draft))
        if drafts.count > Self.draftLimit { drafts.removeFirst(drafts.count - Self.draftLimit) }
        return draft
    }

    /// The draft with this id; nil once the store has forgotten it (another Mac, the demo ended, many newer drafts).
    public func draft(_ id: String) -> ConversationDraft? {
        drafts.first { $0.id == id }?.draft
    }

    /// Forgets a draft whose conversation the screens show now.
    public func discardDraft(_ id: String) {
        drafts.removeAll { $0.id == id }
        unsent[.newConversation(id)] = ""
    }

    /// Where the draft's conversation starts. Nothing reaches the Mac until its first message.
    public func move(_ draft: ConversationDraft, to place: ProjectRef?) {
        if draft.place != place { draft.place = place }
    }

    /// Keeps a photo or file for the draft's first message, on this phone until it is sent.
    public func attach(_ data: Data, name: String, preview: Data? = nil, to draft: ConversationDraft) throws {
        guard data.count <= 50_000_000 else { throw refuse(StoreWords.fileTooLarge) }
        try checkRoom(in: draft)
        draft.pending.append(DraftAttachment(name: name, source: .bytes(data), preview: preview))
    }

    /// Keeps a web page for Pebble to read with the draft's first message. The address must be one Pebble reads: a
    /// public https:// address without credentials or a custom port.
    public func attachURL(_ url: String, to draft: ConversationDraft) throws {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isReadableWebAddress(address) else { throw refuse(StoreWords.webAddressRefused) }
        try checkRoom(in: draft)
        draft.pending.append(DraftAttachment(name: address, source: .webPage(address)))
    }

    /// What waits for the draft's first message: anything already sent to Pebble (when a send was cut short), then
    /// what is still on this phone.
    public func pendingAttachments(for draft: ConversationDraft) -> [AttachmentRef] {
        (draft.chatID.flatMap { attachments[$0] } ?? []) + draft.pending.map(\.ref)
    }

    /// Removes something waiting for the draft's first message (from Pebble too, if it already went).
    public func removeAttachment(_ attachment: AttachmentRef, from draft: ConversationDraft) async throws {
        if draft.pending.contains(where: { $0.id == attachment.id }) {
            draft.pending.removeAll { $0.id == attachment.id }
        } else if let chat = draft.chatID {
            try await removeAttachment(attachment, from: chat)
        }
    }

    /// Sends the draft's first message. Pebble makes the conversation in the draft's place (`make(_:)`), takes the
    /// photos, files and web pages waiting in the draft, then the message. Returns the conversation's id once Pebble
    /// took the message, or nil when there are no words to send. After a failure the draft keeps the conversation (if
    /// Pebble made it) and what didn't reach Pebble yet, so the next send goes on from there.
    @discardableResult
    public func send(_ text: String, from draft: ConversationDraft) async throws -> ChatID? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        let chat = try await make(draft)
        try await sendPending(of: draft, to: chat)
        try await send(words, in: chat)
        draft.isSent = true
        return chat
    }

    /// "Terminal command" in a new conversation: Pebble makes the conversation first (the command and its card are its
    /// first content), then the command goes to Pebble's review. What waits in the draft stays for the next message.
    @discardableResult
    public func proposeTerminalCommand(_ command: String, network: Bool, from draft: ConversationDraft) async throws
        -> ChatID
    {
        let chat = try await make(draft)
        try await sendPending(of: draft, to: chat)
        try await proposeTerminalCommand(command, network: network, in: chat)
        draft.isSent = true
        return chat
    }

    /// Makes the draft's conversation on the Mac, in the draft's place, unless it is made already; returns its id
    /// (`new_chat {workspace}`; Face ID for a folder no conversation uses yet). A conversation made before the person
    /// chose another place (a send cut short) moves there, as Pebble's window reuses an empty conversation.
    public func make(_ draft: ConversationDraft) async throws -> ChatID {
        let wanted = draft.place
        if let made = draft.chatID {
            if draft.madeIn != wanted?.path {
                try await setWorkspace(made, to: wanted)
                draft.madeIn = wanted?.path
            }
            return made
        }
        let made = try await makeChat(in: wanted)
        draft.chatID = made
        draft.madeIn = wanted?.path
        return made
    }

    // MARK: Helpers

    /// `new_chat {workspace}`, and the new conversation shown at once (Pebble lists it only once it holds something).
    /// Companion, a known project and a folder this phone made in the last ten minutes need only the unlock. A folder no
    /// conversation uses yet widens what Pebble may read, so it goes with Face ID: the bridge applies `set_workspace`'s
    /// rule to `new_chat` too (proposal v0.5), and one elevated call leaves no empty conversation behind when the folder
    /// is refused.
    func makeChat(in project: ProjectRef?) async throws -> ChatID {
        let params: JSONValue = project.map { ["workspace": .string($0.path)] } ?? [:]
        let isNew = project.map { connectNeedsFaceID($0.path) } ?? false
        let result = try await act("new_chat", params, reason: StoreWords.workspaceReason(project?.name), elevate: isNew)
        guard let detail = ChatDetailDTO(json: result) else { throw unreadable() }
        let id = detail.chat.id
        publish(world.add(chat: detail.chat))
        publish(world.load(detail))
        let made = transcripts[id] ?? Transcript(chatID: id, store: self)
        transcripts[id] = made
        made.update(from: world)
        return id
    }

    /// Sends what waits in the draft to Pebble, one at a time; each leaves the draft once Pebble took it.
    func sendPending(of draft: ConversationDraft, to chat: ChatID) async throws {
        while let next = draft.pending.first {
            switch next.source {
            case .bytes(let data): try await attach(data, name: next.name, to: chat)
            case .webPage(let address): try await attachURL(address, to: chat)
            }
            draft.pending.removeAll { $0.id == next.id }
        }
    }

    /// A call the bridge may want Face ID for: elevated at once when `elevate` is true or the bridge lists the method in
    /// `welcome.elevated`; otherwise plain, and elevated once when the bridge answers `proof_required` (as
    /// `setKeepAwake` does). Going straight to Face ID when it is known to be needed asks once, not twice (the unlock,
    /// then the proof). A failure is shown once as `notice`, unless `reports` is false: a screen that says it in place,
    /// as a quiz does (lane Q), keeps the alert from saying it a second time.
    func act(
        _ method: String, _ params: JSONValue, reason: String, elevate: Bool = false, reports: Bool = true
    ) async throws -> JSONValue {
        do {
            if elevate || (bridge?.elevated.contains(method) ?? false) {
                return try await client.callElevated(method, params, reason: reason)
            }
            do {
                return try await client.call(method, params)
            } catch RemoteCallError.refused(let refusal) where refusal.code == BridgeErrorCode.proofRequired.rawValue {
                return try await client.callElevated(method, params, reason: reason)
            }
        } catch {
            throw reports ? report(error) : error
        }
    }

    /// Pebble takes up to ten attachments and sources with a message.
    private func checkRoom(in draft: ConversationDraft) throws {
        guard pendingAttachments(for: draft).count < 10 else { throw refuse(StoreWords.tooManyAttachments) }
    }

    /// A refusal the store writes itself, shown once as `notice`.
    private func refuse(_ words: String) -> RemoteCallError {
        let failure = PersonFacingError(message: words)
        notice = failure
        return .refused(failure)
    }

    /// The addresses Pebble reads (sources.py `check_url`): https, a host, no credentials, no custom port, no spaces or
    /// control characters, at most 3,000 characters.
    nonisolated static func isReadableWebAddress(_ address: String) -> Bool {
        let hasControls = address.unicodeScalars.contains { $0.properties.generalCategory == .control }
        guard address.count <= 3000, !hasControls, !address.contains(where: \.isWhitespace),
            let parts = URLComponents(string: address), parts.scheme?.lowercased() == "https",
            let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
            parts.port == nil || parts.port == 443
        else { return false }
        return true
    }
}

/// What a folder's name may be when the phone makes one on the Mac (proposal v0.6): trimmed, then 1 to 255 bytes of UTF-8,
/// with no `/` or `:`, no control characters, and no leading dot (which rules out `.` and `..` too). The bridge holds the
/// same rules; the phone says them first, in the bridge's own words, so a name that can't work never asks for Face ID.
/// A name already in the folder is the Mac's to say.
public enum NewFolderName {
    public enum Problem: Sendable, Hashable {
        case empty
        case tooLong
        /// `/` or `:`.
        case separator
        /// A line break, or any other control character.
        case control
        /// `.`, `..` or a leading dot: the folder would be hidden.
        case leadingDot

        /// The bridge's words for it.
        public var words: String {
            switch self {
            case .empty: StoreWords.folderNameEmpty
            case .tooLong: StoreWords.folderNameTooLong
            case .separator: StoreWords.folderNameSeparator
            case .control: StoreWords.folderNameControl
            case .leadingDot: StoreWords.folderNameDot
            }
        }
    }

    /// The most a name may take, in bytes of UTF-8.
    public static let longestInBytes = 255

    /// The name as the bridge takes it: without the blanks at both ends. A blank is any Unicode separator (spaces, the
    /// line and paragraph separators), a tab, a line break (U+000A to U+000D) or U+0085; a zero-width space is not one.
    /// Written out here, not left to Foundation's whitespace set, which counts the zero-width space too.
    public static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !isBlank($0) }),
            let last = scalars.lastIndex(where: { !isBlank($0) })
        else { return "" }
        return String(scalars[first...last])
    }

    private static func isBlank(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: true
        default: (0x09...0x0D).contains(scalar.value) || scalar.value == 0x85
        }
    }

    /// Why what the person typed can't be a folder's name, or nil. It is judged trimmed, in the bridge's order.
    public static func problem(in typed: String) -> Problem? {
        let name = trimmed(typed)
        if name.isEmpty { return .empty }
        if name.utf8.count > longestInBytes { return .tooLong }
        if name.contains("/") || name.contains(":") { return .separator }
        if name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) { return .control }
        if name.hasPrefix(".") { return .leadingDot }
        return nil
    }
}
