import SwiftUI

/// The context menu of a message (`MessageMenu`), in Pebble's words: Copy and Copy Code; the message's links, opened on
/// this iPhone; then Edit or Retry, each with Pebble's line on what it does (a new message; this one stays). Several code
/// blocks or links sit in a submenu, each named by its first line or its address.
struct MessageMenuItems: View {
    let menu: MessageMenu
    let role: MessageBubble.Role

    var body: some View {
        Section {
            if menu.items.contains(.copy) {
                Button(AppCopy.MessageMenu.copy, systemImage: "doc.on.doc") { menu.perform(.copy) }
                    .accessibilityLabel(role == .person ? AppCopy.MessageMenu.copyYourMessage : AppCopy.MessageMenu.copyReply)
            }
            if codes.count == 1, let code = codes.first {
                Button(AppCopy.MessageMenu.copyCode, systemImage: Self.codeSymbol) { menu.perform(.copyCode(code)) }
            } else if codes.count > 1 {
                Menu(AppCopy.MessageMenu.copyCode, systemImage: Self.codeSymbol) {
                    ForEach(codes.indices, id: \.self) { index in
                        Button(AppCopy.MessageMenu.codeBlock(MessageMenu.firstLine(codes[index]))) {
                            menu.perform(.copyCode(codes[index]))
                        }
                    }
                }
            }
        }
        Section {
            if links.count == 1, let url = links.first {
                Button {
                    menu.perform(.openLink(url))
                } label: {
                    Label(AppCopy.MessageMenu.openLink, systemImage: "link")
                    Text(MessageMenu.linkName(url))
                }
            } else if links.count > 1 {
                Menu(AppCopy.MessageMenu.openLink, systemImage: "link") {
                    ForEach(links, id: \.self) { url in
                        Button(MessageMenu.linkName(url)) { menu.perform(.openLink(url)) }
                    }
                }
            }
        }
        Section {
            if menu.items.contains(.edit) {
                Button {
                    menu.perform(.edit)
                } label: {
                    Label(AppCopy.MessageMenu.edit, systemImage: "pencil")
                    Text(AppCopy.MessageMenu.editNote)
                }
            }
            if menu.items.contains(.retry) {
                Button {
                    menu.perform(.retry)
                } label: {
                    Label(AppCopy.MessageMenu.retry, systemImage: Self.retrySymbol)
                    Text(AppCopy.MessageMenu.retryNote)
                }
            } else if let reason = unavailable {
                Button {
                } label: {
                    Label(AppCopy.MessageMenu.retry, systemImage: Self.retrySymbol)
                    Text(reason)
                }
                .disabled(true)
            }
        }
    }

    static let codeSymbol = "chevron.left.forwardslash.chevron.right"
    static let retrySymbol = "arrow.clockwise"

    private var codes: [String] {
        menu.items.compactMap { item in
            if case .copyCode(let code) = item { code } else { nil }
        }
    }

    private var links: [URL] {
        menu.items.compactMap { item in
            if case .openLink(let url) = item { url } else { nil }
        }
    }

    private var unavailable: String? {
        menu.items.lazy.compactMap { item in
            if case .retryUnavailable(let reason) = item { reason } else { nil }
        }.first
    }
}

extension View {
    /// A message's context menu, lifted in the message's own shape. None without a menu, or with nothing in it.
    @ViewBuilder
    func messageMenu(_ menu: MessageMenu?, role: MessageBubble.Role, preview shape: some Shape) -> some View {
        if let menu, !menu.items.isEmpty {
            self
                // The lifted shape is iOS's (ContentShapeKinds.contextMenuPreview is unavailable on macOS).
                #if os(iOS)
                .contentShape(.contextMenuPreview, shape)
                #endif
                .contextMenu {
                    MessageMenuItems(menu: menu, role: role)
                }
        } else {
            self
        }
    }

    /// The person can select the text where nothing else answers a long press; with a message menu, Copy is in it.
    @ViewBuilder
    func selectable(_ on: Bool) -> some View {
        if on {
            textSelection(.enabled)
        } else {
            self
        }
    }
}
