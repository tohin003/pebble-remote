import SwiftUI

/// A menu picker whose value lives on the Mac (the theme, status words): it moves at once when chosen, sends the
/// change, and goes back to the Mac's value if the call fails. A change made on the Mac moves it too.
struct RemoteMenuPicker: View {
    let title: String
    var subtitle: String? = nil
    let choices: [Choice]
    /// The Mac's value, as the store last heard it.
    let value: String
    /// Sends the change; returns whether the Mac took it.
    let send: (String) async -> Bool

    @State private var shown: String
    @State private var isSending = false

    init(
        _ title: String, subtitle: String? = nil, choices: [Choice], value: String,
        send: @escaping (String) async -> Bool
    ) {
        self.title = title
        self.subtitle = subtitle
        self.choices = choices
        self.value = value
        self.send = send
        _shown = State(initialValue: value)
    }

    var body: some View {
        Picker(selection: $shown) {
            ForEach(choices) { choice in
                Text(choice.title).tag(choice.id)
            }
        } label: {
            Text(title)
            if let subtitle {
                Text(subtitle)
            }
        }
        .pickerStyle(.menu)
        .disabled(isSending)
        .onChange(of: value) { _, newValue in
            shown = newValue
        }
        .onChange(of: shown) { _, newValue in
            guard newValue != value, !isSending else { return }
            Task { await change(to: newValue) }
        }
    }

    private func change(to newValue: String) async {
        isSending = true
        let took = await send(newValue)
        isSending = false
        if !took { shown = value }
    }
}
