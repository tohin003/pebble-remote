import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// Changed files (WorkCard.vue): one row per path with its counts summed, a bar whose length follows the largest
/// change, and the change's state in words.
struct FilesDetails: View {
    let changes: [WorkCard<RunActivityItem>.FileChange]
    @State private var showsAll = false

    var body: some View {
        let widest = max(1, changes.map { $0.added + $0.removed }.max() ?? 1)
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            ForEach(changes.prefix(showsAll ? changes.count : ShowMoreButton.shown)) { change in
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s1) {
                        Text(verbatim: change.path ?? AppCopy.Views.aPrivateFile)
                            .font(change.path == nil ? PebbleFont.cardBody : PebbleFont.cardDetail)
                            .foregroundStyle(change.path == nil ? PebbleColor.secondaryText : PebbleColor.text)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        if change.isNew {
                            Text(AppCopy.Views.new)
                                .font(PebbleFont.meta)
                                .foregroundStyle(PebbleColor.secondaryText)
                        }
                    }
                    HStack(spacing: PebbleSpace.s2) {
                        DiffBar(added: change.added, removed: change.removed, widest: widest)
                        Text(AppCopy.Views.diff(added: change.added, removed: change.removed))
                            .font(PebbleFont.chip.monospacedDigit())
                            .foregroundStyle(PebbleColor.secondaryText)
                            .accessibilityHidden(true)
                        if let state = change.state {
                            ToneLabel(AppCopy.Views.state(state), tone: state.tone)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if changes.count > ShowMoreButton.shown {
                ShowMoreButton(hidden: changes.count - ShowMoreButton.shown, showsAll: $showsAll)
            }
        }
    }
}
