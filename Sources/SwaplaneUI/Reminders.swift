import Foundation
import UserNotifications
import Usage

/// Per-account "tell me when my limit resets" preference.
public struct ReminderPrefs: Codable, Equatable, Sendable {
    public var enabled = false
    public var session = true
    public var weekly = true
    public init() {}
}

/// Schedules local notifications at each window's reset time. Needs the app running (login item),
/// notification permission and a known reset time; otherwise it does nothing.
@MainActor
enum Reminders {
    private static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sync(group: UUID, label: String, prefs: ReminderPrefs, snapshot: UsageSnapshot?) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        let ids = ["Session", "Weekly"].map { "reset-\(group.uuidString)-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard prefs.enabled, let snapshot else { return }
        for w in snapshot.windows {
            guard (w.name == "Session" && prefs.session) || (w.name == "Weekly" && prefs.weekly),
                let at = w.resetsAt, at > Date()
            else { continue }
            let c = UNMutableNotificationContent()
            c.title = "AI Swaplane"
            c.body = "\(label): \(w.name.lowercased()) limit reset. It's available again."
            c.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: at.timeIntervalSinceNow, repeats: false)
            center.add(UNNotificationRequest(identifier: "reset-\(group.uuidString)-\(w.name)", content: c, trigger: trigger))
        }
    }
}
