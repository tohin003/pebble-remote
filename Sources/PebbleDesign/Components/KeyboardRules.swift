import SwiftUI

/// The person can always close the keyboard without sending (the lead's rule, 2026-10-30, after the person was left with
/// a keyboard that wouldn't close): a form's scroll closes it (`scrollDismissesKeyboard(.interactively)`), a sheet keeps
/// a visible Cancel or Done, and Return or Send in an empty field drops the field's focus. Where a list or a transcript
/// sits above the field, a tap on it closes the keyboard too (`closesKeyboardOnTap`): on the Pebble tab, in Chats'
/// search, in a conversation and in a new one (the person, 2026-10-31: "in chats the keyboard … gets stuck"). In
/// PebbleDesign so its own cards keep the rule too (a question's written answer, the re-check's U-54).
public enum KeyboardRules {
    /// Return pressed in a multi-line field that held nothing: the text is blank space with a line break in it.
    public static func isEmptyReturn(_ text: String) -> Bool {
        text.contains(where: \.isNewline) && text.allSatisfy(\.isWhitespace)
    }
}

extension View {
    /// A multi-line field: Return while it holds nothing closes the keyboard instead of adding a blank line. (A one-line
    /// field's Return already ends editing.)
    public func closesKeyboardOnEmptyReturn(_ text: Binding<String>, focus: FocusState<Bool>.Binding) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            guard KeyboardRules.isEmptyReturn(new) else { return }
            text.wrappedValue = ""
            focus.wrappedValue = false
        }
    }

    /// A tap anywhere on this view closes the keyboard of the field `focus` belongs to. The tap is simultaneous, so rows,
    /// links and buttons still take theirs; it listens only while the field has the keyboard; and the whole frame takes
    /// it, the gaps between a transcript's rows and the room above a short one included.
    public func closesKeyboardOnTap(_ focus: FocusState<Bool>.Binding) -> some View {
        contentShape(.rect)
            .simultaneousGesture(
                TapGesture().onEnded { focus.wrappedValue = false },
                including: focus.wrappedValue ? .all : .subviews)
    }
}
