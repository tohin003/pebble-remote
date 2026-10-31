import PebbleDesign
import PebbleProtocol
import SwiftUI

/// One component of an app demo's screen: a heading, a button that switches screens, a field and a switch that stay in
/// the preview, a list, a card, or an image's placeholder.
struct PrototypeComponentView: View {
    let component: NativeView.Prototype.Component
    @Binding var text: String
    @Binding var isOn: Bool
    let go: (String?) -> Void

    var body: some View {
        switch component {
        case .heading(let words):
            Text(verbatim: words)
                .font(PebbleFont.title)
                .foregroundStyle(PebbleColor.text)
                .accessibilityAddTraits(.isHeader)
        case .button(let link):
            Button {
                go(link.target)
            } label: {
                Text(verbatim: link.label)
                    .frame(maxWidth: .infinity, minHeight: PebbleSize.minTap)
            }
            .buttonStyle(.pebbleSecondary)
            .disabled(link.target == nil)
        case .input(let label, let placeholder):
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(verbatim: label)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
                TextField(text: $text, prompt: placeholder.map { Text(verbatim: $0) }) {
                    Text(verbatim: label)
                }
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
            }
        case .toggle(let label):
            Toggle(isOn: $isOn) {
                Text(verbatim: label)
            }
        case .list(let items):
            VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(verbatim: item)
                        .font(PebbleFont.cardBody)
                        .foregroundStyle(PebbleColor.text)
                    Divider()
                }
            }
        case .card(let title, let words):
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(verbatim: title)
                    .font(PebbleFont.cardTitle)
                Text(verbatim: words)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            .padding(PebbleSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PebbleColor.soft, in: .rect(cornerRadius: PebbleRadius.md))
        case .image(let label, let ratio):
            RoundedRectangle(cornerRadius: PebbleRadius.sm)
                .fill(PebbleColor.hover)
                .aspectRatio(ratio ?? 1, contentMode: .fit)
                .overlay {
                    Text(verbatim: label)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.secondaryText)
                        .padding(PebbleSpace.s2)
                }
                .accessibilityElement()
                .accessibilityLabel(AppCopy.Views.imagePlaceholder(label))
        case .nav:
            EmptyView()
        }
    }
}
