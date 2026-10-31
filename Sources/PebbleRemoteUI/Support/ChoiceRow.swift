import SwiftUI

/// One row of a ChoiceList: the option's name and what it does; a checkmark when chosen, progress while changing.
struct ChoiceRow: View {
    let choice: Choice
    let isSelected: Bool
    let isChanging: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack {
                VStack(alignment: .leading) {
                    Text(choice.title)
                    if let detail = choice.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isChanging {
                    ProgressView()
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.bold())
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
