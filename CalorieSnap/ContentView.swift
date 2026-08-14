import SwiftUI
import Combine

// MARK: - To-Do Models

enum TodoPriority: String, Codable, CaseIterable {
    case low = "Low"; case medium = "Medium"; case high = "High"
    var color: Color {
        switch self { case .low: return .blue; case .medium: return .orange; case .high: return .red }
    }
    var icon: String {
        switch self { case .low: return "circle"; case .medium: return "circle.fill"; case .high: return "exclamationmark.circle.fill" }
    }
}

struct TodoItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var note: String
    var isDone: Bool
    var priority: TodoPriority
    var dueDate: Date?
    var hasDueDate: Bool
    var createdAt: Date
    var completedAt: Date?
    var emoji: String

    init(id: UUID = UUID(), title: String, note: String = "", isDone: Bool = false,
         priority: TodoPriority = .medium, dueDate: Date? = nil,
         hasDueDate: Bool = false, emoji: String = "✅") {
        self.id = id; self.title = title; self.note = note; self.isDone = isDone
        self.priority = priority; self.dueDate = dueDate; self.hasDueDate = hasDueDate
        self.createdAt = Date(); self.emoji = emoji
    }

    var isOverdue: Bool {
        guard hasDueDate, let due = dueDate, !isDone else { return false }
        return due < Date()
    }
    var dueDateLabel: String {
        guard hasDueDate, let due = dueDate else { return "" }
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: due)).day ?? 0
        if days < 0 { return "Overdue \(-days)d" }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days)d"
    }
}

class TodoStore: ObservableObject {
    @Published var todos: [TodoItem] = [] { didSet { save() } }
    init() { load() }
    func save() {
        if let d = try? JSONEncoder().encode(todos) { UserDefaults.standard.set(d, forKey: "todoItems_v2") }
    }
    func load() {
        guard let d = UserDefaults.standard.data(forKey: "todoItems_v2"),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: d) else { return }
        todos = decoded
    }
    func toggle(_ item: TodoItem) {
        if let i = todos.firstIndex(where: { $0.id == item.id }) {
            todos[i].isDone.toggle()
            todos[i].completedAt = todos[i].isDone ? Date() : nil
        }
    }
    var pending: [TodoItem] {
        todos.filter { !$0.isDone }.sorted {
            let order: [TodoPriority] = [.high, .medium, .low]
            if $0.priority != $1.priority {
                return (order.firstIndex(of: $0.priority) ?? 0) < (order.firstIndex(of: $1.priority) ?? 0)
            }
            return $0.createdAt < $1.createdAt
        }
    }
    var completed: [TodoItem] { todos.filter { $0.isDone }.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) } }
    var progress: Double {
        guard !todos.isEmpty else { return 0 }
        return Double(todos.filter { $0.isDone }.count) / Double(todos.count)
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var financeStore = FinanceStore()
    @StateObject private var calendarStore = CalendarStore()
    @StateObject private var todoStore = TodoStore()
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: DashboardView(financeStore: financeStore, calendarStore: calendarStore, todoStore: todoStore)
                case 1: FridgeView()
                case 2: CalendarView(store: calendarStore)
                case 3: FinanceView(store: financeStore)
                case 4: ProfileView()
                default: DashboardView(financeStore: financeStore, calendarStore: calendarStore, todoStore: todoStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 60)

            HStack(spacing: 0) {
                CustomTabItem(icon: "flame.fill",        label: "Today",    tag: 0, selected: $selectedTab)
                CustomTabItem(icon: "refrigerator",      label: "Fridge",   tag: 1, selected: $selectedTab)
                CustomTabItem(icon: "calendar",          label: "Calendar", tag: 2, selected: $selectedTab)
                CustomTabItem(icon: "dollarsign.circle", label: "Finance",  tag: 3, selected: $selectedTab)
                CustomTabItem(icon: "person.circle",     label: "Profile",  tag: 4, selected: $selectedTab)
            }
            .padding(.horizontal, 4).padding(.vertical, 8)
            .background(.regularMaterial)
            .overlay(Divider(), alignment: .top)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

struct CustomTabItem: View {
    let icon: String; let label: String; let tag: Int; @Binding var selected: Int
    var isSelected: Bool { selected == tag }
    var body: some View {
        Button(action: { selected = tag }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(isSelected ? .green : Color(.systemGray))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .green : Color(.systemGray))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var financeStore: FinanceStore
    @ObservedObject var calendarStore: CalendarStore
    @ObservedObject var todoStore: TodoStore

    @AppStorage("totalCalories") var totalCalories: Int = 0
    @AppStorage("totalCarbs") var totalCarbs: Double = 0
    @AppStorage("totalProtein") var totalProtein: Double = 0
    @AppStorage("totalFat") var totalFat: Double = 0
    @StateObject private var profile = UserProfile()
    @StateObject private var healthKit = HealthKitManager()

    @State private var recentMeals: [ManualMeal] = ManualMeal.loadAll()
    @State private var weightLogs: [WeightLog] = WeightLog.loadAll()
    @State private var showingWeightLogSheet = false
    @State private var selectedWeightLog: WeightLog? = nil
    @State private var showingQuickLogOptions = false
    @State private var showingAddTransactionSheet = false
    @State private var dragOffset: CGFloat = 0
    @State private var showingLogPanel = false
    @State private var showAddTodo = false
    @State private var editingTodo: TodoItem? = nil
    @State private var showCompletedTodos = false
    @State private var showingCelebration = false
    @State private var celebrationTitle = ""
    @State private var celebrationEmoji = "🎉"
    @State private var celebrationYears = 0

    var goal: Double { Double(profile.dailyCalorieGoal) }
    var adjustedGoal: Int {
        let active = healthKit.isAuthorized ? Int(healthKit.activeCalories) : 0
        return Int(goal) + active
    }
    var recentWeightLogs: [WeightLog] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return weightLogs.filter { $0.date >= start }.sorted { $0.date < $1.date }
    }
    var groupedRecentWeightLogs: [(date: Date, logs: [WeightLog])] {
        let groups = Dictionary(grouping: recentWeightLogs) { Calendar.current.startOfDay(for: $0.date) }
        return groups.map { (date: $0.key, logs: $0.value.sorted { $0.date < $1.date }) }.sorted { $0.date < $1.date }
    }
    var latestWeightLog: WeightLog? { weightLogs.sorted { $0.date > $1.date }.first }
    var screenWidth: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 390
    }
    var upcomingEvents: [CalendarEvent] { [] }

    var todayAnniversaries: [CalendarEvent] {
        // Read countdown events from UserDefaults directly
        guard let d = UserDefaults.standard.data(forKey: "calendarEvents_v2"),
              let events = try? JSONDecoder().decode([CalendarEvent].self, from: d)
        else { return [] }
        return events.filter { $0.isCountdown && $0.isToday }
    }
    var remainingCalories: Int { adjustedGoal - totalCalories }
    var remainingText: String {
        if remainingCalories > 0 { return "\(remainingCalories) kcal left" }
        if remainingCalories == 0 { return "Goal reached! 🎯" }
        return "\(abs(remainingCalories)) kcal over"
    }
    var ringColor: Color { totalCalories > adjustedGoal ? .red : .green }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {

                        // Calorie ring
                        ZStack {
                            Circle().stroke(Color.green.opacity(0.15), lineWidth: 16).frame(width: 180, height: 180)
                            Circle()
                                .trim(from: 0, to: min(CGFloat(totalCalories) / CGFloat(max(adjustedGoal, 1)), 1.0))
                                .stroke(ringColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                .frame(width: 180, height: 180).rotationEffect(.degrees(-90))
                                .animation(.easeInOut, value: totalCalories)
                            VStack(spacing: 4) {
                                Text("\(totalCalories)").font(.system(size: 34, weight: .bold))
                                    .foregroundColor(totalCalories > adjustedGoal ? .red : .primary)
                                if healthKit.isAuthorized && healthKit.activeCalories > 0 {
                                    HStack(spacing: 4) {
                                        Text("\(Int(goal))").font(.caption2).foregroundColor(.secondary)
                                        Text("+").font(.caption2).foregroundColor(.secondary)
                                        Text("\(Int(healthKit.activeCalories))🔥").font(.caption2).foregroundColor(.orange)
                                    }
                                    Text("= \(adjustedGoal) kcal").font(.caption).foregroundColor(.green)
                                } else {
                                    Text("of \(Int(goal)) kcal").font(.caption).foregroundColor(.secondary)
                                }
                                Text(remainingText).font(.caption2)
                                    .foregroundColor(remainingCalories < 0 ? .red : .green).fontWeight(.medium)
                            }
                        }.padding(.top, 8)
                        
                        // Anniversary celebrations
                        if !todayAnniversaries.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(todayAnniversaries) { event in
                                    Button(action: {
                                        celebrationTitle = event.title
                                        celebrationEmoji = event.emoji
                                        celebrationYears = event.anniversaryYears ?? 0
                                        showingCelebration = true
                                    }) {
                                        HStack(spacing: 14) {
                                            Text(event.emoji)
                                                .font(.system(size: 36))
                                                .scaleEffect(1.0)
                                                .animation(
                                                    Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                                                )
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("🎉 Special Day Today!")
                                                    .font(.caption).fontWeight(.semibold).foregroundColor(.orange)
                                                Text(event.title).font(.subheadline).fontWeight(.bold)
                                                if let years = event.anniversaryYears, years > 0 {
                                                    Text("\(years) year\(years == 1 ? "" : "s") 💕")
                                                        .font(.caption2).foregroundColor(.pink)
                                                }
                                            }
                                            Spacer()
                                            VStack(spacing: 4) {
                                                Image(systemName: "party.popper.fill")
                                                    .foregroundColor(.orange).font(.title2)
                                                Text("Celebrate!").font(.caption2).foregroundColor(.orange)
                                            }
                                        }
                                        .padding(14)
                                        .background(
                                            LinearGradient(
                                                colors: [Color.orange.opacity(0.15), Color.pink.opacity(0.12)],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }

                        // Exercise bonus
                        if healthKit.isAuthorized && healthKit.activeCalories > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: "flame.fill").foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Exercise bonus: +\(Int(healthKit.activeCalories)) kcal").font(.caption).fontWeight(.semibold)
                                    Text("Goal increased from \(Int(goal)) to \(adjustedGoal) kcal").font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                            }
                            .padding(10).background(Color.orange.opacity(0.08)).cornerRadius(12).padding(.horizontal)
                        }

                        // Macro cards
                        HStack(spacing: 12) {
                            MacroCard(label: "Carbs",   value: "\(Int(totalCarbs))g",   color: .orange)
                            MacroCard(label: "Protein", value: "\(Int(totalProtein))g", color: .green)
                            MacroCard(label: "Fat",     value: "\(Int(totalFat))g",     color: .blue)
                        }.padding(.horizontal)

                        // Today's meals
                        let todayMeals = recentMeals.filter { Calendar.current.isDateInToday($0.date) }
                        if !todayMeals.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Today's Meals").font(.headline)
                                    Spacer()
                                    Text("\(todayMeals.count) meals").font(.caption).foregroundColor(.secondary)
                                }
                                ForEach(todayMeals) { meal in
                                    HStack(spacing: 10) {
                                        Text(meal.emoji).font(.system(size: 22))
                                            .frame(width: 36, height: 36).background(Color.green.opacity(0.1)).cornerRadius(8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(meal.name).font(.subheadline).fontWeight(.medium)
                                            Text("\(meal.mealType.emoji) \(meal.mealType.rawValue)").font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("\(meal.calories) kcal").font(.subheadline).fontWeight(.semibold).foregroundColor(.green)
                                    }
                                }
                            }
                            .padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)
                        }

                        // To-Do section
                        TodoDashboardSection(store: todoStore, showAddTodo: $showAddTodo, editingTodo: $editingTodo, showCompleted: $showCompletedTodos)
                            .padding(.horizontal)

                        // Upcoming events
                        if !upcomingEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "calendar").foregroundColor(.purple)
                                    Text("Upcoming Events").font(.headline)
                                    Spacer()
                                }
                                ForEach(upcomingEvents) { event in
                                    HStack(spacing: 10) {
                                        Text(event.emoji).font(.system(size: 20))
                                            .frame(width: 34, height: 34).background(Color.purple.opacity(0.1)).cornerRadius(8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.title).font(.subheadline).fontWeight(.medium)
                                            Text(relativeDate(event.date)).font(.caption2).foregroundColor(.purple)
                                        }
                                        Spacer()
                                        Text(timeString(event.date)).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)
                        }

                        // Finance summary
                        MonthFinanceSummary(store: financeStore).padding(.horizontal)

                        // Weight trend — week/month/year with comparisons
                        WeightTrendDashboard().padding(.horizontal)

                        // Apple Health
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "heart.fill").foregroundColor(.red)
                                Text("Apple Health").font(.headline)
                                Spacer()
                                if !healthKit.isAuthorized {
                                    Button("Connect") { healthKit.requestAuthorization() }
                                        .font(.subheadline).foregroundColor(.white)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.red).cornerRadius(10)
                                } else {
                                    Button(action: { healthKit.fetchAll() }) {
                                        Image(systemName: "arrow.clockwise").foregroundColor(.secondary)
                                    }
                                }
                            }
                            if let error = healthKit.errorMessage { Text(error).font(.caption).foregroundColor(.red) }
                            if healthKit.isAuthorized {
                                VStack(spacing: 6) {
                                    HStack {
                                        Label("\(healthKit.steps) steps", systemImage: "figure.walk").font(.subheadline)
                                            .foregroundColor(healthKit.stepsGoalMet ? .green : .primary)
                                        Spacer()
                                        Text(String(format: "%.2f km", healthKit.distanceKm)).font(.caption).foregroundColor(.secondary)
                                        Text(healthKit.stepsGoalMet ? "✅" : "/ 10,000").font(.caption).foregroundColor(.secondary)
                                    }
                                    ProgressView(value: healthKit.stepsProgress).tint(healthKit.stepsGoalMet ? .green : .orange)
                                }
                                Divider()
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Calorie Budget Today").font(.caption).foregroundColor(.secondary)
                                        HStack(spacing: 4) {
                                            Text("\(Int(goal))").font(.subheadline).fontWeight(.semibold)
                                            Text("base").font(.caption2).foregroundColor(.secondary)
                                            if healthKit.activeCalories > 0 {
                                                Text("+").font(.caption2).foregroundColor(.secondary)
                                                Text("\(Int(healthKit.activeCalories))").font(.subheadline).fontWeight(.semibold).foregroundColor(.orange)
                                                Text("exercise").font(.caption2).foregroundColor(.orange)
                                            }
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Total").font(.caption).foregroundColor(.secondary)
                                        Text("\(adjustedGoal) kcal").font(.subheadline).fontWeight(.bold).foregroundColor(.green)
                                    }
                                }
                                .padding(10).background(Color.green.opacity(0.06)).cornerRadius(10)
                                Divider()
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    HealthStatCard(icon: "moon.zzz.fill", label: "Sleep", value: healthKit.sleepFormatted, color: .purple, goalMet: healthKit.sleepGoalMet)
                                    HealthStatCard(icon: "flame.fill", label: "Active Cal", value: "\(Int(healthKit.activeCalories)) kcal", color: .orange, goalMet: healthKit.activeCalories > 300)
                                    if healthKit.heartRate > 0 {
                                        HealthStatCard(icon: "heart.fill", label: "Heart Rate", value: "\(Int(healthKit.heartRate)) bpm", color: .red, goalMet: healthKit.heartRate < 100)
                                    }
                                    HealthStatCard(icon: "fork.knife", label: "Net Calories", value: "\(Int(Double(totalCalories) - healthKit.activeCalories)) kcal", color: .green,
                                                   goalMet: Int(Double(totalCalories) - healthKit.activeCalories) <= Int(goal))
                                }
                                if healthKit.isPeriodDay {
                                    Divider()
                                    Label("Period day today", systemImage: "circle.fill").font(.caption).foregroundColor(.pink)
                                } else if let days = healthKit.daysUntilNextPeriod, days <= 5 {
                                    Divider()
                                    Label("Period expected in \(days) day\(days == 1 ? "" : "s")", systemImage: "calendar.badge.clock")
                                        .font(.caption).foregroundColor(.pink)
                                }
                            } else {
                                Text("Connect Apple Health to see your steps, sleep and activity").font(.caption).foregroundColor(.secondary)
                                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                        }
                        .padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)

                        Button(action: resetDay) {
                            Label("Reset Today's Calories", systemImage: "arrow.counterclockwise").font(.footnote).foregroundColor(.red)
                        }.padding(.bottom, 24)
                    }
                }
                .offset(x: dragOffset)
                .refreshable {
                    healthKit.fetchAll(); recentMeals = ManualMeal.loadAll()
                    financeStore.refreshAll(); weightLogs = WeightLog.loadAll()
                }

                if showingLogPanel {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35)) { showingLogPanel = false; dragOffset = 0 }
                        }
                }
                if showingLogPanel {
                    HStack(spacing: 0) {
                        Spacer()
                        LogMealPanel(
                            onDismiss: {
                                withAnimation(.spring(response: 0.35)) { showingLogPanel = false; dragOffset = 0 }
                                recentMeals = ManualMeal.loadAll()
                            },
                            totalCalories: $totalCalories, totalCarbs: $totalCarbs,
                            totalProtein: $totalProtein, totalFat: $totalFat
                        )
                        .frame(width: screenWidth * 0.88).transition(.move(edge: .trailing))
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !showingLogPanel && value.translation.width < 0 {
                            dragOffset = max(value.translation.width, -screenWidth * 0.88)
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < -60 && !showingLogPanel {
                            withAnimation(.spring(response: 0.35)) { showingLogPanel = true; dragOffset = 0 }
                        } else { withAnimation(.spring(response: 0.35)) { dragOffset = 0 } }
                    }
            )
            .navigationTitle("Kelly Life")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingQuickLogOptions = true }) {
                        Image(systemName: "plus.circle.fill").foregroundColor(.green).font(.title3)
                    }
                }
            }
        }
        .sheet(isPresented: $showingWeightLogSheet) {
            WeightLogEntryView { newLog in WeightLog.save(newLog); weightLogs = WeightLog.loadAll() }
        }
        .sheet(isPresented: $showingAddTransactionSheet) { AddTransactionView(store: financeStore) }
        .sheet(item: $selectedWeightLog) { log in
            WeightLogDetailView(
                log: log,
                onUpdate: { updated in
                    WeightLog.update(updated)
                    weightLogs = WeightLog.loadAll()
                },
                onDelete: {
                    WeightLog.delete(log)
                    weightLogs = WeightLog.loadAll()
                }
            )
        }
        .sheet(isPresented: $showAddTodo) {
            AddEditTodoView(store: todoStore)
        }
        .sheet(item: $editingTodo) { todo in AddEditTodoView(store: todoStore, existing: todo) }
        .confirmationDialog("What would you like to log?", isPresented: $showingQuickLogOptions, titleVisibility: .visible) {
            Button("Log Meal") { withAnimation(.spring(response: 0.35)) { showingLogPanel = true; dragOffset = 0 } }
            Button("Log Weight") { showingWeightLogSheet = true }
            Button("Log Finance Transaction") { showingAddTransactionSheet = true }
            Button("Add To-Do") { showAddTodo = true }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Pick one to add now.") }
        .fullScreenCover(isPresented: $showingCelebration) {
            DashboardCelebrationView(
                title: celebrationTitle,
                emoji: celebrationEmoji,
                years: celebrationYears,
                onDismiss: { showingCelebration = false }
            )
        }
        .onAppear {
            recentMeals = ManualMeal.loadAll(); weightLogs = WeightLog.loadAll()
            if !healthKit.isAuthorized { healthKit.requestAuthorization() }
        }
    }

    func dayLabel(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date) }
    func relativeDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return "In \(days) days"
    }
    func timeString(_ date: Date) -> String { let f = DateFormatter(); f.timeStyle = .short; return f.string(from: date) }
    func shortTimeString(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date) }
    func resetDay() { totalCalories = 0; totalCarbs = 0; totalProtein = 0; totalFat = 0; recentMeals = ManualMeal.loadAll() }
}

// MARK: - To-Do Dashboard Section

struct TodoDashboardSection: View {
    @ObservedObject var store: TodoStore
    @Binding var showAddTodo: Bool
    @Binding var editingTodo: TodoItem?
    @Binding var showCompleted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("To-Do").font(.headline)
                Spacer()
                // Progress
                if !store.todos.isEmpty {
                    Text("\(store.todos.filter { $0.isDone }.count)/\(store.todos.count)")
                        .font(.caption).foregroundColor(.secondary)
                }
                Button(action: { showAddTodo = true }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(.green).font(.title3)
                }
            }

            // Progress bar
            if !store.todos.isEmpty {
                VStack(spacing: 6) {
                    ProgressView(value: store.progress).tint(.green)
                    HStack {
                        Text(progressMessage).font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(store.progress * 100))%").font(.caption2).foregroundColor(.green).fontWeight(.semibold)
                    }
                }
            }

            // Pending items
            if store.pending.isEmpty && store.todos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 32)).foregroundColor(.secondary.opacity(0.4))
                    Text("No tasks yet").font(.subheadline).foregroundColor(.secondary)
                    Button(action: { showAddTodo = true }) {
                        Label("Add your first task", systemImage: "plus.circle").font(.caption).foregroundColor(.green)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                if !store.pending.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(store.pending) { item in
                            DashboardTodoRow(item: item, store: store)
                                .onTapGesture { editingTodo = item }
                                .swipeActions(edge: .leading) {
                                    Button { store.toggle(item) } label: {
                                        Label("Done", systemImage: "checkmark.circle")
                                    }.tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { store.todos.removeAll { $0.id == item.id } }
                                    label: { Label("Delete", systemImage: "trash") }
                                    Button { editingTodo = item } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("All done! 🎉").font(.subheadline).foregroundColor(.green)
                    }.padding(.vertical, 8)
                }

                // Completed toggle
                if !store.completed.isEmpty {
                    Button(action: { withAnimation { showCompleted.toggle() } }) {
                        HStack {
                            Text("Completed (\(store.completed.count))").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: showCompleted ? "chevron.up" : "chevron.down").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if showCompleted {
                        VStack(spacing: 6) {
                            ForEach(store.completed.prefix(5)) { item in
                                DashboardTodoRow(item: item, store: store)
                                    .swipeActions(edge: .leading) {
                                        Button { store.toggle(item) } label: {
                                            Label("Undo", systemImage: "arrow.uturn.backward")
                                        }.tint(.orange)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { store.todos.removeAll { $0.id == item.id } }
                                        label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .padding().background(.regularMaterial).cornerRadius(16)
    }

    var progressMessage: String {
        let pct = Int(store.progress * 100)
        if pct == 100 { return "All done! 🎉" }
        if pct >= 75 { return "Almost there! 💪" }
        if pct >= 50 { return "Halfway through!" }
        if pct >= 25 { return "Good start!" }
        return "Let's get going!"
    }
}

// MARK: - Dashboard Todo Row

struct DashboardTodoRow: View {
    let item: TodoItem; @ObservedObject var store: TodoStore
    var body: some View {
        HStack(spacing: 10) {
            Button(action: { store.toggle(item) }) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundColor(item.isDone ? .green : item.priority.color)
            }
            Text(item.emoji).font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline).fontWeight(.medium)
                    .strikethrough(item.isDone).foregroundColor(item.isDone ? .secondary : .primary)
                if item.hasDueDate && !item.dueDateLabel.isEmpty {
                    Text(item.dueDateLabel).font(.caption2).foregroundColor(item.isOverdue ? .red : .secondary)
                }
            }
            Spacer()
            // Priority dot
            Circle().fill(item.priority.color).frame(width: 6, height: 6).opacity(item.isDone ? 0 : 1)
        }
        .padding(10).background(Color(.systemBackground)).cornerRadius(10)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .opacity(item.isDone ? 0.6 : 1.0)
    }
}

// MARK: - Add / Edit Todo View

struct AddEditTodoView: View {
    @ObservedObject var store: TodoStore
    @Environment(\.dismiss) var dismiss
    var existing: TodoItem?
    @State private var title = ""; @State private var note = ""
    @State private var priority: TodoPriority = .medium
    @State private var hasDueDate = false; @State private var dueDate = Date()
    @State private var emoji = "✅"
    var isEditing: Bool { existing != nil }
    let quickEmojis = ["✅","📌","🔥","💡","📞","🛒","💊","🏃","📝","🎯","🧹","💻","📧","🍳","🚗","💰","📚","🎵","🌿","⚡"]

    var body: some View {
        NavigationView {
            Form {
                Section("Task") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(quickEmojis, id: \.self) { e in
                                Text(e).font(.system(size: 26)).padding(6)
                                    .background(emoji == e ? Color.green.opacity(0.2) : Color.clear)
                                    .cornerRadius(8).onTapGesture { emoji = e }
                            }
                        }.padding(.vertical, 4)
                    }
                    TextField("What needs to be done?", text: $title)
                    TextField("Note (optional)", text: $note)
                }
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TodoPriority.allCases, id: \.self) { p in
                            Label(p.rawValue, systemImage: p.icon).tag(p)
                        }
                    }.pickerStyle(.segmented)
                }
                Section("Due Date") {
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Add") {
                        guard !title.isEmpty else { return }
                        let item = TodoItem(id: existing?.id ?? UUID(), title: title, note: note,
                            isDone: existing?.isDone ?? false, priority: priority,
                            dueDate: hasDueDate ? dueDate : nil, hasDueDate: hasDueDate, emoji: emoji)
                        if isEditing, let i = store.todos.firstIndex(where: { $0.id == item.id }) {
                            store.todos[i] = item
                        } else { store.todos.append(item) }
                        dismiss()
                    }.fontWeight(.bold).disabled(title.isEmpty)
                }
            }
            .onAppear {
                guard let e = existing else { return }
                title = e.title
                note = e.note
                priority = e.priority
                emoji = e.emoji
                hasDueDate = e.hasDueDate
                if let d = e.dueDate { dueDate = d }
            }
        }
    }
}

// MARK: - Month Finance Summary

struct MonthFinanceSummary: View {
    @ObservedObject var store: FinanceStore
    var spent: Double { store.monthSpent() }
    var budget: Double { store.totalMonthlyBudget }
    var remaining: Double { store.monthBudgetRemaining() }
    var income: Double { store.totalIncome(for: .month) }
    var isOverBudget: Bool { remaining < 0 }
    var monthName: String { let f = DateFormatter(); f.dateFormat = "MMMM"; return f.string(from: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "dollarsign.circle.fill").foregroundColor(.green)
                Text("\(monthName) Overview").font(.headline)
                Spacer()
                if income > 0 { Text(String(format: "+$%.2f income", income)).font(.caption).foregroundColor(.green) }
            }
            if !store.stockHoldings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "chart.bar.fill").foregroundColor(.blue)
                        Text("Stock Portfolio").font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Text(String(format: "$%.2f", store.totalStockValue)).font(.subheadline).fontWeight(.bold)
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.isWeekend ? "vs Last Friday" : "Today").font(.caption2).foregroundColor(.secondary)
                            Text((store.todayStockGainLoss >= 0 ? "+" : "") + String(format: "$%.2f", store.todayStockGainLoss))
                                .font(.title3).fontWeight(.bold).foregroundColor(store.todayStockGainLoss >= 0 ? .green : .red)
                            Text(String(format: "%.2f%%", store.todayStockGainLossPercent)).font(.caption2)
                                .foregroundColor(store.todayStockGainLoss >= 0 ? .green : .red)
                        }
                        .frame(maxWidth: .infinity).padding(10)
                        .background(store.todayStockGainLoss >= 0 ? Color.green.opacity(0.08) : Color.red.opacity(0.08)).cornerRadius(10)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Overall").font(.caption2).foregroundColor(.secondary)
                            Text((store.totalStockGainLoss >= 0 ? "+" : "") + String(format: "$%.2f", store.totalStockGainLoss))
                                .font(.title3).fontWeight(.bold).foregroundColor(store.totalStockGainLoss >= 0 ? .green : .red)
                            Text(String(format: "%.2f%%", store.totalStockGainLossPercent)).font(.caption2)
                                .foregroundColor(store.totalStockGainLoss >= 0 ? .green : .red)
                        }
                        .frame(maxWidth: .infinity).padding(10)
                        .background(store.totalStockGainLoss >= 0 ? Color.green.opacity(0.08) : Color.red.opacity(0.08)).cornerRadius(10)
                    }
                }.padding().background(Color.blue.opacity(0.05)).cornerRadius(12)
            }
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.green.opacity(0.15), lineWidth: 10).frame(width: 80, height: 80)
                    Circle().trim(from: 0, to: budget > 0 ? CGFloat(min(spent / budget, 1.0)) : 0)
                        .stroke(isOverBudget ? Color.red : Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 80, height: 80).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(budget > 0 ? "\(Int(min(spent / budget * 100, 999)))%" : "—")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(isOverBudget ? .red : .primary)
                        Text("used").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("Spent").font(.caption).foregroundColor(.secondary); Spacer()
                        Text(String(format: "$%.2f", spent)).font(.subheadline).fontWeight(.semibold).foregroundColor(.red)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Budget").font(.caption).foregroundColor(.secondary); Spacer()
                        Text(budget > 0 ? String(format: "$%.2f", budget) : "Not set").font(.subheadline).fontWeight(.semibold).foregroundColor(.green)
                    }
                    Divider()
                    HStack(spacing: 6) {
                        Circle().fill(isOverBudget ? Color.red : Color.blue).frame(width: 8, height: 8)
                        Text(isOverBudget ? "Over by" : "Left").font(.caption).foregroundColor(.secondary); Spacer()
                        Text(budget > 0 ? String(format: "$%.2f", abs(remaining)) : "—")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(isOverBudget ? .red : .blue)
                    }
                }.frame(maxWidth: .infinity)
            }
            if budget > 0 {
                ProgressView(value: min(spent / budget, 1.0)).tint(isOverBudget ? .red : spent / budget > 0.8 ? .orange : .green)
                Label(isOverBudget ? String(format: "Over monthly budget by $%.2f", abs(remaining))
                      : spent / budget > 0.8 ? String(format: "Almost at budget — $%.2f left", remaining)
                      : String(format: "$%.2f remaining this month", remaining),
                      systemImage: isOverBudget ? "exclamationmark.triangle.fill" : spent / budget > 0.8 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption).foregroundColor(isOverBudget ? .red : spent / budget > 0.8 ? .orange : .green)
            } else {
                Text("Set a monthly budget in Finance to track spending").font(.caption).foregroundColor(.secondary)
            }
            let maturingSoon = store.cdAccounts.filter { $0.daysUntilMaturity <= 30 && !$0.isMatured }
            if !maturingSoon.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("CDs Maturing Soon").font(.caption).foregroundColor(.secondary)
                    ForEach(maturingSoon) { cd in
                        HStack {
                            Image(systemName: "banknote").foregroundColor(.orange)
                            Text(cd.bankName).font(.caption).foregroundColor(.secondary)
                            Text(String(format: "$%.2f", cd.principal)).font(.caption).fontWeight(.medium)
                            Spacer()
                            Text(cd.statusText).font(.caption).fontWeight(.semibold).foregroundColor(cd.statusColor)
                        }
                    }
                }
            }
        }.padding().background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Log Meal Panel

struct LogMealPanel: View {
    let onDismiss: () -> Void
    @Binding var totalCalories: Int; @Binding var totalCarbs: Double
    @Binding var totalProtein: Double; @Binding var totalFat: Double
    @State private var recentMeals: [ManualMeal] = ManualMeal.loadAll()
    @State private var showAddMeal = false
    var todayMeals: [ManualMeal] { recentMeals.filter { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary) }
                Spacer(); Text("Meal Log").font(.headline); Spacer()
                Button(action: { showAddMeal = true }) { Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.green) }
            }.padding().background(.regularMaterial)
            HStack(spacing: 0) {
                VStack(spacing: 2) { Text("\(totalCalories)").font(.title2).fontWeight(.bold).foregroundColor(.green); Text("kcal").font(.caption2).foregroundColor(.secondary) }.frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                VStack(spacing: 2) { Text("\(todayMeals.count)").font(.title2).fontWeight(.bold); Text("meals").font(.caption2).foregroundColor(.secondary) }.frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                VStack(spacing: 2) { Text("\(Int(totalCarbs))g").font(.title2).fontWeight(.bold).foregroundColor(.orange); Text("carbs").font(.caption2).foregroundColor(.secondary) }.frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                VStack(spacing: 2) { Text("\(Int(totalProtein))g").font(.title2).fontWeight(.bold).foregroundColor(.green); Text("protein").font(.caption2).foregroundColor(.secondary) }.frame(maxWidth: .infinity)
            }.padding().background(.regularMaterial)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    if todayMeals.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "fork.knife.circle").font(.system(size: 50)).foregroundColor(.secondary.opacity(0.3))
                            Text("No meals logged today").font(.subheadline).foregroundColor(.secondary)
                            Text("Check 薄荷健康 for calories\nthen add them here").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }.padding(.vertical, 40)
                    } else {
                        ForEach(todayMeals) { meal in MealLogRow(meal: meal, onDelete: { deleteMeal(meal) }).padding(.horizontal) }
                    }
                    let pastMeals = recentMeals.filter { !Calendar.current.isDateInToday($0.date) }
                    if !pastMeals.isEmpty {
                        HStack { Text("Earlier").font(.caption).foregroundColor(.secondary); Spacer() }.padding(.horizontal).padding(.top, 8)
                        ForEach(pastMeals.prefix(8)) { meal in MealLogRow(meal: meal, onDelete: { deleteMeal(meal) }, showDate: true).padding(.horizontal) }
                    }
                }.padding(.vertical, 12)
            }.refreshable { recentMeals = ManualMeal.loadAll() }
            Button(action: { showAddMeal = true }) {
                Label("Log a Meal", systemImage: "plus.circle.fill").font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding().background(Color.green).cornerRadius(14).padding(.horizontal).padding(.bottom, 16)
            }
        }
        .background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, x: -5, y: 0)
        .sheet(isPresented: $showAddMeal, onDismiss: { recentMeals = ManualMeal.loadAll() }) {
            ManualMealEntryView { meal in
                totalCalories += meal.calories; totalCarbs += meal.carbs
                totalProtein += meal.protein; totalFat += meal.fat
                ManualMeal.save(meal); recentMeals = ManualMeal.loadAll()
            }
        }
    }
    func deleteMeal(_ meal: ManualMeal) {
        totalCalories = max(0, totalCalories - meal.calories); totalCarbs = max(0, totalCarbs - meal.carbs)
        totalProtein = max(0, totalProtein - meal.protein); totalFat = max(0, totalFat - meal.fat)
        ManualMeal.delete(meal); recentMeals = ManualMeal.loadAll()
    }
}

// MARK: - Macro Card

struct MacroCard: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 6) {
            Text(value).font(.title2).fontWeight(.semibold).foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity).padding().background(.regularMaterial).cornerRadius(12)
    }
}

// MARK: - Health Stat Card

struct HealthStatCard: View {
    let icon: String; let label: String; let value: String; let color: Color; let goalMet: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 20)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.subheadline).fontWeight(.semibold)
                Text(label).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if goalMet { Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption) }
        }.padding(10).background(color.opacity(0.08)).cornerRadius(10)
    }
}

// MARK: - Weight Log Model

struct WeightLog: Identifiable, Codable, Hashable {
    var id = UUID()
    var weight: Double
    var date: Date = Date()
    var note: String = ""

    static let storageKey = "weightLogs"

    static func loadAll() -> [WeightLog] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let logs = try? JSONDecoder().decode([WeightLog].self, from: data)
        else {
            return []
        }

        return logs.sorted {
            $0.date > $1.date
        }
    }

    static func save(_ log: WeightLog) {
        var all = loadAll()
        all.append(log)

        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func update(_ log: WeightLog) {
        var all = loadAll()

        guard let index = all.firstIndex(where: {
            $0.id == log.id
        }) else {
            return
        }

        all[index] = log

        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func delete(_ log: WeightLog) {
        var all = loadAll()

        all.removeAll {
            $0.id == log.id
        }

        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func logs(for date: Date) -> [WeightLog] {
        loadAll().filter {
            Calendar.current.isDate(
                $0.date,
                inSameDayAs: date
            )
        }
    }
}

// MARK: - Weight Log Entry View

struct WeightLogEntryView: View {
    let onSave: (WeightLog) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var weight = ""; @State private var date = Date(); @State private var note = ""
    var body: some View {
        NavigationView {
            Form {
                Section("Weight") { HStack { TextField("e.g. 62.5", text: $weight).keyboardType(.decimalPad); Text("kg").foregroundColor(.secondary) } }
                Section("Time") { DatePicker("Date & Time", selection: $date) }
                Section("Note Optional") { TextField("Morning, evening, after workout...", text: $note) }
                Section { Text("You can log more than once per day.").font(.caption).foregroundColor(.secondary) }
            }
            .navigationTitle("Log Weight").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard let value = Double(weight) else { return }
                        onSave(WeightLog(weight: value, date: date, note: note)); dismiss()
                    }.fontWeight(.bold).disabled(Double(weight) == nil)
                }
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 300; var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Manual Meal Model

struct ManualMeal: Identifiable, Codable {
    var id = UUID(); var name: String; var mealType: MealType
    var calories: Int; var carbs: Double; var protein: Double; var fat: Double
    var date: Date = Date(); var emoji: String
    enum MealType: String, Codable, CaseIterable {
        case breakfast = "Breakfast"; case lunch = "Lunch"; case dinner = "Dinner"
        case snack = "Snack"; case drink = "Drink"
        var emoji: String {
            switch self { case .breakfast: return "🌅"; case .lunch: return "☀️"; case .dinner: return "🌙"; case .snack: return "🍪"; case .drink: return "🥤" }
        }
    }
    static func loadAll() -> [ManualMeal] {
        guard let data = UserDefaults.standard.data(forKey: "manualMeals"),
              let meals = try? JSONDecoder().decode([ManualMeal].self, from: data) else { return [] }
        return meals.sorted { $0.date > $1.date }
    }
    static func save(_ meal: ManualMeal) {
        var all = loadAll(); all.append(meal)
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: "manualMeals") }
    }
    static func delete(_ meal: ManualMeal) {
        var all = loadAll(); all.removeAll { $0.id == meal.id }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: "manualMeals") }
    }
}

// MARK: - Meal Log Row

struct MealLogRow: View {
    let meal: ManualMeal; let onDelete: () -> Void; var showDate: Bool = false
    var timeString: String { let f = DateFormatter(); f.dateFormat = showDate ? "M/d HH:mm" : "HH:mm"; return f.string(from: meal.date) }
    var body: some View {
        HStack(spacing: 12) {
            Text(meal.emoji).font(.system(size: 28)).frame(width: 44, height: 44).background(Color.green.opacity(0.1)).cornerRadius(10)
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name).font(.subheadline).fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(meal.mealType.emoji + " " + meal.mealType.rawValue).font(.caption2).foregroundColor(.secondary)
                    Text("·").foregroundColor(.secondary)
                    Text(timeString).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(meal.calories) kcal").font(.subheadline).fontWeight(.semibold).foregroundColor(.green)
                HStack(spacing: 4) {
                    Text("C:\(Int(meal.carbs))g").font(.caption2).foregroundColor(.orange)
                    Text("P:\(Int(meal.protein))g").font(.caption2).foregroundColor(.green)
                    Text("F:\(Int(meal.fat))g").font(.caption2).foregroundColor(.blue)
                }
            }
        }
        .padding().background(.regularMaterial).cornerRadius(12)
        .swipeActions(edge: .trailing) { Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") } }
    }
}

// MARK: - Manual Meal Entry View

struct ManualMealEntryView: View {
    let onSave: (ManualMeal) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var name = ""; @State private var mealType: ManualMeal.MealType = .lunch
    @State private var calories = ""; @State private var carbs = ""
    @State private var protein = ""; @State private var fat = ""; @State private var selectedEmoji = "🍚"
    let commonEmojis = ["🍚","🍜","🥩","🍗","🥗","🍱","🥟","🍛","🍝","🥘","🍲","🍣","🥙","🌮","🥪","🍔","🍕","🥞","🥚","🍳","🥣","🍦","🧁","🍰","🍪","🥤","☕","🧃","🍵","🥛"]
    var estimatedMacros: (carbs: Double, protein: Double, fat: Double) {
        guard let cal = Double(calories) else { return (0, 0, 0) }
        return (carbs: (cal * 0.5) / 4, protein: (cal * 0.25) / 4, fat: (cal * 0.25) / 9)
    }
    var body: some View {
        NavigationView {
            Form {
                Section("What did you eat?") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonEmojis, id: \.self) { e in
                                Text(e).font(.system(size: 28)).padding(6)
                                    .background(selectedEmoji == e ? Color.green.opacity(0.2) : Color.clear)
                                    .cornerRadius(8).onTapGesture { selectedEmoji = e }
                            }
                        }.padding(.vertical, 4)
                    }
                    TextField("Food name (e.g. 麻婆豆腐, Rice)", text: $name)
                    Picker("Meal type", selection: $mealType) {
                        ForEach(ManualMeal.MealType.allCases, id: \.self) { Text($0.emoji + " " + $0.rawValue).tag($0) }
                    }
                }
                Section("Calories (from 薄荷健康)") {
                    HStack { TextField("e.g. 450", text: $calories).keyboardType(.numberPad); Text("kcal").foregroundColor(.secondary) }
                    if !calories.isEmpty && carbs.isEmpty && protein.isEmpty && fat.isEmpty {
                        Button(action: {
                            let est = estimatedMacros
                            carbs = String(format: "%.0f", est.carbs)
                            protein = String(format: "%.0f", est.protein)
                            fat = String(format: "%.0f", est.fat)
                        }) { Label("Auto-estimate macros", systemImage: "wand.and.stars").font(.caption).foregroundColor(.green) }
                    }
                }
                Section("Macros (optional)") {
                    HStack { Text("Carbs").frame(width: 70, alignment: .leading); TextField("g", text: $carbs).keyboardType(.decimalPad); Text("g").foregroundColor(.secondary) }
                    HStack { Text("Protein").frame(width: 70, alignment: .leading); TextField("g", text: $protein).keyboardType(.decimalPad); Text("g").foregroundColor(.secondary) }
                    HStack { Text("Fat").frame(width: 70, alignment: .leading); TextField("g", text: $fat).keyboardType(.decimalPad); Text("g").foregroundColor(.secondary) }
                }
                Section { Text("Tip: Check calories in 薄荷健康 first.").font(.caption).foregroundColor(.secondary) }
            }
            .navigationTitle("Log Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard !name.isEmpty, let cal = Int(calories) else { return }
                        let est = estimatedMacros
                        let meal = ManualMeal(name: name, mealType: mealType, calories: cal,
                            carbs: Double(carbs) ?? est.carbs, protein: Double(protein) ?? est.protein,
                            fat: Double(fat) ?? est.fat, emoji: selectedEmoji)
                        onSave(meal); dismiss()
                    }.fontWeight(.bold).disabled(name.isEmpty || calories.isEmpty)
                }
            }
        }
    }
}

// MARK: - Nutrition Badge

struct NutritionBadge: View {
    let label: String; let value: String; let unit: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(color)
            Text(unit).font(.caption2).foregroundColor(.secondary)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - Weight Log Detail View

struct WeightLogDetailView: View {
    let log: WeightLog
    let onUpdate: (WeightLog) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) var dismiss

    @State private var isEditing = false
    @State private var editedWeight = ""
    @State private var editedDate = Date()
    @State private var editedNote = ""

    var body: some View {
        NavigationView {
            List {

                Section("Weight") {
                    if isEditing {
                        HStack {
                            Label("Value", systemImage: "scalemass")
                            Spacer()

                            TextField("Weight", text: $editedWeight)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)

                            Text("kg")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Label("Value", systemImage: "scalemass")
                            Spacer()

                            Text(String(format: "%.1f kg", log.weight))
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                }

                Section("Time") {
                    if isEditing {
                        DatePicker(
                            "Date & Time",
                            selection: $editedDate
                        )
                    } else {
                        HStack {
                            Label("Date", systemImage: "calendar")
                            Spacer()
                            Text(dateString(log.date))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Label("Time", systemImage: "clock")
                            Spacer()
                            Text(timeString(log.date))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Label(
                                "Period",
                                systemImage: timeIcon(log.date)
                            )

                            Spacer()

                            Text(periodLabel(log.date))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Note") {
                    if isEditing {

                        TextField(
                            "Optional note",
                            text: $editedNote
                        )

                    } else if log.note
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty {

                        Text("No note")
                            .foregroundColor(.secondary)

                    } else {

                        Text(log.note)
                    }
                }

                if !isEditing {

                    Section {

                        Button {
                            editedWeight =
                                String(
                                    format: "%.1f",
                                    log.weight
                                )

                            editedDate = log.date
                            editedNote = log.note

                            isEditing = true

                        } label: {

                            Label(
                                "Edit this weight log",
                                systemImage: "pencil"
                            )
                        }

                        Button(role: .destructive) {
                            onDelete()
                            dismiss()

                        } label: {

                            Label(
                                "Delete this weight log",
                                systemImage: "trash"
                            )
                        }
                    }
                }
            }

            .navigationTitle(
                isEditing
                ? "Edit Weight"
                : "Weight Detail"
            )

            .navigationBarTitleDisplayMode(
                .inline
            )

            .toolbar {

                ToolbarItem(
                    placement:
                        .navigationBarLeading
                ) {
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                        }
                    }
                }

                ToolbarItem(
                    placement:
                        .navigationBarTrailing
                ) {

                    if isEditing {

                        Button("Save") {

                            guard let value =
                                    Double(editedWeight)
                            else {
                                return
                            }

                            let updated =
                                WeightLog(
                                    id: log.id,
                                    weight: value,
                                    date: editedDate,
                                    note: editedNote
                                )

                            onUpdate(updated)

                            dismiss()
                        }

                        .fontWeight(.bold)

                        .disabled(
                            Double(editedWeight) == nil
                        )

                    } else {

                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }

            .onAppear {

                editedWeight =
                    String(
                        format: "%.1f",
                        log.weight
                    )

                editedDate = log.date
                editedNote = log.note
            }
        }
    }

    func dateString(
        _ date: Date
    ) -> String {

        let f = DateFormatter()
        f.dateStyle = .full

        return f.string(from: date)
    }

    func timeString(
        _ date: Date
    ) -> String {

        let f = DateFormatter()
        f.timeStyle = .short

        return f.string(from: date)
    }

    func periodLabel(
        _ date: Date
    ) -> String {

        let h =
            Calendar.current.component(
                .hour,
                from: date
            )

        if h < 12 {
            return "Morning"
        }

        if h < 18 {
            return "Afternoon"
        }

        return "Evening"
    }

    func timeIcon(
        _ date: Date
    ) -> String {

        let h =
            Calendar.current.component(
                .hour,
                from: date
            )

        if h < 12 {
            return "sunrise.fill"
        }

        if h < 18 {
            return "sun.max.fill"
        }

        return "moon.fill"
    }
}


// MARK: - Dashboard Celebration View

struct DashboardCelebrationView: View {
    let title: String
    let emoji: String
    let years: Int
    let onDismiss: () -> Void
    @State private var particles: [DashParticle] = []
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.pink.opacity(0.4), Color.orange.opacity(0.3), Color.purple.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()
            ForEach(particles) { p in
                Text(p.emoji).font(.system(size: p.size))
                    .position(p.position).opacity(p.opacity).rotationEffect(.degrees(p.rotation))
            }
            VStack(spacing: 32) {
                Spacer()
                Text(emoji).font(.system(size: 120)).scaleEffect(scale).opacity(opacity)
                VStack(spacing: 16) {
                    Text("🎉 Happy Anniversary! 🎉").font(.title).fontWeight(.bold).multilineTextAlignment(.center)
                    Text(title).font(.title2).fontWeight(.semibold).multilineTextAlignment(.center)
                    if years > 0 {
                        VStack(spacing: 8) {
                            Text("\(years)").font(.system(size: 80, weight: .black)).foregroundColor(.orange)
                            Text("Year\(years == 1 ? "" : "s")").font(.title3).fontWeight(.semibold).foregroundColor(.orange)
                            Text("That's \(years * 365) days 💕").font(.subheadline).foregroundColor(.secondary)
                        }
                    } else {
                        Text("Today is the day! 🌟").font(.title3).foregroundColor(.orange)
                    }
                }
                .padding(24).background(.regularMaterial).cornerRadius(28)
                .padding(.horizontal).scaleEffect(scale).opacity(opacity)
                Spacer()
                Button(action: onDismiss) {
                    HStack(spacing: 8) {
                        Image(systemName: "party.popper.fill")
                        Text("Woohoo! 🎊")
                    }
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding()
                    .background(LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(16).padding(.horizontal)
                }.padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { scale = 1.0; opacity = 1.0 }
            let emojis = ["🎉","🎊","✨","💕","🌸","⭐","🎈","💫","🌟","❤️","🥂","🎆"]
            let w = UIScreen.main.bounds.width; let h = UIScreen.main.bounds.height
            particles = (0..<50).map { _ in
                DashParticle(emoji: emojis.randomElement()!,
                    position: CGPoint(x: CGFloat.random(in: 0...w), y: CGFloat.random(in: 0...h)),
                    size: CGFloat.random(in: 18...48), opacity: Double.random(in: 0.5...1.0),
                    rotation: Double.random(in: 0...360))
            }
        }
    }
}

struct DashParticle: Identifiable {
    let id = UUID()
    let emoji: String
    let position: CGPoint
    let size: CGFloat
    let opacity: Double
    let rotation: Double
}

// MARK: - Weight Trend Dashboard

struct WeightTrendDashboard: View {

    enum TrendPeriod: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
    }

    struct TrendPoint: Identifiable {
        let id = UUID()

        let date: Date
        let weight: Double

        // Original entries included in this point
        let logs: [WeightLog]
    }

    @State private var selectedPeriod:
        TrendPeriod = .week

    @State private var selectedPoint:
        TrendPoint?

    @State private var selectedLog:
        WeightLog?

    @State private var showEntries = false

    @State private var refreshID =
        UUID()


    // MARK: All Logs

    var allLogs: [WeightLog] {

        WeightLog
            .loadAll()
            .sorted {
                $0.date < $1.date
            }
    }


    // MARK: Current Period

    var periodLogs: [WeightLog] {

        let cal =
            Calendar.current

        let now =
            Date()


        switch selectedPeriod {

        case .week:

            let start =
                cal.date(
                    byAdding: .day,
                    value: -6,
                    to:
                        cal.startOfDay(
                            for: now
                        )
                )
                ??
                now

            return allLogs.filter {
                $0.date >= start
            }


        case .month:

            let start =
                cal.date(
                    byAdding: .day,
                    value: -29,
                    to:
                        cal.startOfDay(
                            for: now
                        )
                )
                ??
                now

            return allLogs.filter {
                $0.date >= start
            }


        case .year:

            let start =
                cal.date(
                    byAdding: .day,
                    value: -364,
                    to:
                        cal.startOfDay(
                            for: now
                        )
                )
                ??
                now

            return allLogs.filter {
                $0.date >= start
            }
        }
    }


    // MARK: Previous Period

    var previousPeriodLogs: [WeightLog] {

        let cal =
            Calendar.current

        let now =
            Date()


        switch selectedPeriod {

        case .week:

            let end =
                cal.date(
                    byAdding: .day,
                    value: -7,
                    to:
                        cal.startOfDay(
                            for: now
                        )
                )
                ??
                now

            let start =
                cal.date(
                    byAdding: .day,
                    value: -13,
                    to:
                        cal.startOfDay(
                            for: now
                        )
                )
                ??
                now

            return allLogs.filter {
                $0.date >= start &&
                $0.date < end
            }


        case .month:

            let end =
                cal.date(
                    byAdding: .day,
                    value: -30,
                    to:
                        cal.startOfDay(
                            for: now
                        )
                )
                ??
                now

            let start =
                cal.date(
                    byAdding: .day,
                    value: -59,
                    to:
                        cal.startOfDay(
                            for: now
                        )
                )
                ??
                now

            return allLogs.filter {
                $0.date >= start &&
                $0.date < end
            }


        case .year:

            let end =
                cal.date(
                    byAdding: .day,
                    value: -365,
                    to:
                        cal.startOfDay(
                            for: now
                        )
                )
                ??
                now

            let start =
                cal.date(
                    byAdding: .day,
                    value: -729,
                    to:
                        cal.startOfDay(
                            for: now
                        )
                )
                ??
                now

            return allLogs.filter {
                $0.date >= start &&
                $0.date < end
            }
        }
    }


    // MARK: Chart Points

    var chartPoints: [TrendPoint] {

        let cal =
            Calendar.current


        switch selectedPeriod {

        // Week = every input is a point
        case .week:

            return periodLogs.map {

                TrendPoint(
                    date: $0.date,
                    weight: $0.weight,
                    logs: [$0]
                )
            }


        // Month = one point per day
        case .month:

            let grouped =
                Dictionary(
                    grouping:
                        periodLogs
                ) {
                    cal.startOfDay(
                        for: $0.date
                    )
                }


            return grouped
                .map {
                    day,
                    logs in


                    let avg =
                        logs
                            .map(\.weight)
                            .reduce(0, +)
                        /
                        Double(
                            logs.count
                        )


                    return TrendPoint(
                        date: day,
                        weight: avg,

                        logs:
                            logs.sorted {
                                $0.date <
                                $1.date
                            }
                    )
                }

                .sorted {
                    $0.date < $1.date
                }


        // Year = one point per week
        case .year:

            let grouped =
                Dictionary(
                    grouping:
                        periodLogs
                ) {

                    cal
                        .dateInterval(
                            of: .weekOfYear,
                            for: $0.date
                        )?
                        .start

                    ??
                    $0.date
                }


            return grouped
                .map {
                    weekStart,
                    logs in


                    let avg =
                        logs
                            .map(\.weight)
                            .reduce(0, +)
                        /
                        Double(
                            logs.count
                        )


                    return TrendPoint(
                        date: weekStart,
                        weight: avg,

                        logs:
                            logs.sorted {
                                $0.date <
                                $1.date
                            }
                    )
                }

                .sorted {
                    $0.date < $1.date
                }
        }
    }


    // MARK: Stats

    var latest: Double? {
        periodLogs.last?.weight
    }


    var periodAvg: Double? {

        guard !periodLogs.isEmpty
        else {
            return nil
        }


        return periodLogs
            .map(\.weight)
            .reduce(0, +)
        /
        Double(
            periodLogs.count
        )
    }


    var prevAvg: Double? {

        guard !previousPeriodLogs.isEmpty
        else {
            return nil
        }


        return previousPeriodLogs
            .map(\.weight)
            .reduce(0, +)
        /
        Double(
            previousPeriodLogs.count
        )
    }


    var periodDiff: Double? {

        guard
            let current =
                periodAvg,

            let previous =
                prevAvg

        else {
            return nil
        }


        return current -
               previous
    }


    var periodChange: Double? {

        guard
            let first =
                periodLogs.first?.weight,

            let last =
                periodLogs.last?.weight

        else {
            return nil
        }


        return last - first
    }


    var minW: Double {

        (
            chartPoints
                .map(\.weight)
                .min()
            ??
            60
        )
        -
        0.5
    }


    var maxW: Double {

        (
            chartPoints
                .map(\.weight)
                .max()
            ??
            80
        )
        +
        0.5
    }


    var compareLabel: String {

        switch selectedPeriod {

        case .week:
            return "vs last week"

        case .month:
            return "vs last month"

        case .year:
            return "vs last year"
        }
    }


    var entriesTitle: String {

        switch selectedPeriod {

        case .week:
            return "Entries This Week"

        case .month:
            return "Entries This Month"

        case .year:
            return "Entries This Year"
        }
    }


    // MARK: Body

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {


            // Header

            HStack {

                Image(
                    systemName:
                        "scalemass.fill"
                )
                .foregroundColor(.blue)


                Text("Weight Trend")
                    .font(.headline)


                Spacer()


                if let latest {

                    Text(
                        String(
                            format:
                                "%.1f kg",
                            latest
                        )
                    )
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                }
            }


            // Week / Month / Year

            Picker(
                "Period",
                selection:
                    $selectedPeriod
            ) {

                ForEach(
                    TrendPeriod.allCases,
                    id: \.self
                ) { period in

                    Text(
                        period.rawValue
                    )
                    .tag(period)
                }
            }

            .pickerStyle(
                .segmented
            )

            .onChange(
                of: selectedPeriod
            ) { _ in

                selectedPoint = nil
                showEntries = false
            }


            if chartPoints.isEmpty {

                VStack(spacing: 8) {

                    Image(
                        systemName:
                            "scalemass"
                    )
                    .font(
                        .system(size: 36)
                    )
                    .foregroundColor(
                        .secondary
                            .opacity(0.4)
                    )


                    Text(
                        "No weight logged this \(selectedPeriod.rawValue.lowercased())"
                    )
                    .font(.subheadline)
                    .foregroundColor(
                        .secondary
                    )
                }

                .frame(
                    maxWidth:
                        .infinity
                )

                .padding(
                    .vertical,
                    20
                )


            } else {


                // MARK: Trend Chart

                GeometryReader { geo in

                    let width =
                        geo.size.width

                    let height =
                        geo.size.height

                    let range =
                        max(
                            maxW - minW,
                            0.5
                        )


                    ZStack {


                        // Grid

                        ForEach(
                            0..<4
                        ) { i in

                            Path { p in

                                let y =
                                    height
                                    *
                                    CGFloat(i)
                                    /
                                    3

                                p.move(
                                    to:
                                        CGPoint(
                                            x: 0,
                                            y: y
                                        )
                                )

                                p.addLine(
                                    to:
                                        CGPoint(
                                            x: width,
                                            y: y
                                        )
                                )
                            }

                            .stroke(
                                Color.secondary
                                    .opacity(0.1),
                                lineWidth: 1
                            )
                        }


                        // Area

                        if chartPoints.count > 1 {

                            Path { p in

                                for (
                                    index,
                                    point
                                )
                                in chartPoints.enumerated() {


                                    let x =
                                        width
                                        *
                                        CGFloat(index)
                                        /
                                        CGFloat(
                                            chartPoints.count - 1
                                        )


                                    let normal =
                                        (
                                            point.weight -
                                            minW
                                        )
                                        /
                                        range


                                    let y =
                                        height
                                        *
                                        CGFloat(
                                            1 - normal
                                        )


                                    if index == 0 {

                                        p.move(
                                            to:
                                                CGPoint(
                                                    x: x,
                                                    y: y
                                                )
                                        )

                                    } else {

                                        p.addLine(
                                            to:
                                                CGPoint(
                                                    x: x,
                                                    y: y
                                                )
                                        )
                                    }
                                }


                                p.addLine(
                                    to:
                                        CGPoint(
                                            x: width,
                                            y: height
                                        )
                                )


                                p.addLine(
                                    to:
                                        CGPoint(
                                            x: 0,
                                            y: height
                                        )
                                )


                                p.closeSubpath()
                            }

                            .fill(

                                LinearGradient(

                                    colors: [
                                        Color.blue.opacity(
                                            0.15
                                        ),

                                        Color.blue.opacity(
                                            0
                                        )
                                    ],

                                    startPoint: .top,

                                    endPoint: .bottom
                                )
                            )


                            // Line

                            Path { p in

                                for (
                                    index,
                                    point
                                )
                                in chartPoints.enumerated() {


                                    let x =
                                        width
                                        *
                                        CGFloat(index)
                                        /
                                        CGFloat(
                                            chartPoints.count - 1
                                        )


                                    let normal =
                                        (
                                            point.weight -
                                            minW
                                        )
                                        /
                                        range


                                    let y =
                                        height
                                        *
                                        CGFloat(
                                            1 - normal
                                        )


                                    if index == 0 {

                                        p.move(
                                            to:
                                                CGPoint(
                                                    x: x,
                                                    y: y
                                                )
                                        )

                                    } else {

                                        p.addLine(
                                            to:
                                                CGPoint(
                                                    x: x,
                                                    y: y
                                                )
                                        )
                                    }
                                }
                            }

                            .stroke(
                                Color.blue,

                                style:
                                    StrokeStyle(
                                        lineWidth: 2.5,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                            )
                        }


                        // MARK: CLICKABLE DOTS

                        ForEach(
                            Array(chartPoints.enumerated()),
                            id: \.element.id
                        ) { item in

                            let index = item.offset
                            let point = item.element


                            let x =
                                chartPoints.count == 1
                                ?
                                width / 2
                                :
                                width
                                *
                                CGFloat(index)
                                /
                                CGFloat(
                                    chartPoints.count - 1
                                )


                            let normal =
                                (
                                    point.weight -
                                    minW
                                )
                                /
                                range


                            let y =
                                height
                                *
                                CGFloat(
                                    1 - normal
                                )


                            Button {

                                selectedPoint =
                                    point

                            } label: {

                                ZStack {

                                    // Big invisible tap area
                                    Circle()
                                        .fill(
                                            Color.blue
                                                .opacity(
                                                    0.001
                                                )
                                        )
                                        .frame(
                                            width: 34,
                                            height: 34
                                        )


                                    Circle()
                                        .fill(
                                            Color.blue
                                        )
                                        .frame(
                                            width:
                                                selectedPoint?.id
                                                ==
                                                point.id
                                                ?
                                                12
                                                :
                                                8,

                                            height:
                                                selectedPoint?.id
                                                ==
                                                point.id
                                                ?
                                                12
                                                :
                                                8
                                        )
                                }
                            }

                            .buttonStyle(
                                .plain
                            )

                            .position(
                                x: x,
                                y: y
                            )


                            if selectedPeriod
                                ==
                                .week {

                                Text(
                                    String(
                                        format:
                                            "%.1f",
                                        point.weight
                                    )
                                )

                                .font(
                                    .system(
                                        size: 8
                                    )
                                )

                                .foregroundColor(
                                    .blue
                                )

                                .position(
                                    x: x,

                                    y:
                                        max(
                                            y - 12,
                                            8
                                        )
                                )
                            }
                        }


                        Text(
                            String(
                                format:
                                    "%.1f",
                                maxW
                            )
                        )
                        .font(
                            .system(size: 8)
                        )
                        .foregroundColor(
                            .secondary
                        )
                        .position(
                            x: 20,
                            y: 8
                        )


                        Text(
                            String(
                                format:
                                    "%.1f",
                                minW
                            )
                        )
                        .font(
                            .system(size: 8)
                        )
                        .foregroundColor(
                            .secondary
                        )
                        .position(
                            x: 20,
                            y: height - 4
                        )
                    }
                }

                .frame(
                    height: 130
                )


                // MARK: Selected Point Details

                if let point =
                    selectedPoint {

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {

                        HStack {

                            Image(
                                systemName:
                                    "hand.tap.fill"
                            )
                            .foregroundColor(
                                .blue
                            )


                            Text(
                                pointTitle(
                                    point
                                )
                            )
                            .font(
                                .subheadline
                            )
                            .fontWeight(
                                .semibold
                            )


                            Spacer()


                            Button {

                                selectedPoint =
                                    nil

                            } label: {

                                Image(
                                    systemName:
                                        "xmark.circle.fill"
                                )
                                .foregroundColor(
                                    .secondary
                                )
                            }
                        }


                        HStack {

                            VStack(
                                alignment:
                                    .leading,
                                spacing: 2
                            ) {

                                Text(
                                    point.logs.count == 1
                                    ?
                                    "Weight"
                                    :
                                    "Average weight"
                                )
                                .font(
                                    .caption2
                                )
                                .foregroundColor(
                                    .secondary
                                )


                                Text(
                                    String(
                                        format:
                                            "%.1f kg",
                                        point.weight
                                    )
                                )
                                .font(
                                    .title3
                                )
                                .fontWeight(
                                    .bold
                                )
                                .foregroundColor(
                                    .blue
                                )
                            }


                            Spacer()


                            Text(
                                "\(point.logs.count) entr\(point.logs.count == 1 ? "y" : "ies")"
                            )
                            .font(.caption)
                            .foregroundColor(
                                .secondary
                            )
                        }


                        // Original entries represented by point

                        ForEach(
                            point.logs
                        ) { log in

                            Button {

                                selectedLog =
                                    log

                            } label: {

                                HStack(
                                    spacing: 10
                                ) {

                                    Image(
                                        systemName:
                                            "scalemass"
                                    )
                                    .foregroundColor(
                                        .blue
                                    )


                                    VStack(
                                        alignment:
                                            .leading,
                                        spacing: 2
                                    ) {

                                        Text(
                                            fullDateTime(
                                                log.date
                                            )
                                        )
                                        .font(
                                            .caption
                                        )
                                        .foregroundColor(
                                            .primary
                                        )


                                        if !log.note
                                            .trimmingCharacters(
                                                in:
                                                    .whitespacesAndNewlines
                                            )
                                            .isEmpty {

                                            Text(
                                                log.note
                                            )
                                            .font(
                                                .caption2
                                            )
                                            .foregroundColor(
                                                .secondary
                                            )
                                            .lineLimit(1)
                                        }
                                    }


                                    Spacer()


                                    Text(
                                        String(
                                            format:
                                                "%.1f kg",
                                            log.weight
                                        )
                                    )
                                    .font(
                                        .subheadline
                                    )
                                    .fontWeight(
                                        .semibold
                                    )
                                    .foregroundColor(
                                        .blue
                                    )


                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .font(
                                        .caption2
                                    )
                                    .foregroundColor(
                                        .secondary
                                    )
                                }

                                .padding(8)

                                .background(
                                    Color(
                                        .systemBackground
                                    )
                                )

                                .cornerRadius(8)
                            }

                            .buttonStyle(
                                .plain
                            )
                        }
                    }

                    .padding(12)

                    .background(
                        Color.blue.opacity(
                            0.06
                        )
                    )

                    .cornerRadius(12)
                }


                // MARK: Stats

                HStack(
                    spacing: 0
                ) {

                    VStack(
                        spacing: 4
                    ) {

                        Text("Avg")
                            .font(
                                .caption2
                            )
                            .foregroundColor(
                                .secondary
                            )


                        if let avg =
                            periodAvg {

                            Text(
                                String(
                                    format:
                                        "%.1f",
                                    avg
                                )
                            )
                            .font(
                                .subheadline
                            )
                            .fontWeight(
                                .bold
                            )
                            .foregroundColor(
                                .blue
                            )


                            Text("kg")
                                .font(
                                    .caption2
                                )
                                .foregroundColor(
                                    .secondary
                                )

                        } else {

                            Text("—")
                        }
                    }

                    .frame(
                        maxWidth:
                            .infinity
                    )


                    Divider()
                        .frame(
                            height: 36
                        )


                    VStack(
                        spacing: 4
                    ) {

                        Text("Change")
                            .font(
                                .caption2
                            )
                            .foregroundColor(
                                .secondary
                            )


                        if let change =
                            periodChange {

                            HStack(
                                spacing: 2
                            ) {

                                Image(
                                    systemName:
                                        change < 0
                                        ?
                                        "arrow.down"
                                        :
                                        change > 0
                                        ?
                                        "arrow.up"
                                        :
                                        "minus"
                                )
                                .font(
                                    .caption2
                                )


                                Text(
                                    String(
                                        format:
                                            "%.1f",
                                        abs(
                                            change
                                        )
                                    )
                                )
                                .font(
                                    .subheadline
                                )
                                .fontWeight(
                                    .bold
                                )
                            }

                            .foregroundColor(
                                change < 0
                                ?
                                .green
                                :
                                change > 0
                                ?
                                .red
                                :
                                .secondary
                            )


                            Text(
                                "kg this \(selectedPeriod.rawValue.lowercased())"
                            )
                            .font(
                                .caption2
                            )
                            .foregroundColor(
                                .secondary
                            )

                        } else {

                            Text("—")
                        }
                    }

                    .frame(
                        maxWidth:
                            .infinity
                    )


                    Divider()
                        .frame(
                            height: 36
                        )


                    VStack(
                        spacing: 4
                    ) {

                        Text(
                            compareLabel
                        )
                        .font(
                            .caption2
                        )
                        .foregroundColor(
                            .secondary
                        )


                        if let diff =
                            periodDiff {

                            HStack(
                                spacing: 2
                            ) {

                                Image(
                                    systemName:
                                        diff < 0
                                        ?
                                        "arrow.down"
                                        :
                                        diff > 0
                                        ?
                                        "arrow.up"
                                        :
                                        "minus"
                                )
                                .font(
                                    .caption2
                                )


                                Text(
                                    String(
                                        format:
                                            "%.1f",
                                        abs(
                                            diff
                                        )
                                    )
                                )
                                .font(
                                    .subheadline
                                )
                                .fontWeight(
                                    .bold
                                )
                            }

                            .foregroundColor(
                                diff < 0
                                ?
                                .green
                                :
                                diff > 0
                                ?
                                .red
                                :
                                .secondary
                            )


                            Text(
                                diff < 0
                                ?
                                "lighter ✓"
                                :
                                diff > 0
                                ?
                                "heavier"
                                :
                                "same"
                            )
                            .font(
                                .caption2
                            )

                        } else {

                            Text("—")
                                .font(
                                    .subheadline
                                )


                            Text(
                                "no prior data"
                            )
                            .font(
                                .caption2
                            )
                            .foregroundColor(
                                .secondary
                            )
                        }
                    }

                    .frame(
                        maxWidth:
                            .infinity
                    )
                }

                .padding(
                    .vertical,
                    8
                )

                .background(
                    Color(
                        .systemGray6
                    )
                    .opacity(
                        0.6
                    )
                )

                .cornerRadius(12)


                Divider()


                // MARK: Expandable Entries

                Button {

                    withAnimation {
                        showEntries.toggle()
                    }

                } label: {

                    HStack {

                        Image(
                            systemName:
                                "list.bullet.rectangle"
                        )
                        .foregroundColor(
                            .blue
                        )


                        VStack(
                            alignment:
                                .leading,
                            spacing: 2
                        ) {

                            Text(
                                entriesTitle
                            )
                            .font(
                                .subheadline
                            )
                            .fontWeight(
                                .semibold
                            )
                            .foregroundColor(
                                .primary
                            )


                            Text(
                                "\(periodLogs.count) saved entr\(periodLogs.count == 1 ? "y" : "ies")"
                            )
                            .font(
                                .caption2
                            )
                            .foregroundColor(
                                .secondary
                            )
                        }


                        Spacer()


                        Image(
                            systemName:
                                showEntries
                                ?
                                "chevron.up"
                                :
                                "chevron.down"
                        )
                        .font(
                            .caption
                        )
                        .foregroundColor(
                            .secondary
                        )
                    }
                }

                .buttonStyle(
                    .plain
                )


                if showEntries {

                    VStack(
                        spacing: 8
                    ) {

                        ForEach(
                            periodLogs.sorted {
                                $0.date >
                                $1.date
                            }
                        ) { log in

                            Button {

                                selectedLog =
                                    log

                            } label: {

                                HStack(
                                    spacing: 10
                                ) {

                                    VStack(
                                        alignment:
                                            .leading,
                                        spacing: 3
                                    ) {

                                        Text(
                                            fullDateTime(
                                                log.date
                                            )
                                        )
                                        .font(
                                            .subheadline
                                        )
                                        .foregroundColor(
                                            .primary
                                        )


                                        if !log.note
                                            .trimmingCharacters(
                                                in:
                                                    .whitespacesAndNewlines
                                            )
                                            .isEmpty {

                                            Text(
                                                log.note
                                            )
                                            .font(
                                                .caption2
                                            )
                                            .foregroundColor(
                                                .secondary
                                            )
                                            .lineLimit(1)
                                        }
                                    }


                                    Spacer()


                                    Text(
                                        String(
                                            format:
                                                "%.1f kg",
                                            log.weight
                                        )
                                    )
                                    .font(
                                        .subheadline
                                    )
                                    .fontWeight(
                                        .bold
                                    )
                                    .foregroundColor(
                                        .blue
                                    )


                                    Image(
                                        systemName:
                                            "pencil"
                                    )
                                    .font(
                                        .caption
                                    )
                                    .foregroundColor(
                                        .secondary
                                    )


                                    Image(
                                        systemName:
                                            "chevron.right"
                                    )
                                    .font(
                                        .caption2
                                    )
                                    .foregroundColor(
                                        .secondary
                                    )
                                }

                                .padding(10)

                                .background(
                                    Color(
                                        .systemBackground
                                    )
                                )

                                .cornerRadius(10)
                            }

                            .buttonStyle(
                                .plain
                            )

                            .swipeActions(
                                edge:
                                    .trailing
                            ) {

                                Button(
                                    role:
                                        .destructive
                                ) {

                                    WeightLog
                                        .delete(
                                            log
                                        )

                                    refreshAfterChange()

                                } label: {

                                    Label(
                                        "Delete",
                                        systemImage:
                                            "trash"
                                    )
                                }
                            }
                        }
                    }

                    .id(
                        refreshID
                    )
                }
            }
        }

        .padding()

        .background(
            .regularMaterial
        )

        .cornerRadius(16)


        // MARK: Edit / Delete Sheet

        .sheet(
            item:
                $selectedLog
        ) { log in

            WeightLogDetailView(

                log: log,

                onUpdate: {
                    updated in

                    WeightLog
                        .update(
                            updated
                        )

                    refreshAfterChange()
                },

                onDelete: {

                    WeightLog
                        .delete(
                            log
                        )

                    refreshAfterChange()
                }
            )
        }
    }


    // MARK: Refresh

    func refreshAfterChange() {

        selectedPoint = nil

        refreshID =
            UUID()
    }


    // MARK: Point Title

    func pointTitle(
        _ point: TrendPoint
    ) -> String {

        let formatter =
            DateFormatter()


        switch selectedPeriod {

        case .week,
             .month:

            formatter.dateFormat =
                "EEEE, MMM d"

            return formatter.string(
                from:
                    point.date
            )


        case .year:

            formatter.dateFormat =
                "MMM d"


            let end =
                Calendar.current.date(
                    byAdding: .day,
                    value: 6,
                    to: point.date
                )
                ??
                point.date


            return
                "Week of \(formatter.string(from: point.date)) – \(formatter.string(from: end))"
        }
    }


    func fullDateTime(
        _ date: Date
    ) -> String {

        let formatter =
            DateFormatter()

        formatter.dateFormat =
            "MMM d, yyyy · h:mm a"

        return formatter.string(
            from: date
        )
    }
}

#Preview { ContentView() }
