import Accessibility
import PebbleDesign
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Copy from a message's long press: on this iPhone's own clipboard, never through the Mac (lane Z brief, item 2: the
/// Mac's Copy is window-only, so nothing is sent). VoiceOver hears "Copied", as the Mac's toast says it.
enum MessageClipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        AccessibilityNotification.Announcement(AppCopy.Conversation.copied).post()
    }
}
