import SwiftUI
import Combine

class UserProfile: ObservableObject {
    @AppStorage("dailyCalorieGoal") var dailyCalorieGoal: Int = 1683
    @AppStorage("weeklyWeightGoal") var weeklyWeightGoal: Double = 0.5
    @AppStorage("userWeight") var userWeight: Double = 71
    @AppStorage("userHeight") var userHeight: Double = 160
    @AppStorage("userAge") var userAge: Int = 25
    @AppStorage("userName") var userName: String = "Kelly"
}

// MARK: - Year Wish Models

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

    init(id: UUID = UUID(), title: String, note: String = "", emoji: String = "⭐",
         isDone: Bool = false, category: WishCategory = .personal,
         targetYear: Int = Calendar.current.component(.year, from: Date())) {
        self.id = id; self.title = title; self.note = note; self.emoji = emoji
        self.isDone = isDone; self.category = category
        self.createdAt = Date(); self.targetYear = targetYear
    }
}

class WishStore: ObservableObject {
    @Published var wishes: [WishItem] = [] { didSet { save() } }
    init() { load() }
    func save() {
        if let d = try? JSONEncoder().encode(wishes) { UserDefaults.standard.set(d, forKey: "wishItems_v2") }
    }
    func load() {
        guard let d = UserDefaults.standard.data(forKey: "wishItems_v2"),
              let decoded = try? JSONDecoder().decode([WishItem].self, from: d) else { return }
        wishes = decoded
    }
    func toggle(_ item: WishItem) {
        if let i = wishes.firstIndex(where: { $0.id == item.id }) {
            wishes[i].isDone.toggle()
            wishes[i].completedAt = wishes[i].isDone ? Date() : nil
        }
    }
    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var thisYearWishes: [WishItem] { wishes.filter { $0.targetYear == currentYear } }
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
    @State private var showCompletedWishes = false
    @State private var selectedCategory: WishCategory? = nil
    @State private var isEditingProfile = false

    var pendingWishes: [WishItem] {
        var base = wishStore.thisYearWishes.filter { !$0.isDone }
        if let cat = selectedCategory { base = base.filter { $0.category == cat } }
        return base
    }
    var doneWishes: [WishItem] {
        var base = wishStore.thisYearWishes.filter { $0.isDone }
        if let cat = selectedCategory { base = base.filter { $0.category == cat } }
        return base
    }
    var progress: Double {
        guard !wishStore.thisYearWishes.isEmpty else { return 0 }
        return Double(wishStore.thisYearWishes.filter { $0.isDone }.count) / Double(wishStore.thisYearWishes.count)
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
                                Text("kcal/day goal").font(.caption2).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity)
                            Divider().frame(height: 36)
                            VStack(spacing: 4) {
                                Text(String(format: "%.1f kg/wk", weeklyWeightGoal)).font(.title3).fontWeight(.bold).foregroundColor(.blue)
                                Text("weight goal").font(.caption2).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    .padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)

                    // Year Wish List
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "star.fill").foregroundColor(.yellow)
                            Text("\(String(wishStore.currentYear)) Wish List").font(.headline)
                            Spacer()
                            Button(action: { showAddWish = true }) {
                                Image(systemName: "plus.circle.fill").foregroundColor(.pink).font(.title3)
                            }
                        }

                        // Progress ring
                        if !wishStore.thisYearWishes.isEmpty {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle().stroke(Color.pink.opacity(0.2), lineWidth: 10).frame(width: 56, height: 56)
                                    Circle().trim(from: 0, to: CGFloat(progress))
                                        .stroke(Color.pink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                        .frame(width: 56, height: 56).rotationEffect(.degrees(-90))
                                    Text("\(Int(progress * 100))%").font(.caption2).fontWeight(.bold).foregroundColor(.pink)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(doneWishes.count) of \(wishStore.thisYearWishes.count) achieved ✨")
                                        .font(.subheadline).fontWeight(.semibold)
                                    ProgressView(value: progress).tint(.pink)
                                }
                            }
                        }

                        // Category filter
                        if !wishStore.thisYearWishes.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    WishFilterPill(label: "All", isSelected: selectedCategory == nil, color: .secondary) {
                                        selectedCategory = nil
                                    }
                                    ForEach(WishCategory.allCases, id: \.self) { cat in
                                        let count = wishStore.thisYearWishes.filter { $0.category == cat }.count
                                        if count > 0 {
                                            WishFilterPill(label: "\(cat.emoji) \(cat.rawValue)", isSelected: selectedCategory == cat, color: cat.color) {
                                                selectedCategory = selectedCategory == cat ? nil : cat
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Pending wishes
                        if pendingWishes.isEmpty && wishStore.thisYearWishes.isEmpty {
                            VStack(spacing: 10) {
                                Text("⭐").font(.system(size: 40))
                                Text("No wishes yet for \(String(wishStore.currentYear))")
                                    .font(.subheadline).foregroundColor(.secondary)
                                Text("What do you want to achieve this year?")
                                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                                Button(action: { showAddWish = true }) {
                                    Label("Add a Wish", systemImage: "plus.circle.fill").foregroundColor(.pink)
                                }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                        } else {
                            if !pendingWishes.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(pendingWishes) { wish in
                                        WishRow(wish: wish, store: wishStore)
                                            .onTapGesture { editingWish = wish }
                                            .swipeActions(edge: .leading) {
                                                Button { wishStore.toggle(wish) } label: {
                                                    Label("Done!", systemImage: "star.fill")
                                                }.tint(.pink)
                                            }
                                            .swipeActions(edge: .trailing) {
                                                Button(role: .destructive) {
                                                    wishStore.wishes.removeAll { $0.id == wish.id }
                                                } label: { Label("Delete", systemImage: "trash") }
                                                Button { editingWish = wish } label: {
                                                    Label("Edit", systemImage: "pencil")
                                                }.tint(.blue)
                                            }
                                    }
                                }
                            }

                            // Achieved
                            if !doneWishes.isEmpty {
                                Button(action: { withAnimation { showCompletedWishes.toggle() } }) {
                                    HStack {
                                        Text("Achieved 🌟 (\(doneWishes.count))").font(.subheadline).foregroundColor(.secondary)
                                        Spacer()
                                        Image(systemName: showCompletedWishes ? "chevron.up" : "chevron.down")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                if showCompletedWishes {
                                    VStack(spacing: 8) {
                                        ForEach(doneWishes) { wish in
                                            WishRow(wish: wish, store: wishStore)
                                                .swipeActions(edge: .leading) {
                                                    Button { wishStore.toggle(wish) } label: {
                                                        Label("Undo", systemImage: "arrow.uturn.backward")
                                                    }.tint(.orange)
                                                }
                                                .swipeActions(edge: .trailing) {
                                                    Button(role: .destructive) {
                                                        wishStore.wishes.removeAll { $0.id == wish.id }
                                                    } label: { Label("Delete", systemImage: "trash") }
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)

                    // App info
                    VStack(spacing: 8) {
                        Text("Kelly Life").font(.caption).foregroundColor(.secondary)
                        Text("Built with ❤️ for healthy living").font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.bottom, 24)
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showAddWish) { AddEditWishView(store: wishStore) }
            .sheet(item: $editingWish) { wish in AddEditWishView(store: wishStore, existing: wish) }
            .sheet(isPresented: $isEditingProfile) { EditProfileView() }
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
                    if !wish.note.isEmpty {
                        Text(wish.note).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary.opacity(0.4))
        }
        .padding(12).background(Color(.systemBackground)).cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .opacity(wish.isDone ? 0.65 : 1.0)
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
                    TextField("Details (optional)", text: $note)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(WishCategory.allCases, id: \.self) { cat in
                            Text(cat.emoji + " " + cat.rawValue).tag(cat)
                        }
                    }.pickerStyle(.wheel).frame(height: 120)
                }
                Section("Target Year") {
                    Stepper("\(String(targetYear))", value: $targetYear, in: 2020...2035)
                }
            }
            .navigationTitle(isEditing ? "Edit Wish" : "New Wish").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Add") {
                        guard !title.isEmpty else { return }
                        let wish = WishItem(id: existing?.id ?? UUID(), title: title, note: note,
                            emoji: emoji, isDone: existing?.isDone ?? false, category: category, targetYear: targetYear)
                        if isEditing, let i = store.wishes.firstIndex(where: { $0.id == wish.id }) {
                            store.wishes[i] = wish
                        } else { store.wishes.append(wish) }
                        dismiss()
                    }.fontWeight(.bold).disabled(title.isEmpty)
                }
            }
            .onAppear {
                guard let e = existing else { return }
                title = e.title; note = e.note; emoji = e.emoji; category = e.category; targetYear = e.targetYear
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
    @State private var calorieStr = ""; @State private var ageStr = ""
    @State private var goalStr = ""

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
