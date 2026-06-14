import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Today", systemImage: "flame.fill") }
            FridgeView()
                .tabItem { Label("Fridge", systemImage: "refrigerator") }
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            FinanceView()
                .tabItem { Label("Finance", systemImage: "dollarsign.circle") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.circle") }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @AppStorage("totalCalories") var totalCalories: Int = 0
    @AppStorage("totalCarbs") var totalCarbs: Double = 0
    @AppStorage("totalProtein") var totalProtein: Double = 0
    @AppStorage("totalFat") var totalFat: Double = 0
    @StateObject private var profile = UserProfile()
    @StateObject private var calendarStore = CalendarStore()
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var financeStore = FinanceStore()
    @StateObject private var eventStore = EventStore()

    @State private var recentMeals: [ManualMeal] = ManualMeal.loadAll()
    @State private var dragOffset: CGFloat = 0
    @State private var showingLogPanel = false
    @State private var showingFinancePanel = false

    var goal: Double { Double(profile.dailyCalorieGoal) }

    var last7DaysWeight: [(date: Date, weight: Double)] {
        (0..<7).compactMap { offset -> (Date, Double)? in
            let date = Calendar.current.date(
                byAdding: .day, value: -offset, to: Date())!
            if let w = calendarStore.weightForDate(date) { return (date, w) }
            return nil
        }.reversed()
    }

    var minWeight: Double { last7DaysWeight.map { $0.weight }.min() ?? 60 }
    var maxWeight: Double { last7DaysWeight.map { $0.weight }.max() ?? 80 }

    var screenWidth: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.width ?? 390
    }

    var upcomingEvents: [CalendarEvent] {
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
        return eventStore.events
            .filter { $0.date >= now && $0.date <= future }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                ScrollView {
                    VStack(spacing: 20) {

                        // Swipe hints
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundColor(.secondary)
                                Text("Finance").font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text("Log Meal").font(.caption2).foregroundColor(.secondary)
                                Image(systemName: "chevron.left")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal).padding(.top, 4)

                        // Calorie ring
                        ZStack {
                            Circle()
                                .stroke(Color.green.opacity(0.15), lineWidth: 16)
                                .frame(width: 160, height: 160)
                            Circle()
                                .trim(from: 0, to: min(
                                    CGFloat(totalCalories) / CGFloat(max(goal, 1)), 1.0))
                                .stroke(
                                    totalCalories > Int(goal) ? Color.red : Color.green,
                                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                                )
                                .frame(width: 160, height: 160)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut, value: totalCalories)
                            VStack(spacing: 4) {
                                Text("\(totalCalories)")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(
                                        totalCalories > Int(goal) ? .red : .primary)
                                Text("of \(Int(goal)) kcal")
                                    .font(.caption).foregroundColor(.secondary)
                                Text(remainingText).font(.caption2)
                                    .foregroundColor(
                                        totalCalories > Int(goal) ? .red : .green)
                            }
                        }
                        .padding(.top, 8)

                        // Macro cards
                        HStack(spacing: 12) {
                            MacroCard(label: "Carbs",
                                      value: "\(Int(totalCarbs))g", color: .orange)
                            MacroCard(label: "Protein",
                                      value: "\(Int(totalProtein))g", color: .green)
                            MacroCard(label: "Fat",
                                      value: "\(Int(totalFat))g", color: .blue)
                        }
                        .padding(.horizontal)

                        // Today's meals
                        let todayMeals = recentMeals.filter {
                            Calendar.current.isDateInToday($0.date)
                        }
                        if !todayMeals.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Today's Meals").font(.headline)
                                    Spacer()
                                    Text("\(todayMeals.count) meals")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                ForEach(todayMeals) { meal in
                                    HStack(spacing: 10) {
                                        Text(meal.emoji)
                                            .font(.system(size: 22))
                                            .frame(width: 36, height: 36)
                                            .background(Color.green.opacity(0.1))
                                            .cornerRadius(8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(meal.name)
                                                .font(.subheadline).fontWeight(.medium)
                                            Text(meal.mealType.emoji + " "
                                                 + meal.mealType.rawValue)
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("\(meal.calories) kcal")
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            .padding().background(.regularMaterial)
                            .cornerRadius(16).padding(.horizontal)
                        }

                        // Upcoming events
                        if !upcomingEvents.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "calendar")
                                        .foregroundColor(.purple)
                                    Text("Upcoming Events").font(.headline)
                                    Spacer()
                                }
                                ForEach(upcomingEvents) { event in
                                    HStack(spacing: 10) {
                                        Text(event.emoji)
                                            .font(.system(size: 20))
                                            .frame(width: 34, height: 34)
                                            .background(Color.purple.opacity(0.1))
                                            .cornerRadius(8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.title)
                                                .font(.subheadline).fontWeight(.medium)
                                            Text(relativeDate(event.date))
                                                .font(.caption2).foregroundColor(.purple)
                                        }
                                        Spacer()
                                        Text(timeString(event.date))
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding().background(.regularMaterial)
                            .cornerRadius(16).padding(.horizontal)
                        }

                        // Finance summary
                        MonthFinanceSummary(store: financeStore)
                            .padding(.horizontal)

                        // Weight trend
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Weight Trend").font(.headline)
                                Spacer()
                                if let latest = last7DaysWeight.last {
                                    Text(String(format: "%.1f kg", latest.weight))
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                }
                            }

                            if last7DaysWeight.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.system(size: 36))
                                        .foregroundColor(.secondary.opacity(0.4))
                                    Text("No weight logged yet")
                                        .font(.subheadline).foregroundColor(.secondary)
                                    Text("Log your weight in the Calendar tab")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 20)
                            } else {
                                GeometryReader { geo in
                                    let w = geo.size.width
                                    let h = geo.size.height
                                    let range = maxWeight - minWeight == 0
                                        ? 1 : maxWeight - minWeight
                                    let pad: Double = 2
                                    ZStack {
                                        ForEach(0..<4) { i in
                                            let y = h * CGFloat(i) / 3
                                            Path { path in
                                                path.move(to: CGPoint(x: 0, y: y))
                                                path.addLine(to: CGPoint(x: w, y: y))
                                            }
                                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                                        }
                                        if last7DaysWeight.count > 1 {
                                            Path { path in
                                                for (i, entry) in last7DaysWeight.enumerated() {
                                                    let x = w * CGFloat(i)
                                                        / CGFloat(last7DaysWeight.count - 1)
                                                    let n = (entry.weight - minWeight + pad)
                                                        / (range + pad * 2)
                                                    let y = h * CGFloat(1 - n)
                                                    if i == 0 {
                                                        path.move(to: CGPoint(x: x, y: y))
                                                    } else {
                                                        path.addLine(to: CGPoint(x: x, y: y))
                                                    }
                                                }
                                            }
                                            .stroke(Color.blue, style: StrokeStyle(
                                                lineWidth: 2.5, lineCap: .round,
                                                lineJoin: .round))
                                        }
                                        ForEach(0..<last7DaysWeight.count, id: \.self) { i in
                                            let entry = last7DaysWeight[i]
                                            let x = last7DaysWeight.count == 1
                                                ? w / 2
                                                : w * CGFloat(i)
                                                    / CGFloat(last7DaysWeight.count - 1)
                                            let n = (entry.weight - minWeight + pad)
                                                / (range + pad * 2)
                                            let y = h * CGFloat(1 - n)
                                            Circle().fill(Color.blue)
                                                .frame(width: 8, height: 8)
                                                .position(x: x, y: y)
                                            Text(String(format: "%.1f", entry.weight))
                                                .font(.system(size: 9)).foregroundColor(.blue)
                                                .position(x: x, y: max(y - 14, 10))
                                            Text(dayLabel(entry.date))
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                                .position(x: x, y: h + 12)
                                        }
                                    }
                                }
                                .frame(height: 120).padding(.bottom, 20)

                                if last7DaysWeight.count >= 2 {
                                    let first = last7DaysWeight.first!.weight
                                    let last = last7DaysWeight.last!.weight
                                    let diff = last - first
                                    HStack(spacing: 6) {
                                        Image(systemName: diff < 0
                                              ? "arrow.down.circle.fill"
                                              : diff > 0
                                              ? "arrow.up.circle.fill"
                                              : "minus.circle.fill")
                                            .foregroundColor(
                                                diff < 0 ? .green
                                                : diff > 0 ? .red : .secondary)
                                        Text(diff < 0
                                             ? String(format: "%.1f kg lost this week 🎉",
                                                      abs(diff))
                                             : diff > 0
                                             ? String(format: "%.1f kg gained this week", diff)
                                             : "Weight stable this week")
                                            .font(.caption)
                                            .foregroundColor(
                                                diff < 0 ? .green
                                                : diff > 0 ? .red : .secondary)
                                    }
                                }
                            }
                        }
                        .padding().background(.regularMaterial)
                        .cornerRadius(16).padding(.horizontal)

                        // Apple Health card
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "heart.fill").foregroundColor(.red)
                                Text("Apple Health").font(.headline)
                                Spacer()
                                if !healthKit.isAuthorized {
                                    Button("Connect") {
                                        healthKit.requestAuthorization()
                                    }
                                    .font(.subheadline).foregroundColor(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.red).cornerRadius(10)
                                } else {
                                    Button(action: { healthKit.fetchAll() }) {
                                        Image(systemName: "arrow.clockwise")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            if let error = healthKit.errorMessage {
                                Text(error).font(.caption).foregroundColor(.red)
                            }

                            if healthKit.isAuthorized {
                                VStack(spacing: 6) {
                                    HStack {
                                        Label("\(healthKit.steps) steps",
                                              systemImage: "figure.walk")
                                            .font(.subheadline)
                                            .foregroundColor(
                                                healthKit.stepsGoalMet ? .green : .primary)
                                        Spacer()
                                        Text(String(format: "%.2f km",
                                                    healthKit.distanceKm))
                                            .font(.caption).foregroundColor(.secondary)
                                        Text(healthKit.stepsGoalMet ? "✅" : "/ 10,000")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    ProgressView(value: healthKit.stepsProgress)
                                        .tint(healthKit.stepsGoalMet ? .green : .orange)
                                }

                                Divider()

                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    spacing: 12
                                ) {
                                    HealthStatCard(
                                        icon: "moon.zzz.fill", label: "Sleep",
                                        value: healthKit.sleepFormatted,
                                        color: .purple, goalMet: healthKit.sleepGoalMet)
                                    HealthStatCard(
                                        icon: "flame.fill", label: "Active Cal",
                                        value: "\(Int(healthKit.activeCalories)) kcal",
                                        color: .orange,
                                        goalMet: healthKit.activeCalories > 300)
                                    if healthKit.heartRate > 0 {
                                        HealthStatCard(
                                            icon: "heart.fill", label: "Heart Rate",
                                            value: "\(Int(healthKit.heartRate)) bpm",
                                            color: .red,
                                            goalMet: healthKit.heartRate < 100)
                                    }
                                    HealthStatCard(
                                        icon: "fork.knife", label: "Net Calories",
                                        value: "\(Int(Double(totalCalories) - healthKit.activeCalories)) kcal",
                                        color: .green, goalMet: true)
                                }

                                // Period status
                                if healthKit.isPeriodDay {
                                    Divider()
                                    Label("Period day today",
                                          systemImage: "circle.fill")
                                        .font(.caption).foregroundColor(.pink)
                                } else if let days = healthKit.daysUntilNextPeriod,
                                          days <= 5 {
                                    Divider()
                                    Label(
                                        "Period expected in \(days) day\(days == 1 ? "" : "s")",
                                        systemImage: "calendar.badge.clock")
                                        .font(.caption).foregroundColor(.pink)
                                }
                            } else {
                                Text("Connect Apple Health to see your steps, sleep and activity data automatically")
                                    .font(.caption).foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                        }
                        .padding().background(.regularMaterial)
                        .cornerRadius(16).padding(.horizontal)

                        Button(action: resetDay) {
                            Label("Reset Today's Calories",
                                  systemImage: "arrow.counterclockwise")
                                .font(.footnote).foregroundColor(.red)
                        }
                        .padding(.bottom, 24)
                    }
                }
                .offset(x: dragOffset)
                .refreshable {
                    healthKit.fetchAll()
                    recentMeals = ManualMeal.loadAll()
                    financeStore.refreshAll()
                }

                // Dim overlay
                if showingLogPanel || showingFinancePanel {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35)) {
                                showingLogPanel = false
                                showingFinancePanel = false
                                dragOffset = 0
                            }
                        }
                }

                // Log Meal panel (right)
                if showingLogPanel {
                    HStack(spacing: 0) {
                        Spacer()
                        LogMealPanel(
                            onDismiss: {
                                withAnimation(.spring(response: 0.35)) {
                                    showingLogPanel = false
                                    dragOffset = 0
                                }
                                recentMeals = ManualMeal.loadAll()
                            },
                            totalCalories: $totalCalories,
                            totalCarbs: $totalCarbs,
                            totalProtein: $totalProtein,
                            totalFat: $totalFat
                        )
                        .frame(width: screenWidth * 0.88)
                        .transition(.move(edge: .trailing))
                    }
                }

                // Finance panel (left)
                if showingFinancePanel {
                    HStack(spacing: 0) {
                        FinanceQuickPanel(store: financeStore, onDismiss: {
                            withAnimation(.spring(response: 0.35)) {
                                showingFinancePanel = false
                                dragOffset = 0
                            }
                        })
                        .frame(width: screenWidth * 0.88)
                        .transition(.move(edge: .leading))
                        Spacer()
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !showingLogPanel && !showingFinancePanel {
                            if value.translation.width < 0 {
                                dragOffset = max(value.translation.width,
                                                 -screenWidth * 0.88)
                            } else if value.translation.width > 0 {
                                dragOffset = min(value.translation.width,
                                                 screenWidth * 0.88)
                            }
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < -60 && !showingLogPanel {
                            withAnimation(.spring(response: 0.35)) {
                                showingLogPanel = true; dragOffset = 0
                            }
                        } else if value.translation.width > 60 && !showingFinancePanel {
                            withAnimation(.spring(response: 0.35)) {
                                showingFinancePanel = true; dragOffset = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.35)) { dragOffset = 0 }
                        }
                    }
            )
            .navigationTitle("Kelly Life")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        withAnimation(.spring(response: 0.35)) {
                            showingFinancePanel = true
                        }
                    }) {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.green).font(.title3)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        withAnimation(.spring(response: 0.35)) {
                            showingLogPanel = true
                        }
                    }) {
                        Image(systemName: "fork.knife.circle.fill")
                            .foregroundColor(.green).font(.title3)
                    }
                }
            }
        }
        .onAppear {
            recentMeals = ManualMeal.loadAll()
            if !healthKit.isAuthorized { healthKit.requestAuthorization() }
        }
    }

    // MARK: - Helpers

    var remainingText: String {
        let remaining = Int(goal) - totalCalories
        if remaining > 0 { return "\(remaining) kcal left" }
        if remaining == 0 { return "Goal reached! 🎯" }
        return "\(abs(remaining)) kcal over"
    }

    func dayLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f.string(from: date)
    }

    func relativeDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return "In \(days) days"
    }

    func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: date)
    }

    func resetDay() {
        totalCalories = 0; totalCarbs = 0; totalProtein = 0; totalFat = 0
        recentMeals = ManualMeal.loadAll()
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

    var monthName: String {
        let f = DateFormatter(); f.dateFormat = "MMMM"; return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack {
                Image(systemName: "dollarsign.circle.fill").foregroundColor(.green)
                Text("\(monthName) Overview").font(.headline)
                Spacer()
                if income > 0 {
                    Text(String(format: "+$%.2f income", income))
                        .font(.caption).foregroundColor(.green)
                }
            }

            // Stock section — today gain/loss + overall only, no per-ticker
            if !store.stockHoldings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "chart.bar.fill").foregroundColor(.blue)
                        Text("Stock Portfolio").font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Text(String(format: "$%.2f", store.totalStockValue))
                            .font(.subheadline).fontWeight(.bold)
                    }

                    HStack(spacing: 12) {
                        // Today's gain/loss
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.isWeekend ? "vs Last Friday" : "Today")
                                .font(.caption2).foregroundColor(.secondary)
                            Text(
                                (store.todayStockGainLoss >= 0 ? "+" : "") +
                                String(format: "$%.2f", store.todayStockGainLoss)
                            )
                            .font(.title3).fontWeight(.bold)
                            .foregroundColor(store.todayStockGainLoss >= 0 ? .green : .red)
                            Text(String(format: "%.2f%%",
                                        store.todayStockGainLossPercent))
                                .font(.caption2)
                                .foregroundColor(
                                    store.todayStockGainLoss >= 0 ? .green : .red)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(
                            store.todayStockGainLoss >= 0
                            ? Color.green.opacity(0.08)
                            : Color.red.opacity(0.08))
                        .cornerRadius(10)

                        // Overall gain/loss
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Overall").font(.caption2).foregroundColor(.secondary)
                            Text(
                                (store.totalStockGainLoss >= 0 ? "+" : "") +
                                String(format: "$%.2f", store.totalStockGainLoss)
                            )
                            .font(.title3).fontWeight(.bold)
                            .foregroundColor(store.totalStockGainLoss >= 0 ? .green : .red)
                            Text(String(format: "%.2f%%",
                                        store.totalStockGainLossPercent))
                                .font(.caption2)
                                .foregroundColor(
                                    store.totalStockGainLoss >= 0 ? .green : .red)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(
                            store.totalStockGainLoss >= 0
                            ? Color.green.opacity(0.08)
                            : Color.red.opacity(0.08))
                        .cornerRadius(10)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
            }

            // Spending ring
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.green.opacity(0.15), lineWidth: 10)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: budget > 0
                              ? CGFloat(min(spent / budget, 1.0)) : 0)
                        .stroke(isOverBudget ? Color.red : Color.green,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(budget > 0
                             ? "\(Int(min(spent / budget * 100, 999)))%" : "—")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isOverBudget ? .red : .primary)
                        Text("used").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("Spent").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", spent))
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.red)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Budget").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(budget > 0 ? String(format: "$%.2f", budget) : "Not set")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.green)
                    }
                    Divider()
                    HStack(spacing: 6) {
                        Circle().fill(isOverBudget ? Color.red : Color.blue)
                            .frame(width: 8, height: 8)
                        Text(isOverBudget ? "Over by" : "Left")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(budget > 0 ? String(format: "$%.2f", abs(remaining)) : "—")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(isOverBudget ? .red : .blue)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if budget > 0 {
                ProgressView(value: min(spent / budget, 1.0))
                    .tint(isOverBudget ? .red
                          : spent / budget > 0.8 ? .orange : .green)
                Label(
                    isOverBudget
                        ? String(format: "Over monthly budget by $%.2f", abs(remaining))
                        : spent / budget > 0.8
                        ? String(format: "Almost at budget — $%.2f left", remaining)
                        : String(format: "$%.2f remaining this month", remaining),
                    systemImage: isOverBudget
                        ? "exclamationmark.triangle.fill"
                        : spent / budget > 0.8
                        ? "exclamationmark.circle.fill"
                        : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundColor(
                    isOverBudget ? .red : spent / budget > 0.8 ? .orange : .green)
            } else {
                Text("Set a monthly budget in Finance to track spending")
                    .font(.caption).foregroundColor(.secondary)
            }

            // CD maturing soon
            let maturingSoon = store.cdAccounts.filter {
                $0.daysUntilMaturity <= 30 && !$0.isMatured
            }
            if !maturingSoon.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("CDs Maturing Soon")
                        .font(.caption).foregroundColor(.secondary)
                    ForEach(maturingSoon) { cd in
                        HStack {
                            Image(systemName: "banknote").foregroundColor(.orange)
                            Text(cd.bankName)
                                .font(.caption).foregroundColor(.secondary)
                            Text(String(format: "$%.2f", cd.principal))
                                .font(.caption).fontWeight(.medium)
                            Spacer()
                            Text(cd.statusText)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(cd.statusColor)
                        }
                    }
                }
            }
        }
        .padding().background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Finance Quick Panel

struct FinanceQuickPanel: View {
    @ObservedObject var store: FinanceStore
    let onDismiss: () -> Void
    @State private var showAddTransaction = false

    var recentTransactions: [Transaction] {
        store.transactions.sorted { $0.date > $1.date }.prefix(10).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundColor(.secondary)
                }
                Spacer()
                Text("Finance").font(.headline)
                Spacer()
                Button(action: { showAddTransaction = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2).foregroundColor(.green)
                }
            }
            .padding().background(.regularMaterial)

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(String(format: "$%.2f", store.totalIncome(for: .month)))
                        .font(.title3).fontWeight(.bold).foregroundColor(.green)
                    Text("Income").font(.caption2).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity)
                Divider().frame(height: 40)
                VStack(spacing: 4) {
                    Text(String(format: "$%.2f", store.totalExpense(for: .month)))
                        .font(.title3).fontWeight(.bold).foregroundColor(.red)
                    Text("Spent").font(.caption2).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity)
                Divider().frame(height: 40)
                VStack(spacing: 4) {
                    let rem = store.monthBudgetRemaining()
                    Text(store.totalMonthlyBudget > 0
                         ? String(format: "$%.2f", rem) : "—")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(rem < 0 ? .red : .blue)
                    Text("Left").font(.caption2).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity)
            }
            .padding().background(.regularMaterial)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    if recentTransactions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "dollarsign.circle")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary.opacity(0.3))
                            Text("No transactions yet")
                                .font(.subheadline).foregroundColor(.secondary)
                        }.padding(.vertical, 40)
                    } else {
                        HStack {
                            Text("Recent Transactions").font(.headline)
                            Spacer()
                        }.padding(.horizontal).padding(.top, 4)
                        ForEach(recentTransactions) { t in
                            TransactionRow(
                                transaction: t,
                                onDelete: {
                                    store.transactions.removeAll { $0.id == t.id }
                                }
                            )
                            .padding(.horizontal)
                        }
                    }
                }.padding(.vertical, 12)
            }
            .refreshable { store.refreshAll() }

            Button(action: { showAddTransaction = true }) {
                Label("Add Transaction", systemImage: "plus.circle.fill")
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.green).cornerRadius(14)
                    .padding(.horizontal).padding(.bottom, 16)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 5, y: 0)
        .sheet(isPresented: $showAddTransaction) { AddTransactionView(store: store) }
    }
}

// MARK: - Log Meal Panel

struct LogMealPanel: View {
    let onDismiss: () -> Void
    @Binding var totalCalories: Int
    @Binding var totalCarbs: Double
    @Binding var totalProtein: Double
    @Binding var totalFat: Double
    @State private var recentMeals: [ManualMeal] = ManualMeal.loadAll()
    @State private var showAddMeal = false

    var todayMeals: [ManualMeal] {
        recentMeals.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundColor(.secondary)
                }
                Spacer()
                Text("Meal Log").font(.headline)
                Spacer()
                Button(action: { showAddMeal = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2).foregroundColor(.green)
                }
            }
            .padding().background(.regularMaterial)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(totalCalories)").font(.title2).fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("kcal").font(.caption2).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                VStack(spacing: 2) {
                    Text("\(todayMeals.count)").font(.title2).fontWeight(.bold)
                    Text("meals").font(.caption2).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                VStack(spacing: 2) {
                    Text("\(Int(totalCarbs))g").font(.title2).fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("carbs").font(.caption2).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity)
                Divider().frame(height: 36)
                VStack(spacing: 2) {
                    Text("\(Int(totalProtein))g").font(.title2).fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("protein").font(.caption2).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity)
            }
            .padding().background(.regularMaterial)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    if todayMeals.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "fork.knife.circle")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary.opacity(0.3))
                            Text("No meals logged today")
                                .font(.subheadline).foregroundColor(.secondary)
                            Text("Check 薄荷健康 for calories\nthen add them here")
                                .font(.caption).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }.padding(.vertical, 40)
                    } else {
                        ForEach(todayMeals) { meal in
                            MealLogRow(meal: meal, onDelete: { deleteMeal(meal) })
                                .padding(.horizontal)
                        }
                    }

                    let pastMeals = recentMeals.filter {
                        !Calendar.current.isDateInToday($0.date)
                    }
                    if !pastMeals.isEmpty {
                        HStack {
                            Text("Earlier").font(.caption).foregroundColor(.secondary)
                            Spacer()
                        }.padding(.horizontal).padding(.top, 8)
                        ForEach(pastMeals.prefix(8)) { meal in
                            MealLogRow(meal: meal,
                                       onDelete: { deleteMeal(meal) },
                                       showDate: true)
                                .padding(.horizontal)
                        }
                    }
                }.padding(.vertical, 12)
            }
            .refreshable { recentMeals = ManualMeal.loadAll() }

            Button(action: { showAddMeal = true }) {
                Label("Log a Meal", systemImage: "plus.circle.fill")
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.green).cornerRadius(14)
                    .padding(.horizontal).padding(.bottom, 16)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, x: -5, y: 0)
        .sheet(isPresented: $showAddMeal, onDismiss: {
            recentMeals = ManualMeal.loadAll()
        }) {
            ManualMealEntryView { meal in
                totalCalories += meal.calories
                totalCarbs += meal.carbs
                totalProtein += meal.protein
                totalFat += meal.fat
                ManualMeal.save(meal)
                recentMeals = ManualMeal.loadAll()
            }
        }
    }

    func deleteMeal(_ meal: ManualMeal) {
        totalCalories = max(0, totalCalories - meal.calories)
        totalCarbs = max(0, totalCarbs - meal.carbs)
        totalProtein = max(0, totalProtein - meal.protein)
        totalFat = max(0, totalFat - meal.fat)
        ManualMeal.delete(meal)
        recentMeals = ManualMeal.loadAll()
    }
}

// MARK: - Macro Card

struct MacroCard: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 6) {
            Text(value).font(.title2).fontWeight(.semibold).foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding()
        .background(.regularMaterial).cornerRadius(12)
    }
}

// MARK: - Health Stat Card

struct HealthStatCard: View {
    let icon: String; let label: String
    let value: String; let color: Color; let goalMet: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
                .font(.system(size: 20)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.subheadline).fontWeight(.semibold)
                Text(label).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if goalMet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green).font(.caption)
            }
        }
        .padding(10).background(color.opacity(0.08)).cornerRadius(10)
    }
}

// MARK: - Manual Meal Model

struct ManualMeal: Identifiable, Codable {
    var id = UUID()
    var name: String
    var mealType: MealType
    var calories: Int
    var carbs: Double
    var protein: Double
    var fat: Double
    var date: Date = Date()
    var emoji: String

    enum MealType: String, Codable, CaseIterable {
        case breakfast = "Breakfast"; case lunch = "Lunch"
        case dinner = "Dinner"; case snack = "Snack"; case drink = "Drink"
        var emoji: String {
            switch self {
            case .breakfast: return "🌅"; case .lunch: return "☀️"
            case .dinner: return "🌙"; case .snack: return "🍪"; case .drink: return "🥤"
            }
        }
    }

    static func loadAll() -> [ManualMeal] {
        guard let data = UserDefaults.standard.data(forKey: "manualMeals"),
              let meals = try? JSONDecoder().decode([ManualMeal].self, from: data)
        else { return [] }
        return meals.sorted { $0.date > $1.date }
    }
    static func save(_ meal: ManualMeal) {
        var all = loadAll(); all.append(meal)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: "manualMeals")
        }
    }
    static func delete(_ meal: ManualMeal) {
        var all = loadAll(); all.removeAll { $0.id == meal.id }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: "manualMeals")
        }
    }
}

// MARK: - Meal Log Row

struct MealLogRow: View {
    let meal: ManualMeal; let onDelete: () -> Void; var showDate: Bool = false
    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = showDate ? "M/d HH:mm" : "HH:mm"
        return f.string(from: meal.date)
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(meal.emoji).font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.1)).cornerRadius(10)
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name).font(.subheadline).fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(meal.mealType.emoji + " " + meal.mealType.rawValue)
                        .font(.caption2).foregroundColor(.secondary)
                    Text("·").foregroundColor(.secondary)
                    Text(timeString).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(meal.calories) kcal")
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.green)
                HStack(spacing: 4) {
                    Text("C:\(Int(meal.carbs))g").font(.caption2).foregroundColor(.orange)
                    Text("P:\(Int(meal.protein))g").font(.caption2).foregroundColor(.green)
                    Text("F:\(Int(meal.fat))g").font(.caption2).foregroundColor(.blue)
                }
            }
        }
        .padding().background(.regularMaterial).cornerRadius(12)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Manual Meal Entry View

struct ManualMealEntryView: View {
    let onSave: (ManualMeal) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var mealType: ManualMeal.MealType = .lunch
    @State private var calories = ""
    @State private var carbs = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var selectedEmoji = "🍚"

    let commonEmojis = [
        "🍚","🍜","🥩","🍗","🥗","🍱","🥟","🍛","🍝","🥘",
        "🍲","🍣","🥙","🌮","🥪","🍔","🍕","🥞","🥚","🍳",
        "🥣","🍦","🧁","🍰","🍪","🥤","☕","🧃","🍵","🥛"
    ]

    var estimatedMacros: (carbs: Double, protein: Double, fat: Double) {
        guard let cal = Double(calories) else { return (0, 0, 0) }
        return (carbs: (cal * 0.5) / 4,
                protein: (cal * 0.25) / 4,
                fat: (cal * 0.25) / 9)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("What did you eat?") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonEmojis, id: \.self) { e in
                                Text(e).font(.system(size: 28)).padding(6)
                                    .background(selectedEmoji == e
                                                ? Color.green.opacity(0.2) : Color.clear)
                                    .cornerRadius(8).onTapGesture { selectedEmoji = e }
                            }
                        }.padding(.vertical, 4)
                    }
                    TextField("Food name (e.g. 麻婆豆腐, Rice)", text: $name)
                    Picker("Meal type", selection: $mealType) {
                        ForEach(ManualMeal.MealType.allCases, id: \.self) {
                            Text($0.emoji + " " + $0.rawValue).tag($0)
                        }
                    }
                }
                Section("Calories (from 薄荷健康)") {
                    HStack {
                        TextField("e.g. 450", text: $calories).keyboardType(.numberPad)
                        Text("kcal").foregroundColor(.secondary)
                    }
                    if !calories.isEmpty && carbs.isEmpty
                        && protein.isEmpty && fat.isEmpty {
                        Button(action: {
                            let est = estimatedMacros
                            carbs = String(format: "%.0f", est.carbs)
                            protein = String(format: "%.0f", est.protein)
                            fat = String(format: "%.0f", est.fat)
                        }) {
                            Label("Auto-estimate macros", systemImage: "wand.and.stars")
                                .font(.caption).foregroundColor(.green)
                        }
                    }
                }
                Section("Macros (optional)") {
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
                Section {
                    Text("Tip: Check calories in 薄荷健康 first.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Log Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard !name.isEmpty, let cal = Int(calories) else { return }
                        let est = estimatedMacros
                        let meal = ManualMeal(
                            name: name, mealType: mealType, calories: cal,
                            carbs: Double(carbs) ?? est.carbs,
                            protein: Double(protein) ?? est.protein,
                            fat: Double(fat) ?? est.fat,
                            emoji: selectedEmoji
                        )
                        onSave(meal); dismiss()
                    }
                    .fontWeight(.bold).disabled(name.isEmpty || calories.isEmpty)
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

#Preview { ContentView() }
