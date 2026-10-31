import Foundation
import RenewerCore
import UserNotifications

/// Mac notifications. Only the installed app posts them: a bare executable (a development run) has no bundle id to
/// post with, so it logs the words instead.
@MainActor
final class Notifier {
    private let log: FileLog
    let isAvailable: Bool

    init(log: FileLog) {
        self.log = log
        isAvailable = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    /// Asked at launch, while someone is looking (macOS shows its question once), not at 2 a.m. when one is needed.
    func requestPermission() {
        guard isAvailable else { return }
        let log = self.log
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { @Sendable granted, error in
            if let error {
                log.write("Notifications: asking for permission failed: \(error.localizedDescription)")
            } else if !granted {
                log.write("Notifications are off for Pebble Remote Renewer (System Settings › Notifications).")
            }
        }
    }

    func post(_ notice: Notice, words: NoticeWords) {
        guard isAvailable else {
            log.write("Notification not shown (not running as the installed app): \(words.title) \(words.body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = words.title
        content.body = words.body
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: "renewer-\(notice.rawValue)", content: content, trigger: nil)
        let log = self.log
        let title = words.title
        UNUserNotificationCenter.current().add(request) { @Sendable error in
            if let error { log.write("Notification \"\(title)\" couldn't be posted: \(error.localizedDescription)") }
        }
    }
}
