/// The sheets a conversation opens from its composer's "+" menu and its title menu (and a new conversation from its
/// where control).
enum ConversationSheet: String, Identifiable {
    case terminalCommand
    case webSource
    case connectProject

    var id: String { rawValue }
}
