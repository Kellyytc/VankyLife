import SwiftUI
import UserNotifications

// ─────────────────────────────────────────────────────────────────────────────
// Reminder to reinstall the app before it expires.
//
// With a free Apple account, an app installed from Xcode stops opening 7 days after
// it was installed. The real expiry date is inside the app's own signing profile
// (embedded.mobileprovision), so the app reads it and schedules:
//   • a reminder at 9 AM the day before it expires
//   • a last reminder 2 hours before it expires
// Each time you reinstall from Xcode, the new date is read and the reminders move.
//
// Main app target only.
// ─────────────────────────────────────────────────────────────────────────────

enum AppExpiry {
    private static let dayBeforeID = "appExpiry.dayBefore"
    private static let lastCallID = "appExpiry.lastCall"

    /// When this install stops opening, read from the signing profile. nil in the Simulator
    /// or for App Store / TestFlight builds, which have no such limit.
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        // The profile is a signed wrapper around a plain XML property list
        let ascii = String(decoding: data, as: UTF8.self)
        guard let start = ascii.range(of: "<?xml"),
              let end = ascii.range(of: "</plist>", range: start.upperBound..<ascii.endIndex) else { return nil }
        let xml = Data(ascii[start.lowerBound..<end.upperBound].utf8)
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any] else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    static var timeLeft: TimeInterval? { expirationDate.map { $0.timeIntervalSinceNow } }

    /// Call at launch and whenever the app opens; it replaces any earlier reminders.
    static func scheduleReminders() {
        guard let expiry = expirationDate, expiry > Date() else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: [dayBeforeID, lastCallID])

            let cal = Calendar.current
            let timeText = expiry.formatted(date: .omitted, time: .shortened)
            let dayText = expiry.formatted(.dateTime.weekday(.wide))

            // 9 AM the day before; if that has already passed, 24 hours before; else skip
            var dayBefore = cal.date(bySettingHour: 9, minute: 0, second: 0,
                                     of: cal.date(byAdding: .day, value: -1, to: expiry) ?? expiry) ?? expiry
            if dayBefore <= Date() { dayBefore = expiry.addingTimeInterval(-24 * 3600) }
            if dayBefore > Date() {
                add(id: dayBeforeID, at: dayBefore,
                    title: "Vanky Life expires tomorrow",
                    body: "It stops opening \(dayText) at \(timeText). Plug in your iPhone and run it again from Xcode.",
                    center: center)
            }

            let lastCall = expiry.addingTimeInterval(-2 * 3600)
            if lastCall > Date() {
                add(id: lastCallID, at: lastCall,
                    title: "Vanky Life expires in 2 hours",
                    body: "Reinstall from Xcode before \(timeText) so it keeps opening. Your data stays on the phone.",
                    center: center)
            }
        }
    }

    private static func add(id: String, at date: Date, title: String, body: String, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// A thin strip at the top of the app once less than 2 days are left.
struct AppExpiryBanner: View {
    var body: some View {
        if let expiry = AppExpiry.expirationDate, let left = AppExpiry.timeLeft, left > 0, left < 2 * 24 * 3600 {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark")
                Text("App expires \(expiry.formatted(.relative(presentation: .named))). Reinstall from Xcode.")
                    .font(.caption).fontWeight(.medium)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(left < 6 * 3600 ? Color.red : Color.orange)
        }
    }
}
