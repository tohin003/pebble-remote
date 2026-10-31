import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// Fast Replies: when Pebble asks for the faster model tier (ChatGPT route only), with Pebble's own names and details.
struct FastRepliesList: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        ChoiceList(
            title: AppCopy.Control.fastReplies,
            choices: FastReplies.allCases.map { value in
                Choice(
                    id: value.rawValue, title: AppCopy.Control.fastRepliesName(value),
                    detail: AppCopy.Control.fastRepliesDetail(value))
            },
            selected: store.pebble?.fastReplies?.rawValue,
            footer: AppCopy.Control.fastRepliesNote,
            choose: choose)
    }

    private func choose(_ id: String) async -> Bool {
        guard let value = FastReplies(rawValue: id) else { return false }
        return await store.attempt { try await store.setFastReplies(value) }
    }
}
