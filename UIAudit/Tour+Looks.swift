import PebbleDesign
import XCTest

extension AuditSession {
    /// The key screens in another look (the largest accessibility text size, or the other appearance), for this app
    /// only: the phone's own settings stay as they are.
    ///
    /// At accessibility sizes a conversation and a new one hide the tab bar (lane V's U-43), so `openTab` goes Back
    /// first. In the re-check this area stayed in one conversation without that. At the largest size the tour also
    /// checks:
    /// - that the ⋯ menu holds Model and Effort (U-52);
    /// - that a conversation's keyboard closes with Back in reach.
    func tourKeyScreens(look: Look) {
        launch(pace: 6, look: look)
        snap("pebble-tab")
        if tap(where: Self.modeChip, named: "the mode chip") {
            snap("mode-sheet")
            leaveSheet("How Pebble Acts")
        }
        if openChat(Demo.login) {
            snap("conversation-working")
            if let menu = openMenu(AppCopy.Conversation.more, in: [.button]) {
                snap("conversation-more-menu")
                if look == .largestText {
                    let hasModel = menu.contains { $0.label.hasPrefix(AppCopy.Control.model) }
                    let hasEffort = menu.contains { $0.label.hasPrefix(AppCopy.Control.effort) }
                    let items = menu.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
                    note(
                        "At the largest size the ⋯ menu has \(hasModel ? "Model" : "no Model") and "
                            + "\(hasEffort ? "Effort" : "no Effort") (U-52); its items: \(items).",
                        kind: .observation)
                }
                closeMenu(menu)
            }
            if look == .largestText {
                keyboardCheck(
                    "a conversation's composer at the largest size", shot: "conversation-composer", exit: .swipeDown,
                    open: { openComposer() })
            }
            // Details (lane Y): at accessibility sizes its sections are a menu instead of segments.
            if openDetails() {
                snap("details")
                if look == .largestText {
                    var opened = false
                    for name in [AppCopy.Details.sections, AppCopy.Details.activity] where !opened {
                        guard element(name, in: [.button], timeout: 0.5) != nil,
                            let menu = openMenu(name, in: [.button])
                        else { continue }
                        opened = true
                        snap("details-sections-menu", audit: false)
                        closeMenu(menu)
                    }
                    if !opened {
                        note("At the largest size, Details' sections menu wasn't found.", kind: .observation)
                    }
                }
                leaveSheet("Details")
            }
        }
        toRoot(of: AppCopy.Tabs.chats)
        snap("chats")
        scrollDown()
        snap("chats-further")
        if openChat(Demo.theme) {
            scrollDown()
            snap("held-change-decisions")
        }
        if openChat(Demo.site) {
            scrollDown()
            snap("command-cards")
        }
        toRoot(of: AppCopy.Tabs.chats)
        if tap(AppCopy.Chats.newConversation, in: [.button]) {
            snap("new-conversation")
            if let menu = openMenu(AppCopy.AddContext.title, in: [.button]) {
                snap("add-context-menu")
                closeMenu(menu)
            }
        }
        openTab(AppCopy.Tabs.reviews)
        snap("reviews")
        scrollDown()
        snap("reviews-further")
        toRoot(of: AppCopy.Tabs.control)
        snap("settings")
        scrollDown()
        snap("settings-further")
        // The iPhone section: the phone's own settings, on the Settings root since round 2 (no "Settings" row any more).
        if find(AppCopy.Connection.title, in: [.button, .cell]) != nil {
            snap("settings-iphone-section")
        }
    }
}
