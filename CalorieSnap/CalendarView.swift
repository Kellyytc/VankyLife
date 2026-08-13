import SwiftUI
import Combine
import EventKit
import UserNotifications

// MARK: - Event Store (Apple Calendar + custom events)

class EventStore: ObservableObject {
    @Published var events: [CalendarEvent] = [] { didSet { saveEvents(); scheduleAllCountdownNotifications() } }
    @Published var appleEvents: [EKEvent] = []
    @Published var isCalendarAuthorized = false
    @Published var calendarError: String? = nil

    private let ekStore = EKEventStore()

    init() { loadEvents(); requestCalendarPermission(); requestNotificationPermission() }

    // MARK: Custom events persistence
    func saveEvents() {
        if let d = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(d, forKey: "calendarEvents_v2")
        }
    }
    func loadEvents() {
        if let d = UserDefaults.standard.data(forKey: "calendarEvents_v2"),
           let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: d) {
            events = decoded; return
        }
    }
    func addEvent(_ event: CalendarEvent) { events.append(event) }
    func deleteEvent(_ event: CalendarEvent) { events.removeAll { $0.id == event.id } }
    func updateEvent(_ event: CalendarEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) { events[i] = event }
    }
    func eventsForDate(_ date: Date) -> [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    // MARK: Apple Calendar
    func requestCalendarPermission() {
        if #available(iOS 17.0, *) {
            ekStore.requestFullAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    self.isCalendarAuthorized = granted
                    if granted { self.fetchAppleCalendarEvents(for: Date()) }
                    else if let e = error { self.calendarError = e.localizedDescription }
                }
            }
        } else {
            ekStore.requestAccess(to: .event) { granted, error in
                DispatchQueue.main.async {
                    self.isCalendarAuthorized = granted
                    if granted { self.fetchAppleCalendarEvents(for: Date()) }
                    else if let e = error { self.calendarError = e.localizedDescription }
                }
            }
        }
    }

    func fetchAppleCalendarEvents(for date: Date) {
        let start = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let end   = Calendar.current.date(byAdding: .month, value: 3,  to: Date()) ?? Date()
        let predicate = ekStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        DispatchQueue.main.async {
            self.appleEvents = self.ekStore.events(matching: predicate)
            self.calendarError = nil
        }
    }

    func appleEventsForDate(_ date: Date) -> [EKEvent] {
        appleEvents.filter { event in
            guard let start = event.startDate else { return false }
            let end = event.endDate ?? start
            return Calendar.current.isDate(start, inSameDayAs: date)
                || (start < Calendar.current.startOfDay(for: date) && end > date)
        }.sorted { ($0.startDate ?? Date()) < ($1.startDate ?? Date()) }
    }

    func hasAnyEventOnDate(_ date: Date) -> Bool {
        !eventsForDate(date).isEmpty || !appleEventsForDate(date).isEmpty
    }

    // MARK: - Push Notifications for Countdown Events

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleAllCountdownNotifications() {
        // Remove all existing countdown notifications first
        let ids = events.filter { $0.isCountdown }.map { "countdown-\($0.id.uuidString)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        // Schedule for each countdown event
        for event in events where event.isCountdown {
            scheduleNotification(for: event)
        }
    }

    func scheduleNotification(for event: CalendarEvent) {
        let center = UNUserNotificationCenter.current()
        let baseID = "countdown-\(event.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [baseID, baseID + "-week", baseID + "-day"])

        let cal = Calendar.current

        // Helper to create and schedule a notification
        func schedule(id: String, title: String, body: String, date: Date) {
            guard date > Date() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        if event.isAnniversary {
            // Schedule notification on the anniversary day itself (9 AM)
            // For yearly events, find next occurrence
            var nextComps = cal.dateComponents([.month, .day], from: event.date)
            nextComps.year = cal.component(.year, from: Date())
            nextComps.hour = 9; nextComps.minute = 0
            var nextDate = cal.date(from: nextComps) ?? event.date
            if nextDate < Date() {
                nextComps.year! += 1
                nextDate = cal.date(from: nextComps) ?? event.date
            }
            let years = cal.dateComponents([.year], from: event.date, to: nextDate).year ?? 0
            let yearsText = years > 0 ? " \(years) year\(years == 1 ? "" : "s")!" : "!"
            schedule(id: baseID,
                     title: "🎉 \(event.emoji) \(event.title)\(yearsText)",
                     body: years > 0
                        ? "Today marks \(years) year\(years == 1 ? "" : "s"). Time to celebrate! 🥂"
                        : "Today is the day! Don't forget to celebrate 🎊",
                     date: nextDate)

            // Also notify 1 week before
            if let weekBefore = cal.date(byAdding: .day, value: -7, to: nextDate) {
                schedule(id: baseID + "-week",
                         title: "⏳ \(event.emoji) \(event.title) in 7 days",
                         body: years > 0
                            ? "One week until \(years) year\(years == 1 ? "" : "s") together!"
                            : "One week until \(event.title)!",
                         date: weekBefore)
            }

            // And 1 day before
            if let dayBefore = cal.date(byAdding: .day, value: -1, to: nextDate) {
                schedule(id: baseID + "-day",
                         title: "🌟 \(event.emoji) Tomorrow is \(event.title)!",
                         body: years > 0
                            ? "Tomorrow marks \(years) year\(years == 1 ? "" : "s"). Plan something special! 💕"
                            : "Tomorrow is \(event.title)! Get ready to celebrate 🎊",
                         date: dayBefore)
            }

        } else {
            // One-time countdown event
            let targetDate = event.date
            guard targetDate > Date() else { return }

            // On the day itself at 9 AM
            var dayComps = cal.dateComponents([.year, .month, .day], from: targetDate)
            dayComps.hour = 9; dayComps.minute = 0
            if let dayDate = cal.date(from: dayComps) {
                schedule(id: baseID,
                         title: "🎉 \(event.emoji) Today is the day!",
                         body: "\(event.title) is today! \(event.notes.isEmpty ? "" : event.notes)",
                         date: dayDate)
            }

            // 1 week before
            if let weekBefore = cal.date(byAdding: .day, value: -7, to: targetDate) {
                schedule(id: baseID + "-week",
                         title: "⏳ \(event.emoji) \(event.title) in 1 week",
                         body: "Only 7 days to go! Start preparing 🗓️",
                         date: weekBefore)
            }

            // 1 day before
            if let dayBefore = cal.date(byAdding: .day, value: -1, to: targetDate) {
                schedule(id: baseID + "-day",
                         title: "🌟 \(event.emoji) Tomorrow: \(event.title)",
                         body: "Tomorrow is the big day! Get ready 🎊",
                         date: dayBefore)
            }
        }
    }
}

// MARK: - Calendar Event Model (custom events with reminder + countdown)

struct CalendarEvent: Identifiable, Codable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var date: Date
    var emoji: String = "📅"
    var reminderMinutes: Int = 15
    // Countdown fields
    var isCountdown: Bool = false
    var isAnniversary: Bool = false

    var reminderLabel: String {
        switch reminderMinutes {
        case 0:    return "At event time"
        case 5:    return "5 min before"
        case 10:   return "10 min before"
        case 15:   return "15 min before"
        case 30:   return "30 min before"
        case 60:   return "1 hour before"
        case 120:  return "2 hours before"
        case 1440: return "1 day before"
        default:   return "\(reminderMinutes) min before"
        }
    }

    var daysFromNow: Int {
        let cal = Calendar.current; let now = cal.startOfDay(for: Date())
        if isCountdown {
            if isAnniversary {
                var comps = cal.dateComponents([.month, .day], from: date)
                comps.year = cal.component(.year, from: now)
                var next = cal.date(from: comps) ?? date
                if next < now { comps.year! += 1; next = cal.date(from: comps) ?? date }
                return cal.dateComponents([.day], from: now, to: next).day ?? 0
            }
            return cal.dateComponents([.day], from: now, to: cal.startOfDay(for: date)).day ?? 0
        }
        return 0
    }

    var isToday: Bool { isCountdown && daysFromNow == 0 }

    var anniversaryYears: Int? {
        guard isAnniversary else { return nil }
        return Calendar.current.dateComponents([.year],
            from: Calendar.current.startOfDay(for: date),
            to: Calendar.current.startOfDay(for: Date())).year
    }

    var countdownLabel: String {
        if isToday { return "Today 🎉" }
        if daysFromNow < 0 { return "Passed" }
        if daysFromNow == 1 { return "Tomorrow" }
        return "\(daysFromNow)d"
    }

    var urgencyColor: Color {
        if isToday { return .orange }
        if daysFromNow <= 7  { return .red }
        if daysFromNow <= 30 { return .orange }
        return .blue
    }
}

// MARK: - Weight Entry

struct WeightEntry: Identifiable, Codable {
    var id = UUID()
    var weight: Double
    var time: Date
    var note: String = ""
    var timeLabel: String { let f = DateFormatter(); f.timeStyle = .short; return f.string(from: time) }
    var periodLabel: String {
        let h = Calendar.current.component(.hour, from: time)
        if h < 12 { return "Morning" }; if h < 17 { return "Afternoon" }; return "Evening"
    }
}

// MARK: - Day Log

struct DayLog: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var calories: Int
    var carbs: Double
    var protein: Double
    var fat: Double
    var weightEntries: [WeightEntry] = []

    var latestWeight: Double? { weightEntries.sorted { $0.time > $1.time }.first?.weight }
    var weight: Double? { latestWeight }

    var dateKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decodeIfPresent(UUID.self,   forKey: .id) ?? UUID()
        date     = try c.decode(Date.self, forKey: .date)
        calories = try c.decodeIfPresent(Int.self,    forKey: .calories) ?? 0
        carbs    = try c.decodeIfPresent(Double.self, forKey: .carbs)    ?? 0
        protein  = try c.decodeIfPresent(Double.self, forKey: .protein)  ?? 0
        fat      = try c.decodeIfPresent(Double.self, forKey: .fat)      ?? 0
        if let entries = try c.decodeIfPresent([WeightEntry].self, forKey: .weightEntries) {
            weightEntries = entries
        } else if let old = try c.decodeIfPresent(Double.self, forKey: .oldWeight) {
            weightEntries = [WeightEntry(weight: old, time: date)]
        } else { weightEntries = [] }
    }

    init(date: Date, calories: Int = 0, carbs: Double = 0, protein: Double = 0,
         fat: Double = 0, weightEntries: [WeightEntry] = []) {
        self.date = date; self.calories = calories; self.carbs = carbs
        self.protein = protein; self.fat = fat; self.weightEntries = weightEntries
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(date, forKey: .date)
        try c.encode(calories, forKey: .calories); try c.encode(carbs, forKey: .carbs)
        try c.encode(protein, forKey: .protein); try c.encode(fat, forKey: .fat)
        try c.encode(weightEntries, forKey: .weightEntries)
    }

    enum CodingKeys: String, CodingKey {
        case id, date, calories, carbs, protein, fat, weightEntries
        case oldWeight = "weight"
    }
}

// MARK: - Calendar Store

class CalendarStore: ObservableObject {
    @Published var dayLogs: [DayLog] = [] { didSet { save() } }

    init() { load() }

    func weightForDate(_ date: Date) -> Double? { logForDate(date)?.latestWeight }
    func weightEntriesForDate(_ date: Date) -> [WeightEntry] {
        logForDate(date)?.weightEntries.sorted { $0.time < $1.time } ?? []
    }
    func addWeightEntry(weight: Double, note: String = "", date: Date = Date()) {
        let entry = WeightEntry(weight: weight, time: date, note: note)
        let cal = Calendar.current
        if let i = dayLogs.firstIndex(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            dayLogs[i].weightEntries.append(entry)
        } else {
            var log = DayLog(date: date); log.weightEntries = [entry]; dayLogs.append(log)
        }
    }
    func deleteWeightEntry(_ entry: WeightEntry, date: Date) {
        let cal = Calendar.current
        if let i = dayLogs.firstIndex(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            dayLogs[i].weightEntries.removeAll { $0.id == entry.id }
        }
    }
    func logForDate(_ date: Date) -> DayLog? {
        dayLogs.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
    func saveLog(_ log: DayLog) {
        let cal = Calendar.current
        if let i = dayLogs.firstIndex(where: { cal.isDate($0.date, inSameDayAs: log.date) }) {
            dayLogs[i] = log
        } else { dayLogs.append(log) }
    }
    func dateKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    func caloriesForDate(_ date: Date) -> Int { logForDate(date)?.calories ?? 0 }
    func upcomingEvents(store: EventStore, days: Int = 3) -> [CalendarEvent] {
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return store.events.filter { $0.isCountdown && $0.date >= now && $0.date <= future }
            .sorted { $0.date < $1.date }
    }

    func save() {
        if let d = try? JSONEncoder().encode(dayLogs) {
            UserDefaults.standard.set(d, forKey: "calendarDayLogs_v2")
        }
    }
    func load() {
        if let d = UserDefaults.standard.data(forKey: "calendarDayLogs_v2"),
           let decoded = try? JSONDecoder().decode([DayLog].self, from: d) { dayLogs = decoded; return }
        if let d = UserDefaults.standard.data(forKey: "calendarDayLogs"),
           let decoded = try? JSONDecoder().decode([DayLog].self, from: d) { dayLogs = decoded; save() }
    }
}

// MARK: - Calendar View

struct CalendarView: View {
    @ObservedObject var store: CalendarStore
    @StateObject private var eventStore = EventStore()
    @StateObject private var healthKit = HealthKitManager()
    @State private var selectedDate = Date()
    @State private var showDayDetail = false
    @State private var showAddEvent = false
    @State private var showAddCountdown = false
    @State private var editingCountdown: CalendarEvent? = nil
    @State private var celebratingEvent: CalendarEvent? = nil
    @State private var currentMonth = Date()

    var countdownEvents: [CalendarEvent] { eventStore.events.filter { $0.isCountdown } }
    var todayCountdowns: [CalendarEvent] { countdownEvents.filter { $0.isToday } }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {

                    // Today celebration banners
                    if !todayCountdowns.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(todayCountdowns) { event in
                                CelebrationBannerCard(event: event).onTapGesture { celebratingEvent = event }
                            }
                        }.padding(.horizontal)
                    }

                    // Month navigation
                    HStack {
                        Button(action: previousMonth) {
                            Image(systemName: "chevron.left.circle.fill").font(.title2).foregroundColor(.green)
                        }
                        Spacer()
                        Text(monthTitle).font(.title2).fontWeight(.semibold)
                        Spacer()
                        Button(action: nextMonth) {
                            Image(systemName: "chevron.right.circle.fill").font(.title2).foregroundColor(.green)
                        }
                    }.padding(.horizontal).padding(.top, 8)

                    // Day headers
                    HStack(spacing: 0) {
                        ForEach(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"], id: \.self) { day in
                            Text(day).font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity)
                        }
                    }.padding(.horizontal, 8)

                    // Calendar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(calendarDays) { day in
                            if let date = day.date {
                                DayCell(
                                    date: date,
                                    isSelected: isSameDay(date, selectedDate),
                                    isToday: isSameDay(date, Date()),
                                    calories: store.caloriesForDate(date),
                                    weight: store.weightForDate(date),
                                    hasEvent: eventStore.hasAnyEventOnDate(date),
                                    isPeriod: healthKit.isPeriodDate(date),
                                    hasCountdown: countdownEvents.contains { event in
                                        if isSameDay(event.date, date) { return true }
                                        if event.isAnniversary {
                                            let ec = Calendar.current.dateComponents([.month, .day], from: event.date)
                                            let dc = Calendar.current.dateComponents([.month, .day], from: date)
                                            return ec.month == dc.month && ec.day == dc.day
                                        }
                                        return false
                                    },
                                    anniversaryEmoji: anniversaryEmojiForDate(date)
                                )
                                .onTapGesture { selectedDate = date }
                            } else {
                                Color.clear.frame(height: 56)
                            }
                        }
                    }.padding(.horizontal, 8)

                    // Legend
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            LegendDot(color: .purple, label: "Event")
                            LegendDot(color: .pink,   label: "Period")
                            LegendDot(color: .blue,   label: "Countdown")
                            LegendDot(color: .orange,  label: "Today Countdown")
                        }.padding(.horizontal)
                    }

                    // Selected date header + anniversary announcement
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(formattedSelectedDate).font(.headline)
                            Spacer()
                        }
                        ForEach(anniversaryEventsForDate(selectedDate)) { event in
                            AnniversaryDayCard(event: event, selectedDate: selectedDate)
                        }
                    }
                    .padding(.horizontal)

                    // Health summary for selected day
                    if let log = store.logForDate(selectedDate) {
                        DaySummaryCard(log: log, date: selectedDate).padding(.horizontal)
                    } else {
                        EmptyDayCard(date: selectedDate).padding(.horizontal)
                    }

                    // Period tracker card
                    if healthKit.isAuthorized {
                        PeriodSummaryCard(healthKit: healthKit, selectedDate: selectedDate)
                            .padding(.horizontal)
                    }

                    // Events for selected date
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Events").font(.headline)
                            Spacer()
                            if !eventStore.isCalendarAuthorized {
                                Button("Connect Calendar") { eventStore.requestCalendarPermission() }
                                    .font(.caption).foregroundColor(.purple)
                            } else {
                                Button(action: { eventStore.fetchAppleCalendarEvents(for: selectedDate) }) {
                                    Image(systemName: "arrow.clockwise").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }.padding(.horizontal)

                        if let error = eventStore.calendarError {
                            Text(error).font(.caption).foregroundColor(.red).padding(.horizontal)
                        }

                        let appleEvents = eventStore.appleEventsForDate(selectedDate)
                        let dayEvents   = eventStore.eventsForDate(selectedDate).filter { !$0.isCountdown }

                        if !appleEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("From Apple Calendar", systemImage: "calendar")
                                    .font(.caption).foregroundColor(.secondary).padding(.horizontal)
                                ForEach(appleEvents, id: \.eventIdentifier) { event in
                                    AppleEventRow(event: event).padding(.horizontal)
                                }
                            }
                        }

                        if !dayEvents.isEmpty {
                            ForEach(dayEvents) { event in
                                EventRow(event: event, onDelete: { eventStore.deleteEvent(event) })
                                    .padding(.horizontal)
                            }
                        }

                        if appleEvents.isEmpty && dayEvents.isEmpty {
                            Text("No events for this day")
                                .font(.subheadline).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity).padding()
                                .background(.regularMaterial).cornerRadius(12).padding(.horizontal)
                        }
                    }

                    // Countdown events bar
                    if !countdownEvents.isEmpty {
                        CountdownBar(
                            events: countdownEvents,
                            onTap: { event in
                                if event.isToday { celebratingEvent = event }
                                else { editingCountdown = event }
                            },
                            onAdd: { showAddCountdown = true }
                        ).padding(.horizontal)
                    }

                    // Weight trend
                    WeightTrendCard(store: store).padding(.horizontal)
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showAddCountdown = true }) {
                        Image(systemName: "timer.circle").foregroundColor(.blue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showDayDetail = true }) {
                            Label("Log Calories/Macros", systemImage: "heart.text.square")
                        }
                        Button(action: { showAddEvent = true }) {
                            Label("Add Event", systemImage: "calendar.badge.plus")
                        }
                        Button(action: { showAddCountdown = true }) {
                            Label("Add Countdown / Since", systemImage: "timer")
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showDayDetail) {
                DayDetailView(date: selectedDate, store: store)
            }
            .sheet(isPresented: $showAddEvent) {
                AddEventView(eventStore: eventStore, date: selectedDate)
            }
            .sheet(isPresented: $showAddCountdown) {
                AddEditCountdownView(eventStore: eventStore)
            }
            .sheet(item: $editingCountdown) { event in
                AddEditCountdownView(eventStore: eventStore, existing: event)
            }
            .fullScreenCover(item: $celebratingEvent) { event in
                CelebrationFullScreen(event: event) { celebratingEvent = nil }
            }
            .onAppear {
                if !healthKit.isAuthorized { healthKit.requestAuthorization() }
                eventStore.fetchAppleCalendarEvents(for: selectedDate)
            }
        }
    }

    var monthTitle: String { let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: currentMonth) }
    var formattedSelectedDate: String { let f = DateFormatter(); f.dateStyle = .full; return f.string(from: selectedDate) }
    func previousMonth() { currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth }
    func nextMonth()     { currentMonth = Calendar.current.date(byAdding: .month, value:  1, to: currentMonth) ?? currentMonth }
    func isSameDay(_ a: Date, _ b: Date) -> Bool { Calendar.current.isDate(a, inSameDayAs: b) }

    func anniversaryEmojiForDate(_ date: Date) -> String? {
        let dc = Calendar.current.dateComponents([.month, .day], from: date)
        return countdownEvents.first { event in
            guard event.isAnniversary else { return false }
            let ec = Calendar.current.dateComponents([.month, .day], from: event.date)
            return ec.month == dc.month && ec.day == dc.day
        }?.emoji
    }

    func anniversaryEventsForDate(_ date: Date) -> [CalendarEvent] {
        let dc = Calendar.current.dateComponents([.month, .day], from: date)
        return countdownEvents.filter { event in
            guard event.isAnniversary else { return false }
            let ec = Calendar.current.dateComponents([.month, .day], from: event.date)
            return ec.month == dc.month && ec.day == dc.day
        }
    }

    struct CalendarDay: Identifiable { let id: String; let date: Date? }

    var calendarDays: [CalendarDay] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let range = cal.range(of: .day, in: .month, for: start)!
        let firstWeekday = cal.component(.weekday, from: start) - 1
        var days: [CalendarDay] = (0..<firstWeekday).map { CalendarDay(id: "empty-\($0)", date: nil) }
        for day in range {
            days.append(CalendarDay(id: "day-\(day)", date: cal.date(byAdding: .day, value: day - 1, to: start)))
        }
        while days.count % 7 != 0 { days.append(CalendarDay(id: "trail-\(days.count)", date: nil)) }
        return days
    }
}

// MARK: - Legend Dot

struct LegendDot: View {
    let color: Color; let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - Day Cell (restored original style + countdown dot)

struct DayCell: View {
    let date: Date; let isSelected: Bool; let isToday: Bool
    let calories: Int; let weight: Double?; let hasEvent: Bool; let isPeriod: Bool
    var hasCountdown: Bool = false
    var anniversaryEmoji: String? = nil

    var calorieColor: Color {
        if calories == 0 { return .clear }
        if calories < 1500 { return .green.opacity(0.3) }
        if calories < 2000 { return .orange.opacity(0.3) }
        return .red.opacity(0.3)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 14, weight: isToday ? .bold : .regular))
                .foregroundColor(isSelected ? .white : isToday ? .green : .primary)
            if calories > 0 {
                Text("\(calories)").font(.system(size: 9)).foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            } else {
                Text(" ").font(.system(size: 9))
            }
            if let emoji = anniversaryEmoji {
                Text(emoji).font(.system(size: 12))
            } else {
                HStack(spacing: 3) {
                    Circle().fill(weight != nil ? (isSelected ? Color.white : Color.blue) : Color.clear).frame(width: 4, height: 4)
                    Circle().fill(hasEvent    ? (isSelected ? Color.white : Color.purple) : Color.clear).frame(width: 4, height: 4)
                    Circle().fill(isPeriod    ? (isSelected ? Color.white : Color.pink)   : Color.clear).frame(width: 4, height: 4)
                    Circle().fill(hasCountdown ? (isSelected ? Color.white : Color.orange) : Color.clear).frame(width: 4, height: 4)
                }
            }
        }
        .frame(height: 56).frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isPeriod && !isSelected ? Color.pink.opacity(0.15) : isSelected ? Color.green : calorieColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(anniversaryEmoji != nil && !isSelected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Period Summary Card (full original)

struct PeriodSummaryCard: View {
    @ObservedObject var healthKit: HealthKitManager
    let selectedDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🌸 Period Tracker").font(.headline)
                Spacer()
                if healthKit.isPeriodDate(selectedDate) {
                    Text("Period Day").font(.caption).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.pink).cornerRadius(8)
                }
            }
            if let last = healthKit.lastPeriodStart {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last period").font(.caption).foregroundColor(.secondary)
                        Text(last, style: .date).font(.subheadline).fontWeight(.medium)
                    }
                    Spacer()
                    if healthKit.periodCycleDays > 0 {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Avg cycle").font(.caption).foregroundColor(.secondary)
                            Text("\(healthKit.periodCycleDays) days").font(.subheadline).fontWeight(.medium)
                        }
                    }
                }
                if let next = healthKit.nextPeriodEstimate {
                    Divider()
                    HStack {
                        Image(systemName: "calendar.badge.clock").foregroundColor(.pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next estimated").font(.caption).foregroundColor(.secondary)
                            Text(next, style: .date).font(.subheadline).fontWeight(.medium).foregroundColor(.pink)
                        }
                        Spacer()
                        if let days = healthKit.daysUntilNextPeriod {
                            Text(days <= 0 ? "Today" : "in \(days)d")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(days <= 3 ? .pink : .secondary)
                        }
                    }
                }
            } else {
                Text("No period data found in Apple Health").font(.caption).foregroundColor(.secondary)
                Text("Log period data in the Health app to see it here").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding().background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Apple Event Row (original)

struct AppleEventRow: View {
    let event: EKEvent
    var timeString: String {
        if event.isAllDay { return "All day" }
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: event.startDate)
    }
    var calendarColor: Color {
        if let cgColor = event.calendar.cgColor { return Color(cgColor) }; return .purple
    }
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(calendarColor).frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "No title").font(.subheadline).fontWeight(.medium)
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "location").font(.caption2).foregroundColor(.secondary)
                }
                if let notes = event.notes, !notes.isEmpty {
                    Text(notes).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(timeString).font(.caption).foregroundColor(.secondary)
        }
        .padding().background(.regularMaterial).cornerRadius(12)
    }
}

// MARK: - Event Row (original custom event)

struct EventRow: View {
    let event: CalendarEvent; let onDelete: () -> Void
    var timeString: String { let f = DateFormatter(); f.timeStyle = .short; return f.string(from: event.date) }
    var body: some View {
        HStack(spacing: 12) {
            Text(event.emoji).font(.system(size: 28)).frame(width: 44, height: 44)
                .background(Color.purple.opacity(0.1)).cornerRadius(10)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                if !event.notes.isEmpty { Text(event.notes).font(.caption).foregroundColor(.secondary) }
                Label(event.reminderLabel, systemImage: "bell.fill").font(.caption2).foregroundColor(.purple)
            }
            Spacer()
            Text(timeString).font(.subheadline).foregroundColor(.secondary)
        }
        .padding().background(.regularMaterial).cornerRadius(12)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Add Event View (original)

struct AddEventView: View {
    @ObservedObject var eventStore: EventStore
    let date: Date
    @Environment(\.dismiss) var dismiss
    @State private var title = ""; @State private var notes = ""
    @State private var eventDate: Date; @State private var reminderMinutes = 15; @State private var emoji = "📅"
    let reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440]
    let reminderLabels  = ["At event time","5 min before","10 min before","15 min before",
                           "30 min before","1 hour before","2 hours before","1 day before"]
    let commonEmojis = ["📅","🏃","💊","🍽️","⚕️","🧘","🏋️","🥗","💉","🩺",
                        "🎂","🎯","📝","🏥","⏰","🔔","💪","🛒","🍎","🧪"]
    init(eventStore: EventStore, date: Date) {
        self.eventStore = eventStore; self.date = date; _eventDate = State(initialValue: date)
    }
    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonEmojis, id: \.self) { e in
                                Text(e).font(.system(size: 26)).padding(6)
                                    .background(emoji == e ? Color.purple.opacity(0.2) : Color.clear)
                                    .cornerRadius(8).onTapGesture { emoji = e }
                            }
                        }.padding(.vertical, 4)
                    }
                    TextField("Event title", text: $title)
                    TextField("Notes (optional)", text: $notes)
                }
                Section("Date & Time") { DatePicker("Event time", selection: $eventDate) }
                Section("Reminder") {
                    Picker("Remind me", selection: $reminderMinutes) {
                        ForEach(0..<reminderOptions.count, id: \.self) { i in
                            Text(reminderLabels[i]).tag(reminderOptions[i])
                        }
                    }.pickerStyle(.wheel).frame(height: 120)
                }
            }
            .navigationTitle("Add Event").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        guard !title.isEmpty else { return }
                        let event = CalendarEvent(title: title, notes: notes, date: eventDate,
                            emoji: emoji, reminderMinutes: reminderMinutes)
                        eventStore.addEvent(event); dismiss()
                    }.fontWeight(.bold).disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - Add / Edit Countdown View (NEW)

struct AddEditCountdownView: View {
    @ObservedObject var eventStore: EventStore
    @Environment(\.dismiss) var dismiss
    var existing: CalendarEvent?
    @State private var title = ""; @State private var notes = ""; @State private var emoji = "🎂"
    @State private var date = Date(); @State private var isAnniversary = false
    var isEditing: Bool { existing != nil }
    let commonEmojis = ["🎂","💕","🎉","✈️","🏠","💍","🎓","👶","🎄","🌸","❤️","🥂","🏆","🎵","🌍","💼","🏥","🎬","⭐","🌙","📅","🏃","💊","🍽️","🎯","🐱","🐶","🌈","🎮","📚"]
    var body: some View {
        NavigationView {
            Form {
                Section("Countdown Details") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonEmojis, id: \.self) { e in
                                Text(e).font(.system(size: 28)).padding(6)
                                    .background(emoji == e ? Color.blue.opacity(0.2) : Color.clear)
                                    .cornerRadius(8).onTapGesture { emoji = e }
                            }
                        }.padding(.vertical, 4)
                    }
                    TextField("Event name (e.g. Anniversary, Trip to Japan)", text: $title)
                    TextField("Notes (optional)", text: $notes)
                }
                Section("Date") {
                    DatePicker("Event Date", selection: $date, displayedComponents: .date)
                }
                Section {
                    Toggle("Repeats every year", isOn: $isAnniversary)
                    if isAnniversary {
                        Label("Counts down to next yearly occurrence", systemImage: "arrow.clockwise")
                            .font(.caption).foregroundColor(.blue)
                    }
                } header: { Text("Anniversary / Birthday") }
                Section("Preview") {
                    let preview = CalendarEvent(title: title.isEmpty ? "Your Event" : title,
                        notes: notes, date: date, emoji: emoji, isCountdown: true, isAnniversary: isAnniversary)
                    HStack(spacing: 12) {
                        Text(emoji).font(.system(size: 32)).frame(width: 48, height: 48)
                            .background(preview.urgencyColor.opacity(0.12)).cornerRadius(10)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title.isEmpty ? "Your Event" : title).font(.subheadline).fontWeight(.semibold)
                            Text("⏳ Countdown").font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(preview.countdownLabel).font(.title3).fontWeight(.bold).foregroundColor(preview.urgencyColor)
                    }
                }
                if isEditing, let existing = existing {
                    Section {
                        Button(role: .destructive) {
                            eventStore.deleteEvent(existing)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Delete Countdown", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Countdown" : "Add Countdown").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Add") {
                        guard !title.isEmpty else { return }
                        let event = CalendarEvent(id: existing?.id ?? UUID(), title: title, notes: notes,
                            date: date, emoji: emoji, reminderMinutes: 0,
                            isCountdown: true, isAnniversary: isAnniversary)
                        if isEditing { eventStore.updateEvent(event) } else { eventStore.addEvent(event) }
                        dismiss()
                    }.fontWeight(.bold).disabled(title.isEmpty)
                }
            }
            .onAppear {
                guard let e = existing else { return }
                title = e.title; notes = e.notes; emoji = e.emoji; date = e.date; isAnniversary = e.isAnniversary
            }
        }
    }
}

// MARK: - Countdown Bar (NEW - horizontal scroll chips)

struct CountdownBar: View {
    let events: [CalendarEvent]
    let onTap: (CalendarEvent) -> Void
    let onAdd: () -> Void

    var sortedEvents: [CalendarEvent] {
        events.sorted {
            if $0.isToday != $1.isToday { return $0.isToday }
            return $0.daysFromNow < $1.daysFromNow
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "timer").foregroundColor(.blue)
                Text("Countdowns").font(.headline)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill").foregroundColor(.blue).font(.title3)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedEvents) { event in
                        CountdownChip(event: event).onTapGesture { onTap(event) }
                    }
                }.padding(.vertical, 4)
            }
        }
        .padding().background(.regularMaterial).cornerRadius(16)
    }
}

struct CountdownChip: View {
    let event: CalendarEvent
    @State private var showingCountdown = true

    var yearsElapsed: Int {
        Calendar.current.dateComponents([.year],
            from: Calendar.current.startOfDay(for: event.date),
            to: Calendar.current.startOfDay(for: Date())).year ?? 0
    }
    var daysElapsed: Int {
        Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: event.date),
            to: Calendar.current.startOfDay(for: Date())).day ?? 0
    }
    var daysToNext: Int {
        guard event.isAnniversary else { return max(event.daysFromNow, 0) }
        let cal = Calendar.current
        let now = cal.startOfDay(for: Date())
        var comps = cal.dateComponents([.month, .day], from: event.date)
        comps.year = cal.component(.year, from: now)
        var next = cal.date(from: comps) ?? event.date
        if next <= now { comps.year! += 1; next = cal.date(from: comps) ?? event.date }
        return cal.dateComponents([.day], from: now, to: next).day ?? 0
    }

    var topLabel: String {
        if event.isToday { return "Today!" }
        if showingCountdown {
            if daysToNext == 1 { return "1 day" }
            return "\(daysToNext)d left"
        } else {
            if yearsElapsed > 0 {
                let rem = daysElapsed % 365
                return "\(yearsElapsed)y \(rem)d"
            }
            return "\(daysElapsed) days"
        }
    }

    var modeIcon: String { showingCountdown ? "⏳" : "💝" }

    var chipColor: Color {
        if event.isToday { return .orange }
        if showingCountdown {
            if daysToNext <= 7  { return .red }
            if daysToNext <= 30 { return .orange }
            return .blue
        }
        return .pink
    }

    var body: some View {
        VStack(spacing: 5) {
            // Emoji — clean, no overlay
            Text(event.emoji)
                .font(.system(size: 30))
                .frame(width: 54, height: 54)
                .background(chipColor.opacity(0.12))
                .cornerRadius(12)
                .overlay(
                    event.isToday
                        ? RoundedRectangle(cornerRadius: 12).stroke(chipColor, lineWidth: 2)
                        : nil
                )

            // Title
            Text(event.title)
                .font(.system(size: 10)).fontWeight(.medium)
                .lineLimit(1)
                .frame(width: 72)
                .multilineTextAlignment(.center)

            // Count label
            Text(topLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(chipColor)
                .animation(.spring(response: 0.3), value: showingCountdown)

            // Mode row — tap hint
            HStack(spacing: 3) {
                Text(modeIcon).font(.system(size: 9))
                Text(showingCountdown ? "to next" : "since")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 80)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 2)
        .onTapGesture {
            withAnimation(.spring(response: 0.35)) {
                showingCountdown.toggle()
            }
        }
    }
}

// MARK: - Celebration Banner Card

struct CelebrationBannerCard: View {
    let event: CalendarEvent
    var body: some View {
        HStack(spacing: 14) {
            Text(event.emoji).font(.system(size: 36))
            VStack(alignment: .leading, spacing: 4) {
                Text("🎉 Today!").font(.caption).foregroundColor(.orange).fontWeight(.semibold)
                Text(event.title).font(.subheadline).fontWeight(.bold)
                if let years = event.anniversaryYears, years > 0 {
                    Text("\(years) year\(years == 1 ? "" : "s") 💕").font(.caption2).foregroundColor(.pink)
                }
            }
            Spacer()
            Text("Tap to celebrate 🎊").font(.caption2).foregroundColor(.secondary)
        }
        .padding(12)
        .background(LinearGradient(colors: [Color.orange.opacity(0.15), Color.pink.opacity(0.1)], startPoint: .leading, endPoint: .trailing))
        .cornerRadius(14).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Celebration Full Screen

struct CelebrationFullScreen: View {
    let event: CalendarEvent; let onDismiss: () -> Void
    @State private var particles: [ConfettiParticle] = []
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.pink.opacity(0.3), Color.orange.opacity(0.2), Color.purple.opacity(0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ForEach(particles) { p in
                Text(p.emoji).font(.system(size: p.size)).position(p.position).opacity(p.opacity).rotationEffect(.degrees(p.rotation))
            }
            VStack(spacing: 30) {
                Spacer()
                Text(event.emoji).font(.system(size: 100))
                VStack(spacing: 12) {
                    Text("🎉 Celebration! 🎉").font(.title).fontWeight(.bold)
                    Text(event.title).font(.title2).fontWeight(.semibold).multilineTextAlignment(.center)
                    if let years = event.anniversaryYears, years > 0 {
                        Text("\(years) Year\(years == 1 ? "" : "s")!").font(.system(size: 48, weight: .bold)).foregroundColor(.orange)
                    } else {
                        Text("Today is the day!").font(.title3).foregroundColor(.orange)
                        if !event.notes.isEmpty { Text(event.notes).font(.subheadline).foregroundColor(.secondary) }
                    }
                }.padding().background(.regularMaterial).cornerRadius(24).padding(.horizontal)
                Spacer()
                Button(action: onDismiss) {
                    Text("Done 🎊").font(.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding().background(Color.pink).cornerRadius(16).padding(.horizontal)
                }.padding(.bottom, 40)
            }
        }
        .onAppear {
            let emojis = ["🎉","🎊","✨","💕","🌸","⭐","🎈","💫","🌟","❤️"]
            let w = UIScreen.main.bounds.width; let h = UIScreen.main.bounds.height
            particles = (0..<40).map { _ in
                ConfettiParticle(emoji: emojis.randomElement()!,
                    position: CGPoint(x: CGFloat.random(in: 0...w), y: CGFloat.random(in: 0...h)),
                    size: CGFloat.random(in: 20...50), opacity: Double.random(in: 0.6...1.0), rotation: Double.random(in: 0...360))
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID(); let emoji: String; let position: CGPoint
    let size: CGFloat; let opacity: Double; let rotation: Double
}

// MARK: - Day Summary Card (original)

struct DaySummaryCard: View {
    let log: DayLog; let date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Health").font(.headline); Spacer() }
            HStack(spacing: 16) {
                CalNutritionBadge(label: "Calories", value: "\(log.calories)", unit: "kcal", color: .red)
                CalNutritionBadge(label: "Carbs",    value: "\(Int(log.carbs))",    unit: "g", color: .orange)
                CalNutritionBadge(label: "Protein",  value: "\(Int(log.protein))",  unit: "g", color: .green)
                CalNutritionBadge(label: "Fat",      value: "\(Int(log.fat))",      unit: "g", color: .blue)
            }
            ProgressView(value: min(Double(log.calories), 2000), total: 2000)
                .tint(log.calories > 2000 ? .red : .green)
        }.padding().background(.regularMaterial).cornerRadius(16)
    }
}

struct CalNutritionBadge: View {
    let label: String; let value: String; let unit: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(color)
            Text(unit).font(.caption2).foregroundColor(.secondary)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct EmptyDayCard: View {
    let date: Date
    var body: some View {
        VStack(spacing: 8) {
            Text("No health data logged").font(.subheadline).foregroundColor(.secondary)
            Text("Tap + to log calories or macros").font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity).padding().background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Day Detail View (original log form)

struct DayDetailView: View {
    let date: Date; @ObservedObject var store: CalendarStore
    @Environment(\.dismiss) var dismiss
    @State private var calories = ""; @State private var carbs = ""
    @State private var protein = ""; @State private var fat = ""
    var body: some View {
        NavigationView {
            Form {
                Section("🔥 Calories") {
                    HStack { TextField("e.g. 1800", text: $calories).keyboardType(.numberPad); Text("kcal").foregroundColor(.secondary) }
                }
                Section("🥗 Macros") {
                    HStack { Text("Carbs").frame(width: 70, alignment: .leading); TextField("g", text: $carbs).keyboardType(.decimalPad); Text("g").foregroundColor(.secondary) }
                    HStack { Text("Protein").frame(width: 70, alignment: .leading); TextField("g", text: $protein).keyboardType(.decimalPad); Text("g").foregroundColor(.secondary) }
                    HStack { Text("Fat").frame(width: 70, alignment: .leading); TextField("g", text: $fat).keyboardType(.decimalPad); Text("g").foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Log Calories/Macros").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveLog(); dismiss() }.fontWeight(.bold)
                }
            }
            .onAppear { loadExisting() }
        }
    }
    func loadExisting() {
        if let log = store.logForDate(date) {
            calories = "\(log.calories)"; carbs = "\(Int(log.carbs))"
            protein = "\(Int(log.protein))"; fat = "\(Int(log.fat))"
        }
    }
    func saveLog() {
        var log = store.logForDate(date) ?? DayLog(date: date, calories: 0, carbs: 0, protein: 0, fat: 0)
        if let c = Int(calories)    { log.calories = c }
        if let c = Double(carbs)    { log.carbs = c }
        if let p = Double(protein)  { log.protein = p }
        if let f = Double(fat)      { log.fat = f }
        store.saveLog(log)
    }
}

// MARK: - Anniversary Day Card

struct AnniversaryDayCard: View {
    let event: CalendarEvent
    let selectedDate: Date

    var yearsOnDate: Int {
        Calendar.current.dateComponents([.year],
            from: Calendar.current.startOfDay(for: event.date),
            to: Calendar.current.startOfDay(for: selectedDate)).year ?? 0
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(event.emoji).font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(Color.orange.opacity(0.12)).cornerRadius(10)
            VStack(alignment: .leading, spacing: 3) {
                if yearsOnDate > 0 {
                    Text("Today is \(event.title) — \(yearsOnDate) Year\(yearsOnDate == 1 ? "" : "s")! 🎉")
                        .font(.subheadline).fontWeight(.bold).foregroundColor(.orange)
                    Text("That's \(yearsOnDate * 365) days")
                        .font(.caption2).foregroundColor(.secondary)
                } else {
                    Text("Today is \(event.title)! 🎉")
                        .font(.subheadline).fontWeight(.bold).foregroundColor(.orange)
                }
                if !event.notes.isEmpty {
                    Text(event.notes).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            if yearsOnDate > 0 {
                VStack(spacing: 2) {
                    Text("Year").font(.caption2).foregroundColor(.secondary)
                    Text("\(yearsOnDate)").font(.title3).fontWeight(.bold).foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .background(LinearGradient(colors: [Color.orange.opacity(0.12), Color.pink.opacity(0.08)],
                                   startPoint: .leading, endPoint: .trailing))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Weight Trend Card

struct WeightTrendCard: View {
    @ObservedObject var store: CalendarStore
    var last14Days: [(date: Date, entries: [WeightEntry])] {
        (0..<14).compactMap { offset -> (Date, [WeightEntry])? in
            let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let e = store.weightEntriesForDate(d); return e.isEmpty ? nil : (d, e)
        }.reversed()
    }
    var trendPoints: [(date: Date, weight: Double)] {
        last14Days.compactMap { day in
            guard let w = day.entries.sorted(by: { $0.time > $1.time }).first?.weight else { return nil }
            return (day.date, w)
        }
    }
    var minW: Double { trendPoints.map { $0.weight }.min() ?? 60 }
    var maxW: Double { trendPoints.map { $0.weight }.max() ?? 80 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weight Trend (14 days)").font(.headline)
                Spacer()
                if let latest = trendPoints.last {
                    Text(String(format: "%.1f kg", latest.weight)).font(.subheadline).fontWeight(.semibold).foregroundColor(.blue)
                }
            }
            if trendPoints.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 36)).foregroundColor(.secondary.opacity(0.4))
                    Text("No weight data yet").font(.subheadline).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width; let h = geo.size.height
                    let range = max(maxW - minW, 1.0); let pad = 2.0
                    ZStack {
                        ForEach(0..<4) { i in
                            Path { p in let y = h * CGFloat(i) / 3; p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        }
                        if trendPoints.count > 1 {
                            Path { p in
                                for (i, pt) in trendPoints.enumerated() {
                                    let x = w * CGFloat(i) / CGFloat(trendPoints.count - 1)
                                    let n = (pt.weight - minW + pad) / (range + pad * 2)
                                    let y = h * CGFloat(1 - n)
                                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                                }
                            }.stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                        ForEach(0..<trendPoints.count, id: \.self) { i in
                            let pt = trendPoints[i]
                            let x = trendPoints.count == 1 ? w / 2 : w * CGFloat(i) / CGFloat(trendPoints.count - 1)
                            let n = (pt.weight - minW + pad) / (range + pad * 2)
                            let y = h * CGFloat(1 - n)
                            Circle().fill(Color.blue).frame(width: 8, height: 8).position(x: x, y: y)
                            Text(String(format: "%.1f", pt.weight)).font(.system(size: 8)).foregroundColor(.blue).position(x: x, y: max(y - 12, 8))
                        }
                    }
                }.frame(height: 120)
                if trendPoints.count >= 2 {
                    let diff = trendPoints.last!.weight - trendPoints.first!.weight
                    HStack(spacing: 6) {
                        Image(systemName: diff < 0 ? "arrow.down.circle.fill" : diff > 0 ? "arrow.up.circle.fill" : "minus.circle.fill")
                            .foregroundColor(diff < 0 ? .green : diff > 0 ? .red : .secondary)
                        Text(diff == 0 ? "Stable" : String(format: "%.1f kg in 14 days", abs(diff)))
                            .font(.caption).foregroundColor(diff < 0 ? .green : diff > 0 ? .red : .secondary)
                    }
                }
            }
        }.padding().background(.regularMaterial).cornerRadius(16)
    }
}
