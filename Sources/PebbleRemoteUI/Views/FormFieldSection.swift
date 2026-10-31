import PebbleDesign
import PebbleProtocol
import SwiftUI

/// One field of a Pebble form, with the system's own controls: a choice as an inline picker (a checkmark on the chosen
/// row), text as a one-line field whose Return closes the keyboard and sends nothing (the person's keyboard rule).
/// The field's words are the model's: shown literally, as the section's header in sentence case.
struct FormFieldSection: View {
    let field: NativeView.Form.Field
    @Binding var choice: String?
    @Binding var text: String
    let isEnabled: Bool
    var focus: FocusState<String?>.Binding

    var body: some View {
        Section {
            switch field.kind {
            case .choice:
                Picker(selection: $choice) {
                    ForEach(field.options) { option in
                        Text(verbatim: option.label)
                            .tag(Optional(option.id))
                    }
                } label: {
                    Text(verbatim: field.label)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(!isEnabled)
            case .text:
                TextField(text: $text, prompt: Text(verbatim: field.placeholder ?? AppCopy.Views.writeHere)) {
                    Text(verbatim: field.label)
                }
                .focused(focus, equals: field.id)
                .submitLabel(.done)
                .onSubmit { focus.wrappedValue = nil }
                .disabled(!isEnabled)
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: field.label)
                    .textCase(nil)
                    .foregroundStyle(PebbleColor.text)
                Spacer(minLength: PebbleSpace.s2)
                Text(AppCopy.Views.required)
                    .textCase(nil)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            .font(PebbleFont.cardBody)
            .accessibilityElement(children: .combine)
        }
    }
}
