import Foundation
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Lane Z: what a long press offers. On a conversation in Chats (U-19), the Mac sidebar row's actions the bridge offers,
/// as its swipe actions offer them.
struct LongPressMenuTests {
    static let everything: Set<String> = ["chat_rename", "new_chat", "cancel", "storage_trash_chat"]
    static let project = ProjectRef(path: "/Users/me/Projects/pebble-web", name: "pebble-web")

    static func chat(_ status: StatusKey? = nil) -> ChatSummary {
        ChatSummary(id: "c1", title: "Fix the login redirect loop", project: "pebble-web", status: status)
    }

    @Test func aSettledConversationOffersRenameANewOneInItsProjectAndDelete() {
        let items = ChatMenuItem.items(for: Self.chat(), project: Self.project) { Self.everything.contains($0) }
        #expect(items == [.rename, .newConversation(Self.project), .delete])
    }

    @Test(arguments: [StatusKey.thinking, .reading, .running, .writing])
    func aWorkingConversationOffersStopInsteadOfDelete(_ status: StatusKey) {
        let items = ChatMenuItem.items(for: Self.chat(status), project: Self.project) { Self.everything.contains($0) }
        #expect(items == [.rename, .newConversation(Self.project), .stop])
    }

    @Test(arguments: [StatusKey.question, .review, .blocked, .uncertain, .error, .paused])
    func aConversationThatWaitsOrEndedCanBeDeleted(_ status: StatusKey) {
        let items = ChatMenuItem.items(for: Self.chat(status), project: nil) { Self.everything.contains($0) }
        #expect(items == [.rename, .delete])
    }

    @Test func companionHasNoNewConversationItem() {
        let items = ChatMenuItem.items(for: Self.chat(), project: nil) { Self.everything.contains($0) }
        #expect(!items.contains { if case .newConversation = $0 { true } else { false } })
    }

    @Test func whatTheBridgeDoesNotOfferIsLeftOut() {
        #expect(ChatMenuItem.items(for: Self.chat(), project: Self.project) { _ in false }.isEmpty)
        #expect(ChatMenuItem.items(for: Self.chat(.running), project: nil) { $0 == "storage_trash_chat" }.isEmpty)
        #expect(ChatMenuItem.items(for: Self.chat(), project: Self.project) { $0 == "chat_rename" } == [.rename])
    }

    @Test func stopAndDeleteStandApart() {
        #expect(ChatMenuItem.stop.ends && ChatMenuItem.delete.ends)
        #expect(!ChatMenuItem.rename.ends && !ChatMenuItem.newConversation(Self.project).ends)
    }
}

/// Lane Z, item 2: a long press on a message offers what Pebble's window offers under it (MessageActions.vue).
struct MessageMenuRulesTests {
    static let photo = AttachmentRef(id: "s1", name: "screen.png", kind: "image")

    static func message(
        _ id: String, _ role: MessageItem.Role, _ text: String, streaming: Bool = false, attachments: [AttachmentRef] = []
    ) -> MessageItem {
        MessageItem(id: id, role: role, text: text, isStreaming: streaming, attachments: attachments)
    }

    static let question = message("m1", .user, "Why does login loop?")
    static let reply = message("m2", .assistant, "The cookie expired.\n\n```ts\nsetCookie(1)\n```\nSee [the fix](https://github.com/me/app/pull/7).")
    static let transcript: [TranscriptItem] = [.message(question), .message(reply)]

    static func items(
        _ message: MessageItem, in transcript: [TranscriptItem] = transcript, working: Bool = false, send: Bool = true
    ) -> [MessageMenu.Item] {
        MessageMenuRules.items(for: message, in: transcript, isWorking: working, canSend: send) { _ in true }
    }

    @Test func theLatestReplyOffersCopyItsCodeItsLinkAndRetry() throws {
        let link = try #require(URL(string: "https://github.com/me/app/pull/7"))
        #expect(Self.items(Self.reply) == [.copy, .copyCode("setCookie(1)"), .openLink(link), .retry])
    }

    @Test func thePersonsLastMessageOffersCopyAndEdit() {
        #expect(Self.items(Self.question) == [.copy, .edit])
    }

    @Test func anEarlierMessageOffersCopyOnly() {
        let later = Self.message("m3", .user, "And the logout?")
        let reply2 = Self.message("m4", .assistant, "Fixed too.")
        let transcript = Self.transcript + [.message(later), .message(reply2)]
        #expect(Self.items(Self.question, in: transcript) == [.copy])
        #expect(Self.items(Self.reply, in: transcript).last != .retry)
        #expect(Self.items(reply2, in: transcript) == [.copy, .retry])
    }

    @Test func whileTheConversationWorksNothingIsSentAgain() {
        #expect(Self.items(Self.question, working: true) == [.copy])
        #expect(!Self.items(Self.reply, working: true).contains(.retry))
    }

    @Test func withoutSendThereIsNoEditOrRetry() {
        #expect(Self.items(Self.question, send: false) == [.copy])
        #expect(!Self.items(Self.reply, send: false).contains(.retry))
    }

    @Test func aReplyStillBeingWrittenHasNoMenu() {
        #expect(Self.items(Self.message("m2", .assistant, "Working on", streaming: true)).isEmpty)
    }

    @Test func retrySaysWhyWhenTheQuestionHadAttachments() {
        let question = Self.message("m1", .user, "What's on this screen?", attachments: [Self.photo])
        let reply = Self.message("m2", .assistant, "A login form.")
        let items = Self.items(reply, in: [.message(question), .message(reply)])
        #expect(items == [.copy, .retryUnavailable(AppCopy.MessageMenu.retryWithoutAttachments)])
    }

    @Test func aReplyWithNoQuestionBeforeItHasNoRetry() {
        let reply = Self.message("m2", .assistant, "Hello.")
        #expect(Self.items(reply, in: [.message(reply)]) == [.copy])
    }

    @Test func onlyLinksTheIPhoneOpensAreOffered() {
        let reply = Self.message("m2", .assistant, "See https://example.com/a and [x](pebble-remote://pair?x=1).")
        let items = MessageMenuRules.items(for: reply, in: [.message(reply)], isWorking: false, canSend: true) {
            InAppLinks.opensInBrowser($0)
        }
        #expect(items.count == 2 && items.first == .copy)
        #expect(items.last == .openLink(URL(string: "https://example.com/a")!))
    }

    @Test func thePersonsCodeIsCopiedWithTheirMessageNotAsABlock() {
        let mine = Self.message("m1", .user, "```\nnpm test\n```")
        #expect(!Self.items(mine, in: [.message(mine)]).contains(.copyCode("npm test")))
    }
}
