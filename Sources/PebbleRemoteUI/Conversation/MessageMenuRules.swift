import Foundation
import PebbleDesign
import PebbleRemoteKit

/// What a long press on a message offers (`MessageMenu`), as Pebble's window offers it under each message
/// (MessageActions.vue, App.vue):
/// - Copy, on every message Pebble has finished writing (a reply still being written has no menu, as on the Mac).
/// - Copy Code for each code block of a reply; Open Link for each web link the iPhone opens (F13: on the iPhone, never
///   on the Mac).
/// - Edit on the person's last message, and Retry on the latest reply that answers a question of theirs; both only
///   while this conversation isn't working and the bridge offers `send`, since each sends a new message. Retry says
///   why it can't run when the question had attachments, which aren't sent again.
nonisolated enum MessageMenuRules {
    /// What a message's menu takes from its words alone: Copy Code's blocks (a reply's) and the links it shows. Markdown
    /// parsing and link detection are too slow to repeat for every row on screen at each streamed update, so the
    /// transcript keeps these by message id and works them out again only when the text changes.
    struct Words: Sendable {
        let text: String
        let code: [String]
        let links: [URL]

        init(_ message: MessageItem) {
            text = message.text
            code = message.role == .assistant ? MessageMenu.codeBlocks(in: message.text) : []
            links = MessageMenu.links(in: message.text)
        }
    }

    static func items(
        for message: MessageItem, in transcript: [TranscriptItem], isWorking: Bool, canSend: Bool,
        words kept: Words? = nil, opens: (URL) -> Bool
    ) -> [MessageMenu.Item] {
        guard !message.isStreaming else { return [] }
        let words: Words
        if let kept, kept.text == message.text { words = kept } else { words = Words(message) }
        var items: [MessageMenu.Item] = [.copy]
        items += words.code.map(MessageMenu.Item.copyCode)
        items += words.links.filter(opens).map(MessageMenu.Item.openLink)
        guard canSend, !isWorking else { return items }
        let messages = transcript.compactMap { item -> MessageItem? in
            if case .message(let message) = item { message } else { nil }
        }
        switch message.role {
        case .user:
            if messages.last(where: { $0.role == .user })?.id == message.id { items.append(.edit) }
        case .assistant:
            if messages.last(where: { $0.role == .assistant })?.id == message.id,
                let question = RemoteStore.question(before: message.id, in: transcript)
            {
                items.append(
                    question.attachments.isEmpty ? .retry : .retryUnavailable(AppCopy.MessageMenu.retryWithoutAttachments))
            }
        }
        return items
    }
}
