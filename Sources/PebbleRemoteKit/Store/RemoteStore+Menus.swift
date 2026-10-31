import Foundation
import PebbleProtocol

// Lane Z (2026-10-31): what the long-press menus need. A conversation's last line for the Chats preview, the project a
// conversation is in, and what a message's "Ask Again" sends. Reads only; the menus act through the store's own calls
// (rename, trash, stop, send).

extension RemoteStore {
    // MARK: Chats: a long press on a conversation

    /// The newest message of a conversation, for the preview of a long press on Chats. It comes from what the phone holds
    /// for a conversation open here, else from one small read of its newest messages (`remote.chat_tail`, a read that
    /// needs no unlock), never stored. Nil when there is none or the bridge doesn't offer the read: the preview then
    /// shows the title alone.
    public func lastLine(of chat: ChatID) async -> ChatLastLine? {
        if let timeline = world.timelines[chat] {
            let messages = world.messages(in: chat, timeline: timeline)
            if let line = Self.newestLine(messages.map { (role: $0.role, text: $0.text) }) { return line }
            if !timeline.hasOlder { return nil }
        }
        guard offers("remote.chat_tail"),
            let result = try? await client.call("remote.chat_tail", ["id": .string(chat), "limit": .int(3)])
        else { return nil }
        let messages = (result["messages"]?.array ?? []).compactMap(MessageDTO.init(json:))
        return Self.newestLine(messages.map { (role: $0.role, text: $0.content) })
    }

    /// The newest message that still has words once its Markdown marks are gone.
    nonisolated static func newestLine(_ messages: [(role: MessageItem.Role, text: String)]) -> ChatLastLine? {
        for message in messages.reversed() {
            if let line = ChatLastLine.make(role: message.role, text: message.text) { return line }
        }
        return nil
    }

    /// The project a conversation is in, as a place to start another conversation ("New conversation in pebble-web",
    /// as the Mac's project rows do); nil in Companion.
    public func project(of chat: ChatID) -> ProjectRef? {
        world.workspace(of: chat).map { ProjectRef(path: $0, name: world.project(of: chat) ?? ProjectRef.folderName($0)) }
    }

    // MARK: The transcript: a long press on a message

    /// The person's question a reply answers: the newest message of theirs before it (App.vue `questionFor`). Retry
    /// ("Ask Again") sends its words again as a new message.
    public nonisolated static func question(before reply: MessageID, in items: [TranscriptItem]) -> MessageItem? {
        let messages = items.compactMap { item -> MessageItem? in
            if case .message(let message) = item { message } else { nil }
        }
        guard let index = messages.firstIndex(where: { $0.id == reply }) else { return nil }
        return messages[..<index].last { $0.role == .user }
    }
}
