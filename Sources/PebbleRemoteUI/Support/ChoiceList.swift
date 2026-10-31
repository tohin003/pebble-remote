import PebbleDesign
import SwiftUI

/// A setting the Mac keeps, chosen from a list (Fast Replies, the model, its effort, the theme, status words): a
/// checkmark on the Mac's choice; choosing one sends it and shows progress on that row. When the call fails, the Mac's
/// choice stays and the store's notice says why.
struct ChoiceList: View {
    let title: String
    let choices: [Choice]
    /// The Mac's current choice.
    let selected: String?
    var footer: String? = nil
    /// Sends the choice; returns whether the Mac took it.
    let choose: (String) async -> Bool
    @State private var changing: String?

    var body: some View {
        Form {
            Section {
                ForEach(choices) { choice in
                    ChoiceRow(choice: choice, isSelected: choice.id == selected, isChanging: changing == choice.id) {
                        pick(choice.id)
                    }
                }
            } footer: {
                if let footer {
                    Text(footer)
                }
            }
        }
        .disabled(changing != nil)
        .navigationTitle(title)
        .sensoryFeedback(PebbleHaptics.selection, trigger: selected)
    }

    private func pick(_ id: String) {
        guard id != selected, changing == nil else { return }
        changing = id
        Task {
            _ = await choose(id)
            changing = nil
        }
    }
}
