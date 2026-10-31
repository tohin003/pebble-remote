import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A project in "Connect a project": its name, its folder on the Mac (two projects may share a name), and a checkmark
/// where the conversation is now.
struct ProjectChoiceRow: View {
    let project: ProjectRef
    let isCurrent: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                        Text(project.name)
                            .foregroundStyle(.primary)
                        Text(project.path)
                            .font(PebbleFont.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: PebbleSymbol.project)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
