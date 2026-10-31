import PebbleDesign
import PebbleProtocol
import SwiftUI

/// Reading and searching (WorkCard.vue): a chip per file read (its path, or "A private file", with its lines) and per
/// search (its query, with what it found).
struct ExploredDetails: View {
    let views: [WorkView]
    @State private var showsAll = false

    var body: some View {
        let chips = views.compactMap(Self.chip)
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            ChipFlow {
                ForEach(Array(chips.prefix(showsAll ? chips.count : ShowMoreButton.shown).enumerated()), id: \.offset) { _, chip in
                    ViewChip(chip.text, note: chip.note, monospaced: chip.isPath)
                }
            }
            if chips.count > ShowMoreButton.shown {
                ShowMoreButton(hidden: chips.count - ShowMoreButton.shown, showsAll: $showsAll)
            }
        }
    }

    static func chip(_ view: WorkView) -> (text: String, note: String?, isPath: Bool)? {
        switch view.content {
        case .read(let read):
            let note = read.total.map(AppCopy.Views.lines)
            if read.isPrivate || read.path == nil { return (AppCopy.Views.aPrivateFile, note, false) }
            return (read.path ?? "", note, true)
        case .search(let search):
            return (search.query ?? AppCopy.Views.search, search.hits.map(AppCopy.Views.found), false)
        default:
            return nil
        }
    }
}
