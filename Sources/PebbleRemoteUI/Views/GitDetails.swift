import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A Git step (WorkCard.vue): its branch, commit and counts as chips (the branch and remote names are literal text,
/// never a button), whether it changes history or publishes, and its state.
struct GitDetails: View {
    let git: WorkView.Git

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            ChipFlow {
                if let branch = git.branch {
                    ViewChip(branch, monospaced: true)
                }
                if let commit = git.commit {
                    ViewChip(commit, monospaced: true)
                }
                if let ahead = git.ahead {
                    ViewChip(AppCopy.Views.aheadBehind(ahead: ahead, behind: git.behind ?? 0))
                }
                if let changed = git.changed {
                    ViewChip(AppCopy.Views.changed(changed))
                }
                if let remote = git.pushTo {
                    ViewChip(AppCopy.Views.pushTo(remote))
                }
            }
            if git.isDestructive || git.publishes {
                let warnings = [
                    git.isDestructive ? AppCopy.Views.changesHistory : nil, git.publishes ? AppCopy.Views.publishes : nil,
                ].compactMap { $0 }
                ToneLabel(warnings.joined(separator: " \u{00B7} "), tone: .open)
            }
            if let state = git.state {
                ToneLabel(AppCopy.Views.state(state), tone: state.tone)
            }
        }
    }
}
