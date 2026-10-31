import PebbleDesign
import PebbleProtocol
import SwiftUI

/// One screen of an app demo in a plain device frame: its title bar, its components in order, and its tabs at the
/// bottom. The words are the model's, shown literally; a demo button that names no screen of the demo does nothing and
/// looks it.
struct PrototypeScreenView: View {
    let screen: NativeView.Prototype.Screen
    @Binding var fields: [String: String]
    @Binding var toggles: [String: Bool]
    let go: (String?) -> Void

    var body: some View {
        let parts = Array(screen.components.enumerated())
        VStack(spacing: 0) {
            Text(verbatim: screen.title)
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.text)
                .frame(maxWidth: .infinity)
                .padding(PebbleSpace.s3)
                .background(PebbleColor.soft)
            VStack(alignment: .leading, spacing: PebbleSpace.s3) {
                ForEach(parts.filter { !Self.isNav($0.element) }, id: \.offset) { index, component in
                    PrototypeComponentView(
                        component: component, text: field("\(screen.id)/\(index)"), isOn: toggle("\(screen.id)/\(index)"),
                        go: go)
                }
            }
            .padding(PebbleSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(parts.filter { Self.isNav($0.element) }, id: \.offset) { _, component in
                if case .nav(let links) = component {
                    PrototypeTabs(links: links, current: screen.id, go: go)
                }
            }
        }
        .frame(maxWidth: 380)
        .background(PebbleColor.panel, in: .rect(cornerRadius: PebbleRadius.lg))
        .clipShape(.rect(cornerRadius: PebbleRadius.lg))
        .overlay { RoundedRectangle(cornerRadius: PebbleRadius.lg).stroke(PebbleColor.lineStrong, lineWidth: 1) }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppCopy.Views.demoScreen(screen.title))
    }

    static func isNav(_ component: NativeView.Prototype.Component) -> Bool {
        if case .nav = component { true } else { false }
    }

    private func field(_ key: String) -> Binding<String> {
        Binding(get: { fields[key] ?? "" }, set: { fields[key] = String($0.prefix(200)) })
    }

    private func toggle(_ key: String) -> Binding<Bool> {
        Binding(get: { toggles[key] ?? false }, set: { toggles[key] = $0 })
    }
}
