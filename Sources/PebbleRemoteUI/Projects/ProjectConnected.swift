import Accessibility
import PebbleDesign

/// Pebble's confirmation once a folder is connected ("Project connected. Source reads stay inside this folder."). On
/// screen the conversation's place says it; VoiceOver hears Pebble's sentence.
enum ProjectConnected {
    static func announce() {
        AccessibilityNotification.Announcement(AppCopy.ConnectProject.connected).post()
    }
}
