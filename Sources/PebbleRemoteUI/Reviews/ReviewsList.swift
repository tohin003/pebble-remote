import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Everything waiting for the person, oldest first (the store keeps that order), as PebbleDesign's cards in a scrolling
/// stack (the cards draw their own panel, so no list rows around them). Each item names its chat, which opens.
///
/// The scroll view keeps its content clear of the bars at its end (the system's inset covers the tab bar and the run
/// accessory). While the accessory shows, cards that scroll under it are hidden behind a solid edge rather than showing
/// through the glass, where their buttons looked tappable and the accessory took the tap (the UX audit's U-04).
struct ReviewsList: View {
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A card's details or a task's uncertain outcomes.
    @State private var recovery: RecoverySheet?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PebbleSpace.s5) {
                ForEach(store.waiting) { item in
                    WaitingRow(item: item, present: { recovery = $0 })
                        .transition(PebbleMotion.transition(edge: .trailing, reduceMotion: reduceMotion))
                }
            }
            .padding()
        }
        .scrollEdgeEffectStyle(router.showsRunAccessory(in: store) ? .hard : nil, for: .bottom)
        // A question's written answer lets go of the keyboard when the list moves (the re-check's U-54: on this tab root
        // nothing else closed it); its card adds Done and Return in an empty answer.
        .scrollDismissesKeyboard(.immediately)
        .pebbleAnimation(PebbleMotion.appear, value: store.waiting)
        .overlay {
            if store.waiting.isEmpty {
                PebbleEmptyState(.noReviews)
            }
        }
        .refreshable { await store.refresh() }
        .navigationTitle(AppCopy.Reviews.title)
        .sheet(item: $recovery) { which in
            RecoverySheetView(which: which)
                .lockCover()
        }
        .viewOpening()  // lane G: a waiting form's sheet opens from here
    }
}
