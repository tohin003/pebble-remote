import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's welcome in an empty conversation, word for word (App.vue): "Good to see you." in Companion, "Let's build
/// something." in a project, with the pebble.
///
/// It always gives a little on a swipe, even when it fits, so a swipe down closes the keyboard (as in a conversation);
/// Back stays in reach as well.
struct DraftWelcome: View {
    let draft: ConversationDraft
    @Environment(RemoteStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: PebbleSpace.s4) {
                PebbleAvatar(pose: .idle, stealth: store.pebble?.stealth ?? false, animated: true)
                    .frame(width: PebbleSize.avatarEmpty, height: PebbleSize.avatarEmpty)
                    .accessibilityHidden(true)
                Text(draft.placeName == nil ? AppCopy.Draft.welcome : AppCopy.Draft.welcomeInProject)
                    .font(.title2)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                Text(draft.placeName.map(AppCopy.Draft.projectDescription) ?? AppCopy.Draft.companionDescription)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
    }
}
