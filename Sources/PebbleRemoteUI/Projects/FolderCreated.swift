import Accessibility
import PebbleDesign

/// Pebble's confirmation once a folder is made on the Mac. On screen the new folder opens; VoiceOver hears it said.
enum FolderCreated {
    static func announce(_ name: String) {
        AccessibilityNotification.Announcement(AppCopy.ConnectProject.folderMade(name)).post()
    }
}
