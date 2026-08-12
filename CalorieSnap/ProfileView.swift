import SwiftUI
import Combine

// MARK: - User Profile

class UserProfile: ObservableObject {
    @AppStorage("dailyCalorieGoal") var dailyCalorieGoal: Int = 1683
    @AppStorage("weeklyWeightGoal") var weeklyWeightGoal: Double = 0.5
    @AppStorage("userWeight") var userWeight: Double = 71
    @AppStorage("userHeight") var userHeight: Double = 160
    @AppStorage("userAge") var userAge: Int = 25
    @AppStorage("userName") var userName: String = "Kelly"
}

// MARK: - Wish Models

enum WishCategory: String, Codable, CaseIterable {
    case personal = "Personal"; case travel = "Travel"; case career = "Career"
    case health = "Health"; case relationship = "Relationship"; case finance = "Finance"
    case learn = "Learn"; case other = "Other"
    var emoji: String {
        switch self {
        case .personal: return "🌸"; case .travel: return "✈️"; case .career: return "💼"
        case .health: return "💪"; case .relationship: return "💕"; case .finance: return "💰"
        case .learn: return "📚"; case .other: return "⭐"
        }
    }
    var color: Color {
        switch self {
        case .personal: return .pink; case .travel: return .blue; case .career: return .purple
        case .health: return .green; case .relationship: return .red; case .finance: return .orange
        case .learn: return .teal; case .other: return .secondary
        }
    }
}

// Completion note entry — recorded each time user checks progress
struct WishProgressEntry: Identifiable, Codable {
    var id = UUID()
    var note: String
    var date: Date
    var isCompletion: Bool  // true = fully done, false = partial progress
}

struct WishItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var note: String
    var emoji: String
    var isDone: Bool
    var category: WishCategory
    var createdAt: Date
    var completedAt: Date?
    var targetYear: Int
    var progressEntries: [WishProgressEntry]   // journal of partial completions

    // Convenience: latest progress note
    var latestProgressNote: String? {
        progressEntries.sorted { $0.date > $1.date }.first?.note
    }
    var progressCount: Int { progressEntries.count }

    init(id: UUID = UUID(), title: String, note: String = "", emoji: String = "⭐",
         isDone: Bool = false, category: WishCategory = .personal,
         targetYear: Int = Calendar.current.component(.year, from: Date())) {
        self.id = id; self.title = title; self.note = note; self.emoji = emoji
        self.isDone = isDone; self.category = category
        self.createdAt = Date(); self.targetYear = targetYear
        self.progressEntries = []
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "⭐"
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        category = try c.decodeIfPresent(WishCategory.self, forKey: .category) ?? .other
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        targetYear = try c.decodeIfPresent(Int.self, forKey: .targetYear) ?? Calendar.current.component(.year, from: Date())
        progressEntries = try c.decodeIfPresent([WishProgressEntry].self, forKey: .progressEntries) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id, title, note, emoji, isDone, category, createdAt, completedAt, targetYear, progressEntries
    }
}

// MARK: - Achievement Models

enum AchievementCategory: String, Codable, CaseIterable {
    case personal = "Personal"; case career = "Career"; case health = "Health"
    case travel = "Travel"; case relationship = "Relationship"; case learn = "Learn"
    case milestone = "Milestone"; case other = "Other"
    var emoji: String {
        switch self {
        case .personal: return "🌸"; case .career: return "💼"; case .health: return "💪"
        case .travel: return "✈️"; case .relationship: return "💕"; case .learn: return "📚"
        case .milestone: return "🏆"; case .other: return "⭐"
        }
    }
    var color: Color {
        switch self {
        case .personal: return .pink; case .career: return .purple; case .health: return .green
        case .travel: return .blue; case .relationship: return .red; case .learn: return .teal
        case .milestone: return .orange; case .other: return .secondary
        }
    }
}

struct AchievementItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var note: String
    var emoji: String
    var category: AchievementCategory
    var date: Date
    var createdAt: Date
    var journalEntries: [WishProgressEntry]  // extra notes added later

    init(id: UUID = UUID(), title: String, note: String = "", emoji: String = "🏆",
         category: AchievementCategory = .milestone, date: Date = Date()) {
        self.id = id; self.title = title; self.note = note; self.emoji = emoji
        self.category = category; self.date = date; self.createdAt = Date()
        self.journalEntries = []
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🏆"
        category = try c.decodeIfPresent(AchievementCategory.self, forKey: .category) ?? .milestone
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        journalEntries = try c.decodeIfPresent([WishProgressEntry].self, forKey: .journalEntries) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id, title, note, emoji, category, date, createdAt, journalEntries
    }

    var yearAchieved: Int { Calendar.current.component(.year, from: date) }
    var dateLabel: String { let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date) }
}

// MARK: - Store

class WishStore: ObservableObject {
    @Published var wishes: [WishItem] = [] { didSet { save() } }
    @Published var achievements: [AchievementItem] = [] { didSet { saveAchievements() } }

    init() { load(); loadAchievements() }

    func save() {
        if let d = try? JSONEncoder().encode(wishes) { UserDefaults.standard.set(d, forKey: "wishItems_v2") }
    }
    func load() {
        guard let d = UserDefaults.standard.data(forKey: "wishItems_v2"),
              let decoded = try? JSONDecoder().decode([WishItem].self, from: d) else { return }
        wishes = decoded
    }
    func saveAchievements() {
        if let d = try? JSONEncoder().encode(achievements) { UserDefaults.standard.set(d, forKey: "achievementItems_v1") }
    }
    func loadAchievements() {
        guard let d = UserDefaults.standard.data(forKey: "achievementItems_v1"),
              let decoded = try? JSONDecoder().decode([AchievementItem].self, from: d) else { return }
        achievements = decoded
    }

    // Toggle full completion
    func toggle(_ item: WishItem) {
        if let i = wishes.firstIndex(where: { $0.id == item.id }) {
            wishes[i].isDone.toggle()
            wishes[i].completedAt = wishes[i].isDone ? Date() : nil
        }
    }

    // Add a progress entry (partial or full completion note)
    func addProgressEntry(to wishId: UUID, note: String, isCompletion: Bool) {
        if let i = wishes.firstIndex(where: { $0.id == wishId }) {
            let entry = WishProgressEntry(note: note, date: Date(), isCompletion: isCompletion)
            wishes[i].progressEntries.append(entry)
            if isCompletion {
                wishes[i].isDone = true
                wishes[i].completedAt = Date()
            }
        }
    }

    // Add a journal note to an achievement
    func addJournalEntry(to achievementId: UUID, note: String) {
        if let i = achievements.firstIndex(where: { $0.id == achievementId }) {
            let entry = WishProgressEntry(note: note, date: Date(), isCompletion: false)
            achievements[i].journalEntries.append(entry)
        }
    }

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var thisYearWishes: [WishItem] { wishes.filter { $0.targetYear == currentYear } }
    func achievementsForYear(_ year: Int) -> [AchievementItem] {
        achievements.filter { $0.yearAchieved == year }.sorted { $0.date > $1.date }
    }
    var achievementYears: [Int] { Array(Set(achievements.map { $0.yearAchieved })).sorted(by: >) }
}

// MARK: - Profile View

struct ProfileView: View {
    @StateObject private var wishStore = WishStore()
    @AppStorage("userName") var userName: String = "Kelly"
    @AppStorage("userAge") var userAge: Int = 25
    @AppStorage("userHeight") var userHeight: Double = 160
    @AppStorage("userWeight") var userWeight: Double = 71
    @AppStorage("dailyCalorieGoal") var dailyCalorieGoal: Int = 1683
    @AppStorage("weeklyWeightGoal") var weeklyWeightGoal: Double = 0.5

    @State private var showAddWish = false
    @State private var editingWish: WishItem? = nil
    @State private var detailWish: WishItem? = nil
    @State private var showAddAchievement = false
    @State private var editingAchievement: AchievementItem? = nil
    @State private var detailAchievement: AchievementItem? = nil
    @State private var showCompletedWishes = false
    @State private var selectedWishCategory: WishCategory? = nil
    @State private var selectedAchievementCategory: AchievementCategory? = nil
    @State private var isEditingProfile = false
    @State private var selectedTab: ProfileTab = .wishes

    enum ProfileTab { case wishes; case achievements }

    var pendingWishes: [WishItem] {
        var base = wishStore.thisYearWishes.filter { !$0.isDone }
        if let cat = selectedWishCategory { base = base.filter { $0.category == cat } }
        return base
    }
    var doneWishes: [WishItem] {
        var base = wishStore.thisYearWishes.filter { $0.isDone }
        if let cat = selectedWishCategory { base = base.filter { $0.category == cat } }
        return base
    }
    var wishProgress: Double {
        guard !wishStore.thisYearWishes.isEmpty else { return 0 }
        return Double(wishStore.thisYearWishes.filter { $0.isDone }.count) / Double(wishStore.thisYearWishes.count)
    }
    var filteredAchievements: [AchievementItem] {
        var base = wishStore.achievements
        if let cat = selectedAchievementCategory { base = base.filter { $0.category == cat } }
        return base.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // Profile card
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(userName).font(.title2).fontWeight(.bold)
                                HStack(spacing: 12) {
                                    Label("\(userAge) yrs", systemImage: "person.fill").font(.caption).foregroundColor(.secondary)
                                    Label(String(format: "%.0f cm", userHeight), systemImage: "ruler").font(.caption).foregroundColor(.secondary)
                                    Label(String(format: "%.1f kg", userWeight), systemImage: "scalemass").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(action: { isEditingProfile = true }) {
                                Image(systemName: "pencil.circle.fill").font(.title2).foregroundColor(.green)
                            }
                        }
                        Divider()
                        HStack(spacing: 0) {
                            VStack(spacing: 4) {
                                Text("\(dailyCalorieGoal)").font(.title3).fontWeight(.bold).foregroundColor(.green)
                                Text("kcal/day").font(.caption2).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity)
                            Divider().frame(height: 36)
                            VStack(spacing: 4) {
                                Text(String(format: "%.1f kg/wk", weeklyWeightGoal)).font(.title3).fontWeight(.bold).foregroundColor(.blue)
                                Text("weight goal").font(.caption2).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    .padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)

                    // Tab picker
                    Picker("Tab", selection: $selectedTab) {
                        Text("⭐ \(String(wishStore.currentYear)) Wishes").tag(ProfileTab.wishes)
                        Text("🏆 Achievements").tag(ProfileTab.achievements)
                    }
                    .pickerStyle(.segmented).padding(.horizontal)

                    if selectedTab == .wishes { wishSection } else { achievementSection }

                    VStack(spacing: 4) {
                        Text("Kelly Life").font(.caption).foregroundColor(.secondary)
                        Text("Built with ❤️ for healthy living").font(.caption2).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity).padding(.bottom, 24)
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if selectedTab == .wishes { showAddWish = true }
                        else { showAddAchievement = true }
                    }) { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddWish) { AddEditWishView(store: wishStore) }
            .sheet(item: $editingWish) { wish in AddEditWishView(store: wishStore, existing: wish) }
            .sheet(item: $detailWish) { wish in WishDetailView(wish: wish, store: wishStore) }
            .sheet(isPresented: $showAddAchievement) { AddEditAchievementView(store: wishStore) }
            .sheet(item: $editingAchievement) { item in AddEditAchievementView(store: wishStore, existing: item) }
            .sheet(item: $detailAchievement) { item in AchievementDetailView(item: item, store: wishStore) }
            .sheet(isPresented: $isEditingProfile) { EditProfileView() }
        }
    }

    // MARK: - Wish Section

    var wishSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "star.fill").foregroundColor(.yellow)
                Text("\(String(wishStore.currentYear)) Wish List").font(.headline)
                Spacer()
                Button(action: { showAddWish = true }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(.pink).font(.title3)
                }
            }.padding(.horizontal)

            // Progress ring
            if !wishStore.thisYearWishes.isEmpty {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Color.pink.opacity(0.2), lineWidth: 10).frame(width: 56, height: 56)
                        Circle().trim(from: 0, to: CGFloat(wishProgress))
                            .stroke(Color.pink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .frame(width: 56, height: 56).rotationEffect(.degrees(-90))
                        Text("\(Int(wishProgress * 100))%").font(.caption2).fontWeight(.bold).foregroundColor(.pink)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(doneWishes.count) of \(wishStore.thisYearWishes.count) achieved ✨")
                            .font(.subheadline).fontWeight(.semibold)
                        ProgressView(value: wishProgress).tint(.pink)
                        // Count partial progress
                        let withProgress = wishStore.thisYearWishes.filter { !$0.isDone && !$0.progressEntries.isEmpty }.count
                        if withProgress > 0 {
                            Text("\(withProgress) in progress").font(.caption2).foregroundColor(.orange)
                        }
                    }
                }.padding(.horizontal)
            }

            // Category filter
            if !wishStore.thisYearWishes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        WishFilterPill(label: "All", isSelected: selectedWishCategory == nil, color: .secondary) { selectedWishCategory = nil }
                        ForEach(WishCategory.allCases, id: \.self) { cat in
                            let count = wishStore.thisYearWishes.filter { $0.category == cat }.count
                            if count > 0 {
                                WishFilterPill(label: "\(cat.emoji) \(cat.rawValue)", isSelected: selectedWishCategory == cat, color: cat.color) {
                                    selectedWishCategory = selectedWishCategory == cat ? nil : cat
                                }
                            }
                        }
                    }.padding(.horizontal)
                }
            }

            if wishStore.thisYearWishes.isEmpty {
                VStack(spacing: 10) {
                    Text("⭐").font(.system(size: 40))
                    Text("No wishes yet for \(String(wishStore.currentYear))").font(.subheadline).foregroundColor(.secondary)
                    Text("What do you want to achieve this year?").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button(action: { showAddWish = true }) {
                        Label("Add a Wish", systemImage: "plus.circle.fill").foregroundColor(.pink)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 20).padding(.horizontal)
            } else {
                if !pendingWishes.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(pendingWishes) { wish in
                            WishRow(wish: wish, store: wishStore)
                                .onTapGesture { detailWish = wish }
                                .swipeActions(edge: .leading) {
                                    Button { detailWish = wish } label: {
                                        Label("Progress", systemImage: "pencil.and.list.clipboard")
                                    }.tint(.orange)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { wishStore.wishes.removeAll { $0.id == wish.id } }
                                    label: { Label("Delete", systemImage: "trash") }
                                    Button { editingWish = wish } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                }
                        }
                    }.padding(.horizontal)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill").foregroundColor(.yellow)
                        Text("All wishes achieved! 🎉").font(.subheadline).foregroundColor(.pink)
                    }.padding(.horizontal)
                }

                if !doneWishes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { withAnimation { showCompletedWishes.toggle() } }) {
                            HStack {
                                Text("Achieved 🌟 (\(doneWishes.count))").font(.subheadline).foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: showCompletedWishes ? "chevron.up" : "chevron.down").font(.caption2).foregroundColor(.secondary)
                            }
                        }.padding(.horizontal)
                        if showCompletedWishes {
                            ForEach(doneWishes) { wish in
                                WishRow(wish: wish, store: wishStore)
                                    .onTapGesture { detailWish = wish }
                                    .swipeActions(edge: .leading) {
                                        Button { wishStore.toggle(wish) } label: {
                                            Label("Undo", systemImage: "arrow.uturn.backward")
                                        }.tint(.orange)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { wishStore.wishes.removeAll { $0.id == wish.id } }
                                        label: { Label("Delete", systemImage: "trash") }
                                        Button { editingWish = wish } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                    }
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Achievement Section

    var achievementSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "trophy.fill").foregroundColor(.orange)
                Text("Achievements").font(.headline)
                Spacer()
                Text("\(wishStore.achievements.count) total").font(.caption).foregroundColor(.secondary)
                Button(action: { showAddAchievement = true }) {
                    Image(systemName: "plus.circle.fill").foregroundColor(.orange).font(.title3)
                }
            }.padding(.horizontal)

            if wishStore.achievements.isEmpty {
                VStack(spacing: 10) {
                    Text("🏆").font(.system(size: 40))
                    Text("No achievements recorded yet").font(.subheadline).foregroundColor(.secondary)
                    Text("Record your milestones, big and small!").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button(action: { showAddAchievement = true }) {
                        Label("Add Achievement", systemImage: "plus.circle.fill").foregroundColor(.orange)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 20).padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        WishFilterPill(label: "All", isSelected: selectedAchievementCategory == nil, color: .secondary) { selectedAchievementCategory = nil }
                        ForEach(AchievementCategory.allCases, id: \.self) { cat in
                            let count = wishStore.achievements.filter { $0.category == cat }.count
                            if count > 0 {
                                WishFilterPill(label: "\(cat.emoji) \(cat.rawValue)", isSelected: selectedAchievementCategory == cat, color: cat.color) {
                                    selectedAchievementCategory = selectedAchievementCategory == cat ? nil : cat
                                }
                            }
                        }
                    }.padding(.horizontal)
                }

                let years = Array(Set(filteredAchievements.map { $0.yearAchieved })).sorted(by: >)
                ForEach(years, id: \.self) { year in
                    let yearItems = filteredAchievements.filter { $0.yearAchieved == year }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(year)).font(.subheadline).fontWeight(.bold).foregroundColor(.orange)
                            Text("· \(yearItems.count) achievement\(yearItems.count == 1 ? "" : "s")")
                                .font(.caption).foregroundColor(.secondary)
                        }.padding(.horizontal)
                        ForEach(yearItems) { item in
                            AchievementRow(item: item)
                                .onTapGesture { detailAchievement = item }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { wishStore.achievements.removeAll { $0.id == item.id } }
                                    label: { Label("Delete", systemImage: "trash") }
                                    Button { editingAchievement = item } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                }
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Wish Detail View (progress notes + completion)

struct WishDetailView: View {
    let wish: WishItem
    @ObservedObject var store: WishStore
    @Environment(\.dismiss) var dismiss
    @State private var showAddProgress = false
    @State private var progressNote = ""
    @State private var isCompletion = false
    @State private var isPartial = false      // new: partial achieved
    @State private var showEditWish = false
    @State private var showDeleteConfirm = false

    var wishBinding: WishItem? { store.wishes.first { $0.id == wish.id } }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {

                    // Header
                    VStack(spacing: 8) {
                        Text(wish.emoji).font(.system(size: 60))
                        Text(wish.title).font(.title2).fontWeight(.bold).multilineTextAlignment(.center)
                        HStack(spacing: 8) {
                            Text(wish.category.emoji + " " + wish.category.rawValue)
                                .font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(wish.category.color.opacity(0.12))
                                .foregroundColor(wish.category.color).cornerRadius(20)
                            if wish.isDone {
                                Label("Achieved!", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundColor(.green)
                            } else {
                                let count = wishBinding?.progressEntries.count ?? 0
                                let partialCount = wishBinding?.progressEntries.filter { !$0.isCompletion }.count ?? 0
                                if count > 0 {
                                    if partialCount > 0 {
                                        Label("\(partialCount) partial · \(count) total", systemImage: "circle.lefthalf.filled")
                                            .font(.caption).foregroundColor(.orange)
                                    } else {
                                        Label("\(count) update\(count == 1 ? "" : "s")", systemImage: "pencil.circle")
                                            .font(.caption).foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                        if !wish.note.isEmpty {
                            Text(wish.note).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(.regularMaterial).cornerRadius(16).padding(.horizontal)

                    // Progress entries timeline
                    let entries = wishBinding?.progressEntries.sorted { $0.date > $1.date } ?? []
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Progress Journal").font(.headline)
                            ForEach(entries) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(spacing: 4) {
                                        Image(systemName: entry.isCompletion
                                              ? "checkmark.circle.fill"
                                              : entry.note.isEmpty ? "pencil.circle.fill" : "circle.lefthalf.filled")
                                            .foregroundColor(entry.isCompletion ? .green : .orange).font(.title3)
                                        Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 1.5).frame(minHeight: 20)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(entry.isCompletion ? "Fully Achieved ✅" : "Partial Progress 🔸")
                                                .font(.caption).fontWeight(.semibold)
                                                .foregroundColor(entry.isCompletion ? .green : .orange)
                                            Spacer()
                                            Text(entry.date, style: .date).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Text(entry.note).font(.subheadline)
                                    }
                                }
                            }
                        }
                        .padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)
                    }

                    // Action buttons
                    if !wish.isDone {
                        VStack(spacing: 10) {

                            // Progress note
                            Button(action: { isCompletion = false; isPartial = false; showAddProgress = true }) {
                                HStack {
                                    Image(systemName: "pencil.circle.fill").foregroundColor(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Add Progress Note").fontWeight(.semibold).foregroundColor(.blue)
                                        Text("Track what you've done so far").font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Color.blue.opacity(0.08)).cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.25), lineWidth: 1))
                            }

                            // Partial achieved
                            Button(action: { isCompletion = false; isPartial = true; showAddProgress = true }) {
                                HStack {
                                    Image(systemName: "circle.lefthalf.filled").foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Partially Achieved 🔸").fontWeight(.semibold).foregroundColor(.orange)
                                        Text("Done some of it — log what you achieved").font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Color.orange.opacity(0.08)).cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                            }

                            // Fully achieved
                            Button(action: { isCompletion = true; isPartial = false; showAddProgress = true }) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.white)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Mark Fully Achieved! 🌟").fontWeight(.semibold).foregroundColor(.white)
                                        Text("Completed everything").font(.caption2).foregroundColor(.white.opacity(0.8))
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Color.green).cornerRadius(12)
                            }
                        }.padding(.horizontal)
                    } else {
                        VStack(spacing: 10) {
                            // Add more notes even when done
                            Button(action: { isCompletion = true; isPartial = false; showAddProgress = true }) {
                                HStack {
                                    Image(systemName: "note.text.badge.plus").foregroundColor(.green)
                                    Text("Add Completion Note").fontWeight(.semibold).foregroundColor(.green)
                                }
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Color.green.opacity(0.08)).cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.3), lineWidth: 1))
                            }
                            Button(action: { store.toggle(wish) }) {
                                Label("Undo — Mark as Not Done", systemImage: "arrow.uturn.backward")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }.padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Wish Detail").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // Edit button
                        Button(action: { showEditWish = true }) {
                            Image(systemName: "pencil.circle.fill").foregroundColor(.blue)
                        }
                        // Delete button
                        Button(action: { showDeleteConfirm = true }) {
                            Image(systemName: "trash.circle.fill").foregroundColor(.red)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEditWish) {
                AddEditWishView(store: store, existing: wish)
            }
            .confirmationDialog("Delete this wish?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.wishes.removeAll { $0.id == wish.id }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("\"\(wish.title)\" and all its progress notes will be deleted.")
            }
            .sheet(isPresented: $showAddProgress) {
                NavigationView {
                    Form {
                        Section(isCompletion
                            ? "How did you fully achieve this? 🎉"
                            : isPartial
                            ? "What part did you achieve? 🔸"
                            : "What progress did you make?") {
                            TextField(isCompletion
                                ? "e.g. Went to Paris and Rome in June!"
                                : isPartial
                                ? "e.g. Visited 1 out of 2 places — went to Japan!"
                                : "e.g. Booked flights to Japan, researching hotels...",
                                      text: $progressNote, axis: .vertical)
                                .lineLimit(4...8)
                        }
                        Section {
                            if isCompletion {
                                Label("This will mark the wish as fully achieved ✅", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundColor(.green)
                            } else if isPartial {
                                Label("This records a partial achievement — wish stays open", systemImage: "circle.lefthalf.filled")
                                    .font(.caption).foregroundColor(.orange)
                            } else {
                                Label("This adds a progress note — wish stays open", systemImage: "pencil.circle")
                                    .font(.caption).foregroundColor(.blue)
                            }
                        }
                    }
                    .navigationTitle(isCompletion ? "Mark Achieved" : isPartial ? "Partial Achievement" : "Add Progress")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") { showAddProgress = false; progressNote = "" }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(isCompletion ? "Achieve! 🌟" : isPartial ? "Save 🔸" : "Add Note") {
                                guard !progressNote.isEmpty else { return }
                                store.addProgressEntry(to: wish.id, note: progressNote,
                                                       isCompletion: isCompletion)
                                progressNote = ""; showAddProgress = false
                            }.fontWeight(.bold).disabled(progressNote.isEmpty)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Achievement Detail View (journal notes)

struct AchievementDetailView: View {
    let item: AchievementItem
    @ObservedObject var store: WishStore
    @Environment(\.dismiss) var dismiss
    @State private var showAddNote = false
    @State private var newNote = ""

    var achievementBinding: AchievementItem? { store.achievements.first { $0.id == item.id } }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {

                    // Header
                    VStack(spacing: 8) {
                        Text(item.emoji).font(.system(size: 60))
                        Text(item.title).font(.title2).fontWeight(.bold).multilineTextAlignment(.center)
                        HStack(spacing: 8) {
                            Text(item.category.emoji + " " + item.category.rawValue)
                                .font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(item.category.color.opacity(0.12))
                                .foregroundColor(item.category.color).cornerRadius(20)
                            Label(item.dateLabel, systemImage: "calendar")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if !item.note.isEmpty {
                            Text(item.note).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(.regularMaterial).cornerRadius(16).padding(.horizontal)

                    // Journal entries
                    let entries = achievementBinding?.journalEntries.sorted { $0.date > $1.date } ?? []
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Notes & Memories").font(.headline)
                            ForEach(entries) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "note.text")
                                        .foregroundColor(.orange).font(.title3)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Note").font(.caption).fontWeight(.semibold).foregroundColor(.orange)
                                            Spacer()
                                            Text(entry.date, style: .date).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Text(entry.note).font(.subheadline)
                                    }
                                }
                                .padding(12).background(Color.orange.opacity(0.06)).cornerRadius(10)
                            }
                        }
                        .padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)
                    }

                    // Add note button
                    Button(action: { showAddNote = true }) {
                        HStack {
                            Image(systemName: "note.text.badge.plus").foregroundColor(.orange)
                            Text("Add a Note or Memory").fontWeight(.semibold).foregroundColor(.orange)
                        }
                        .frame(maxWidth: .infinity).padding(14)
                        .background(Color.orange.opacity(0.1)).cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                    }.padding(.horizontal)
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Achievement").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showAddNote) {
                NavigationView {
                    Form {
                        Section("Add a note, memory or detail about this achievement") {
                            TextField("e.g. Visited Paris, Rome and Tokyo! The food in Japan was incredible...",
                                      text: $newNote, axis: .vertical)
                                .lineLimit(4...8)
                        }
                    }
                    .navigationTitle("Add Note").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { showAddNote = false; newNote = "" } }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Save") {
                                guard !newNote.isEmpty else { return }
                                store.addJournalEntry(to: item.id, note: newNote)
                                newNote = ""; showAddNote = false
                            }.fontWeight(.bold).disabled(newNote.isEmpty)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Wish Filter Pill

struct WishFilterPill: View {
    let label: String; let isSelected: Bool; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.caption).fontWeight(.medium)
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? color : color.opacity(0.1)).cornerRadius(20)
        }
    }
}

// MARK: - Wish Row

struct WishRow: View {
    let wish: WishItem; @ObservedObject var store: WishStore
    var body: some View {
        HStack(spacing: 12) {
            Button(action: { store.toggle(wish) }) {
                Image(systemName: wish.isDone ? "star.fill" : "star")
                    .font(.title2).foregroundColor(wish.isDone ? .yellow : wish.category.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(wish.emoji).font(.subheadline)
                    Text(wish.title).font(.subheadline).fontWeight(.medium)
                        .strikethrough(wish.isDone).foregroundColor(wish.isDone ? .secondary : .primary)
                }
                HStack(spacing: 6) {
                    Text(wish.category.emoji + " " + wish.category.rawValue)
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(wish.category.color.opacity(0.12)).foregroundColor(wish.category.color).cornerRadius(4)
                    // Show progress indicator
                    if !wish.progressEntries.isEmpty && !wish.isDone {
                        Text("\(wish.progressEntries.count) update\(wish.progressEntries.count == 1 ? "" : "s")")
                            .font(.caption2).foregroundColor(.orange)
                    }
                    if let note = wish.latestProgressNote, !wish.isDone {
                        Text(note).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                    if wish.isDone, let latest = wish.progressEntries.filter({ $0.isCompletion }).first {
                        Text(latest.note).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            // Progress dots
            if !wish.progressEntries.isEmpty && !wish.isDone {
                VStack(spacing: 2) {
                    Image(systemName: "circle.dotted").font(.caption2).foregroundColor(.orange)
                    Text("in progress").font(.system(size: 7)).foregroundColor(.orange)
                }
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary.opacity(0.4))
        }
        .padding(12).background(Color(.systemBackground)).cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .opacity(wish.isDone ? 0.65 : 1.0)
    }
}

// MARK: - Achievement Row

struct AchievementRow: View {
    let item: AchievementItem
    var body: some View {
        HStack(spacing: 12) {
            Text(item.emoji).font(.system(size: 28))
                .frame(width: 48, height: 48)
                .background(item.category.color.opacity(0.12)).cornerRadius(12)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline).fontWeight(.semibold)
                HStack(spacing: 6) {
                    Text(item.category.emoji + " " + item.category.rawValue)
                        .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(item.category.color.opacity(0.12))
                        .foregroundColor(item.category.color).cornerRadius(4)
                    Text(item.dateLabel).font(.caption2).foregroundColor(.secondary)
                }
                if !item.note.isEmpty {
                    Text(item.note).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                if !item.journalEntries.isEmpty {
                    Text("\(item.journalEntries.count) note\(item.journalEntries.count == 1 ? "" : "s")")
                        .font(.caption2).foregroundColor(.orange)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary.opacity(0.4))
        }
        .padding(12).background(Color(.systemBackground)).cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Add / Edit Wish View

struct AddEditWishView: View {
    @ObservedObject var store: WishStore
    @Environment(\.dismiss) var dismiss
    var existing: WishItem?
    @State private var title = ""; @State private var note = ""
    @State private var emoji = "⭐"; @State private var category: WishCategory = .personal
    @State private var targetYear = Calendar.current.component(.year, from: Date())
    var isEditing: Bool { existing != nil }
    let quickEmojis = ["⭐","✈️","🏠","💍","🎓","💪","📚","🌍","🎵","💰","🌸","🤝","🏆","🎨","🧘","🚀","🌙","🎯","💻","🌿"]

    var body: some View {
        NavigationView {
            Form {
                Section("Wish") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(quickEmojis, id: \.self) { e in
                                Text(e).font(.system(size: 26)).padding(6)
                                    .background(emoji == e ? Color.pink.opacity(0.2) : Color.clear)
                                    .cornerRadius(8).onTapGesture { emoji = e }
                            }
                        }.padding(.vertical, 4)
                    }
                    TextField("What do you wish for this year?", text: $title)
                    TextField("Details (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(WishCategory.allCases, id: \.self) { cat in
                            Text(cat.emoji + " " + cat.rawValue).tag(cat)
                        }
                    }.pickerStyle(.wheel).frame(height: 120)
                }
                Section("Target Year") {
                    Stepper(String(targetYear), value: $targetYear, in: 2020...2035)
                }
            }
            .navigationTitle(isEditing ? "Edit Wish" : "New Wish").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Add") {
                        guard !title.isEmpty else { return }
                        var wish = WishItem(id: existing?.id ?? UUID(), title: title, note: note,
                            emoji: emoji, isDone: existing?.isDone ?? false,
                            category: category, targetYear: targetYear)
                        wish.progressEntries = existing?.progressEntries ?? []
                        wish.completedAt = existing?.completedAt
                        if isEditing, let i = store.wishes.firstIndex(where: { $0.id == wish.id }) {
                            store.wishes[i] = wish
                        } else { store.wishes.append(wish) }
                        dismiss()
                    }.fontWeight(.bold).disabled(title.isEmpty)
                }
            }
            .onAppear {
                guard let e = existing else { return }
                title = e.title; note = e.note; emoji = e.emoji
                category = e.category; targetYear = e.targetYear
            }
        }
    }
}

// MARK: - Add / Edit Achievement View

struct AddEditAchievementView: View {
    @ObservedObject var store: WishStore
    @Environment(\.dismiss) var dismiss
    var existing: AchievementItem?
    @State private var title = ""; @State private var note = ""
    @State private var emoji = "🏆"; @State private var category: AchievementCategory = .milestone
    @State private var date = Date()
    var isEditing: Bool { existing != nil }
    let quickEmojis = ["🏆","🥇","🎖️","🌟","⭐","✅","💪","🎓","💼","🌍","✈️","💕","📚","🎨","🚀","💰","🏠","🎵","🌿","🥂"]

    var body: some View {
        NavigationView {
            Form {
                Section("Achievement") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(quickEmojis, id: \.self) { e in
                                Text(e).font(.system(size: 26)).padding(6)
                                    .background(emoji == e ? Color.orange.opacity(0.2) : Color.clear)
                                    .cornerRadius(8).onTapGesture { emoji = e }
                            }
                        }.padding(.vertical, 4)
                    }
                    TextField("What did you achieve?", text: $title)
                    TextField("Details (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(AchievementCategory.allCases, id: \.self) { cat in
                            Text(cat.emoji + " " + cat.rawValue).tag(cat)
                        }
                    }.pickerStyle(.wheel).frame(height: 120)
                }
                Section("Date Achieved") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle(isEditing ? "Edit Achievement" : "Add Achievement").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Add") {
                        guard !title.isEmpty else { return }
                        var item = AchievementItem(id: existing?.id ?? UUID(), title: title,
                            note: note, emoji: emoji, category: category, date: date)
                        item.journalEntries = existing?.journalEntries ?? []
                        if isEditing, let i = store.achievements.firstIndex(where: { $0.id == item.id }) {
                            store.achievements[i] = item
                        } else { store.achievements.append(item) }
                        dismiss()
                    }.fontWeight(.bold).disabled(title.isEmpty)
                }
            }
            .onAppear {
                guard let e = existing else { return }
                title = e.title; note = e.note; emoji = e.emoji
                category = e.category; date = e.date
            }
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("userName") var userName: String = "Kelly"
    @AppStorage("userAge") var userAge: Int = 25
    @AppStorage("userHeight") var userHeight: Double = 160
    @AppStorage("userWeight") var userWeight: Double = 71
    @AppStorage("dailyCalorieGoal") var dailyCalorieGoal: Int = 1683
    @AppStorage("weeklyWeightGoal") var weeklyWeightGoal: Double = 0.5
    @State private var heightStr = ""; @State private var weightStr = ""
    @State private var calorieStr = ""; @State private var ageStr = ""; @State private var goalStr = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Personal") {
                    TextField("Name", text: $userName)
                    HStack { Text("Age").foregroundColor(.secondary); Spacer(); TextField("25", text: $ageStr).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80) }
                    HStack { Text("Height").foregroundColor(.secondary); Spacer(); TextField("160", text: $heightStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text("cm").foregroundColor(.secondary) }
                    HStack { Text("Weight").foregroundColor(.secondary); Spacer(); TextField("71", text: $weightStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text("kg").foregroundColor(.secondary) }
                }
                Section("Goals") {
                    HStack { Text("Daily Calories").foregroundColor(.secondary); Spacer(); TextField("1683", text: $calorieStr).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80); Text("kcal").foregroundColor(.secondary) }
                    HStack { Text("Weekly Weight Goal").foregroundColor(.secondary); Spacer(); TextField("0.5", text: $goalStr).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text("kg").foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Edit Profile").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let a = Int(ageStr) { userAge = a }
                        if let h = Double(heightStr) { userHeight = h }
                        if let w = Double(weightStr) { userWeight = w }
                        if let c = Int(calorieStr) { dailyCalorieGoal = c }
                        if let g = Double(goalStr) { weeklyWeightGoal = g }
                        dismiss()
                    }.fontWeight(.bold)
                }
            }
            .onAppear {
                ageStr = "\(userAge)"; heightStr = String(format: "%.0f", userHeight)
                weightStr = String(format: "%.1f", userWeight)
                calorieStr = "\(dailyCalorieGoal)"; goalStr = String(format: "%.1f", weeklyWeightGoal)
            }
        }
    }
}
