import SwiftUI
import Combine
import UserNotifications
import EventKit

// MARK: - Models

struct CalendarEvent: Identifiable, Codable {
    var id = UUID()
    var title: String
    var notes: String
    var date: Date
    var reminderMinutes: Int
    var emoji: String
    var notificationID: String = UUID().uuidString
    var appleEventID: String? = nil

    var reminderLabel: String {
        switch reminderMinutes {
        case 0: return "At time of event"
        case 5: return "5 minutes before"
        case 10: return "10 minutes before"
        case 15: return "15 minutes before"
        case 30: return "30 minutes before"
        case 60: return "1 hour before"
        case 120: return "2 hours before"
        case 1440: return "1 day before"
        default: return "\(reminderMinutes) minutes before"
        }
    }
}

// MARK: - Event Store

class EventStore: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var appleEvents: [EKEvent] = []
    @Published var isCalendarAuthorized = false
    @Published var calendarError: String? = nil

    let ekStore = EKEventStore()

    init() {
        load()
        requestNotificationPermission()
        requestCalendarPermission()
    }

    // MARK: - Permissions

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func requestCalendarPermission() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            DispatchQueue.main.async {
                self.isCalendarAuthorized = true
                self.fetchAppleCalendarEvents()
            }
        case .notDetermined:
            if #available(iOS 17.0, *) {
                ekStore.requestFullAccessToEvents { granted, error in
                    DispatchQueue.main.async {
                        self.isCalendarAuthorized = granted
                        if granted { self.fetchAppleCalendarEvents() }
                        else { self.calendarError = error?.localizedDescription }
                    }
                }
            } else {
                ekStore.requestAccess(to: .event) { granted, error in
                    DispatchQueue.main.async {
                        self.isCalendarAuthorized = granted
                        if granted { self.fetchAppleCalendarEvents() }
                        else { self.calendarError = error?.localizedDescription }
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.calendarError = "Calendar access denied. Please enable in Settings."
            }
        default:
            break
        }
    }

    // MARK: - Apple Calendar

    func fetchAppleCalendarEvents(for date: Date = Date()) {
        guard isCalendarAuthorized else { return }

        // Fetch 30 days around the current month
        let start = Calendar.current.date(byAdding: .day, value: -15, to: date) ?? date
        let end = Calendar.current.date(byAdding: .day, value: 45, to: date) ?? date

        let predicate = ekStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = ekStore.events(matching: predicate)

        DispatchQueue.main.async {
            self.appleEvents = ekEvents.sorted { $0.startDate < $1.startDate }
        }
    }

    func appleEventsForDate(_ date: Date) -> [EKEvent] {
        appleEvents.filter { event in
            Calendar.current.isDate(event.startDate, inSameDayAs: date)
        }
    }

    func addToAppleCalendar(event: CalendarEvent) {
        guard isCalendarAuthorized else { return }

        let ekEvent = EKEvent(eventStore: ekStore)
        ekEvent.title = "\(event.emoji) \(event.title)"
        ekEvent.notes = event.notes
        ekEvent.startDate = event.date
        ekEvent.endDate = event.date.addingTimeInterval(3600)
        ekEvent.calendar = ekStore.defaultCalendarForNewEvents

        let alarm = EKAlarm(relativeOffset: TimeInterval(-event.reminderMinutes * 60))
        ekEvent.addAlarm(alarm)

        do {
            try ekStore.save(ekEvent, span: .thisEvent)
            fetchAppleCalendarEvents()
        } catch {
            calendarError = "Could not save to Apple Calendar: \(error.localizedDescription)"
        }
    }

    // MARK: - App Events

    func save() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: "calendarEvents")
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: "calendarEvents"),
           let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
            self.events = decoded
        }
    }

    func eventsForDate(_ date: Date) -> [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    func addEvent(_ event: CalendarEvent) {
        let newEvent = event
        events.append(newEvent)
        scheduleNotification(for: newEvent)
        save()

        // Also add to Apple Calendar if authorized
        if isCalendarAuthorized {
            addToAppleCalendar(event: newEvent)
        }
    }

    func deleteEvent(_ event: CalendarEvent) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [event.notificationID])
        events.removeAll { $0.id == event.id }
        save()
    }

    func scheduleNotification(for event: CalendarEvent) {
        let content = UNMutableNotificationContent()
        content.title = "\(event.emoji) \(event.title)"
        content.body = event.notes.isEmpty ? "Time for your event!" : event.notes
        content.sound = .default

        let triggerDate = event.date.addingTimeInterval(TimeInterval(-event.reminderMinutes * 60))
        guard triggerDate > Date() else { return }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: event.notificationID,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    func upcomingEvents(days: Int = 3) -> [CalendarEvent] {
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return events
            .filter { $0.date >= now && $0.date <= future }
            .sorted { $0.date < $1.date }
    }
}
