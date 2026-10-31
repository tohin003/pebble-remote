import PebbleDesign
import SwiftUI

/// A place under Your Space (Companion or a project). As on the Mac, tapping it starts a new conversation there, so it
/// carries the new-conversation glyph and VoiceOver hears "New conversation in pebble-web".
struct PlaceButton: View {
    let name: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(name)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: systemImage)
                }
                Spacer(minLength: 0)
                Image(systemName: PebbleSymbol.askPebble)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(AppCopy.Sidebar.newConversation(in: name))
        .accessibilityHint(AppCopy.Sidebar.newConversationHint)
    }
}
