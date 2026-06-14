import SwiftUI
import Combine
import EventKit

// MARK: - Data Models

struct CalendarDay: Identifiable {
    let id: String
    let date: Date?
}

struct DayLog: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var calories: Int
    var carbs: Double
    var protein: Double
    var fat: Double
    var weight: Double?

    var dateKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Calendar Store

class CalendarStore: ObservableObject {
    @Published var logs: [String: DayLog] = [:]

    init() { load() }

    func save() {
        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: "calendarLogs")
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: "calendarLogs"),
           let decoded = try? JSONDecoder().decode([String: DayLog].self, from: data) {
            self.logs = decoded
        }
    }

    func logForDate(_ date: Date) -> DayLog? { logs[dateKey(date)] }

    func saveLog(_ log: DayLog) {
        logs[log.dateKey] = log
        save()
    }

    func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func caloriesForDate(_ date: Date) -> Int {
        logs[dateKey(date)]?.calories ?? 0
    }

    func weightForDate(_ date: Date) -> Double? {
        logs[dateKey(date)]?.weight
    }
}

// MARK: - Calendar View

struct CalendarView: View {
    @StateObject private var store = CalendarStore()
    @StateObject private var eventStore = EventStore()
    @StateObject private var healthKit = HealthKitManager()
    @State private var selectedDate = Date()
    @State private var showDayDetail = false
    @State private var showAddEvent = false
    @State private var currentMonth = Date()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // Month navigation
                    HStack {
                        Button(action: previousMonth) {
                            Image(systemName: "chevron.left")
                                .font(.title3).foregroundColor(.green)
                        }
                        Spacer()
                        Text(monthTitle).font(.title2).fontWeight(.semibold)
                        Spacer()
                        Button(action: nextMonth) {
                            Image(systemName: "chevron.right")
                                .font(.title3).foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal).padding(.top, 8)

                    // Day headers
                    HStack(spacing: 0) {
                        ForEach(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"], id: \.self) { day in
                            Text(day).font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)

                    // Calendar grid
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                        spacing: 4
                    ) {
                        ForEach(calendarDays) { day in
                            if let date = day.date {
                                DayCell(
                                    date: date,
                                    isSelected: isSameDay(date, selectedDate),
                                    isToday: isSameDay(date, Date()),
                                    calories: store.caloriesForDate(date),
                                    weight: store.weightForDate(date),
                                    hasEvent: !eventStore.eventsForDate(date).isEmpty ||
                                              !eventStore.appleEventsForDate(date).isEmpty,
                                    isPeriod: healthKit.isPeriodDate(date)
                                )
                                .onTapGesture { selectedDate = date }
                            } else {
                                Color.clear.frame(height: 56)
                            }
                        }
                    }
                    .padding(.horizontal, 8)

                    // Dot legend
                    HStack(spacing: 16) {
                        LegendDot(color: .blue, label: "Weight")
                        LegendDot(color: .purple, label: "Event")
                        LegendDot(color: .pink, label: "Period")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    // Selected date header
                    HStack {
                        Text(formattedSelectedDate).font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal)

                    // Health summary
                    if let log = store.logForDate(selectedDate) {
                        DaySummaryCard(log: log, date: selectedDate).padding(.horizontal)
                    } else {
                        EmptyDayCard(date: selectedDate).padding(.horizontal)
                    }

                    // Period info
                    if healthKit.isAuthorized {
                        PeriodSummaryCard(healthKit: healthKit, selectedDate: selectedDate)
                            .padding(.horizontal)
                    }

                    // Events
                    let dayEvents = eventStore.eventsForDate(selectedDate)
                    let appleEvents = eventStore.appleEventsForDate(selectedDate)

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
                        }
                        .padding(.horizontal)

                        if let error = eventStore.calendarError {
                            Text(error).font(.caption).foregroundColor(.red).padding(.horizontal)
                        }

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

                        if dayEvents.isEmpty && appleEvents.isEmpty {
                            Text("No events")
                                .font(.subheadline).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity).padding()
                                .background(.regularMaterial).cornerRadius(12).padding(.horizontal)
                        }
                    }

                    // Weight trend
                    WeightTrendCard(store: store).padding(.horizontal).padding(.bottom, 24)
                }
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showDayDetail = true }) {
                            Label("Log Health Data", systemImage: "heart.text.square")
                        }
                        Button(action: { showAddEvent = true }) {
                            Label("Add Event", systemImage: "calendar.badge.plus")
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showDayDetail) { DayDetailView(date: selectedDate, store: store) }
            .sheet(isPresented: $showAddEvent) { AddEventView(eventStore: eventStore, date: selectedDate) }
            .onAppear {
                if !healthKit.isAuthorized { healthKit.requestAuthorization() }
            }
        }
    }

    var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: currentMonth)
    }

    var formattedSelectedDate: String {
        let f = DateFormatter(); f.dateStyle = .full; return f.string(from: selectedDate)
    }

    func previousMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }

    func nextMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
    }

    func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }

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

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let calories: Int
    let weight: Double?
    let hasEvent: Bool
    let isPeriod: Bool

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
                Text("\(calories)").font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            } else {
                Text(" ").font(.system(size: 9))
            }

            HStack(spacing: 3) {
                Circle()
                    .fill(weight != nil ? (isSelected ? Color.white : Color.blue) : Color.clear)
                    .frame(width: 4, height: 4)
                Circle()
                    .fill(hasEvent ? (isSelected ? Color.white : Color.purple) : Color.clear)
                    .frame(width: 4, height: 4)
                Circle()
                    .fill(isPeriod ? (isSelected ? Color.white : Color.pink) : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(height: 56).frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isPeriod && !isSelected
                      ? Color.pink.opacity(0.15)
                      : isSelected ? Color.green : calorieColor)
        )
    }
}

// MARK: - Period Summary Card

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
                Text("No period data found in Apple Health")
                    .font(.caption).foregroundColor(.secondary)
                Text("Log period data in the Health app to see it here")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding().background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Apple Event Row

struct AppleEventRow: View {
    let event: EKEvent

    var timeString: String {
        if event.isAllDay { return "All day" }
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: event.startDate)
    }

    var calendarColor: Color {
        if let cgColor = event.calendar.cgColor { return Color(cgColor) }
        return .purple
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

// MARK: - Event Row

struct EventRow: View {
    let event: CalendarEvent; let onDelete: () -> Void

    var timeString: String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: event.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(event.emoji).font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(Color.purple.opacity(0.1)).cornerRadius(10)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                if !event.notes.isEmpty {
                    Text(event.notes).font(.caption).foregroundColor(.secondary)
                }
                Label(event.reminderLabel, systemImage: "bell.fill")
                    .font(.caption2).foregroundColor(.purple)
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

// MARK: - Add Event View

struct AddEventView: View {
    @ObservedObject var eventStore: EventStore
    let date: Date
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var eventDate: Date
    @State private var reminderMinutes = 15
    @State private var emoji = "📅"

    let reminderOptions = [0, 5, 10, 15, 30, 60, 120, 1440]
    let reminderLabels = ["At event time","5 min before","10 min before","15 min before",
                          "30 min before","1 hour before","2 hours before","1 day before"]
    let commonEmojis = ["📅","🏃","💊","🍽️","⚕️","🧘","🏋️","🥗","💉","🩺",
                        "🎂","🎯","📝","🏥","⏰","🔔","💪","🛒","🍎","🧪"]

    init(eventStore: EventStore, date: Date) {
        self.eventStore = eventStore
        self.date = date
        _eventDate = State(initialValue: date)
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
                Section("Date & Time") {
                    DatePicker("Event time", selection: $eventDate)
                }
                Section("Reminder") {
                    Picker("Remind me", selection: $reminderMinutes) {
                        ForEach(0..<reminderOptions.count, id: \.self) { i in
                            Text(reminderLabels[i]).tag(reminderOptions[i])
                        }
                    }
                    .pickerStyle(.wheel).frame(height: 120)
                }
            }
            .navigationTitle("Add Event").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        guard !title.isEmpty else { return }
                        let event = CalendarEvent(title: title, notes: notes, date: eventDate, reminderMinutes: reminderMinutes, emoji: emoji)
                        eventStore.addEvent(event)
                        dismiss()
                    }.fontWeight(.bold).disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - Day Summary Card

struct DaySummaryCard: View {
    let log: DayLog; let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Health").font(.headline)
                Spacer()
                if let w = log.weight {
                    Label(String(format: "%.1f kg", w), systemImage: "scalemass")
                        .font(.subheadline).foregroundColor(.blue)
                }
            }
            HStack(spacing: 16) {
                NutritionBadge(label: "Calories", value: "\(log.calories)", unit: "kcal", color: .red)
                NutritionBadge(label: "Carbs", value: "\(Int(log.carbs))", unit: "g", color: .orange)
                NutritionBadge(label: "Protein", value: "\(Int(log.protein))", unit: "g", color: .green)
                NutritionBadge(label: "Fat", value: "\(Int(log.fat))", unit: "g", color: .blue)
            }
            ProgressView(value: min(Double(log.calories), 2000), total: 2000)
                .tint(log.calories > 2000 ? .red : .green)
        }
        .padding().background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Empty Day Card

struct EmptyDayCard: View {
    let date: Date
    var body: some View {
        VStack(spacing: 8) {
            Text("No health data logged").font(.subheadline).foregroundColor(.secondary)
            Text("Tap + to log weight or calories").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding()
        .background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Weight Trend Card

struct WeightTrendCard: View {
    @ObservedObject var store: CalendarStore

    var last14Days: [(date: Date, weight: Double)] {
        (0..<14).compactMap { offset -> (Date, Double)? in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            if let w = store.weightForDate(date) { return (date, w) }
            return nil
        }.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight Trend (14 days)").font(.headline)

            if last14Days.isEmpty {
                Text("Log your weight by tapping + on any day")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding()
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(last14Days, id: \.date) { entry in
                        VStack(spacing: 4) {
                            Text(String(format: "%.0f", entry.weight)).font(.system(size: 8)).foregroundColor(.secondary)
                            RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.7))
                                .frame(width: 18, height: barHeight(entry.weight))
                            Text(dayLabel(entry.date)).font(.system(size: 8)).foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        }
        .padding().background(.regularMaterial).cornerRadius(16)
    }

    func barHeight(_ weight: Double) -> CGFloat {
        let weights = last14Days.map { $0.weight }
        guard let min = weights.min(), let max = weights.max(), max != min else { return 60 }
        return CGFloat(((weight - min) / (max - min)) * 60 + 20)
    }

    func dayLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
    }
}

// MARK: - Day Detail View

struct DayDetailView: View {
    let date: Date
    @ObservedObject var store: CalendarStore
    @Environment(\.dismiss) var dismiss

    @State private var calories = ""
    @State private var carbs = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var weight = ""

    var body: some View {
        NavigationView {
            Form {
                Section("⚖️ Weight") {
                    HStack {
                        TextField("e.g. 68.5", text: $weight).keyboardType(.decimalPad)
                        Text("kg").foregroundColor(.secondary)
                    }
                }
                Section("🔥 Calories") {
                    HStack {
                        TextField("e.g. 1800", text: $calories).keyboardType(.numberPad)
                        Text("kcal").foregroundColor(.secondary)
                    }
                }
                Section("🥗 Macros") {
                    HStack {
                        Text("Carbs").frame(width: 70, alignment: .leading)
                        TextField("g", text: $carbs).keyboardType(.decimalPad)
                        Text("g").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Protein").frame(width: 70, alignment: .leading)
                        TextField("g", text: $protein).keyboardType(.decimalPad)
                        Text("g").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Fat").frame(width: 70, alignment: .leading)
                        TextField("g", text: $fat).keyboardType(.decimalPad)
                        Text("g").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Log Health Data").navigationBarTitleDisplayMode(.inline)
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
            if let w = log.weight { weight = String(format: "%.1f", w) }
        }
    }

    func saveLog() {
        let key = store.dateKey(date)
        var log = store.logs[key] ?? DayLog(date: date, calories: 0, carbs: 0, protein: 0, fat: 0)
        if let c = Int(calories) { log.calories = c }
        if let c = Double(carbs) { log.carbs = c }
        if let p = Double(protein) { log.protein = p }
        if let f = Double(fat) { log.fat = f }
        if let w = Double(weight) { log.weight = w }
        store.saveLog(log)
    }
}
