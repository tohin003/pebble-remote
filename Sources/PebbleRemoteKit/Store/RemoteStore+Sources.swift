import Foundation
import PebbleProtocol

extension RemoteStore {
    /// A reply's source marker ("S7"), as Pebble's window opens it (App.vue `openCitation`): the page the reply's run
    /// recorded under that id (`research_sources`) when its address is a secure web address, for the caller to open on
    /// this iPhone, never on the Mac (F13). Otherwise a notice names the source, or says Pebble has no record of it. A
    /// reply without its run asks for the conversation's newest, as the window does.
    public func sourcePage(_ id: String, in chat: ChatID, run: RunID?) async -> URL? {
        guard let run = run ?? world.newestRun(in: chat)?.row.id else {
            notice = PersonFacingError(message: StoreWords.sourceNotRecorded(id))
            return nil
        }
        let listing: JSONValue
        do {
            listing = try await answer("research_sources", ["id": .string(chat), "run_id": .string(run)])
        } catch RemoteCallError.cancelledByPerson {
            return nil
        } catch {
            // `answer` already says what went wrong when it can (the unlock sheet opens from its notice).
            if notice == nil { notice = PersonFacingError(message: StoreWords.sourceNotOpened(id)) }
            return nil
        }
        guard let source = (listing["sources"]?.array ?? []).first(where: { $0["source_id"]?.string == id }) else {
            notice = PersonFacingError(message: StoreWords.sourceNotRecorded(id))
            return nil
        }
        func words(_ key: String) -> String {
            (source[key]?.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let address = words("url")
        if address.count <= 3000, address.range(of: #"^https://\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil,
            let page = URL(string: address), page.host() != nil
        {
            return page
        }
        let name = String(([words("title"), words("domain"), address].first { !$0.isEmpty } ?? "").prefix(80))
        notice = PersonFacingError(
            message: name.isEmpty ? StoreWords.sourceWithoutAddress(id) : StoreWords.sourceNamed(id, name))
        return nil
    }
}
