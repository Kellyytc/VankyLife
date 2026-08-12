import SwiftUI
import Combine

// MARK: - Models

enum FridgeLocation: String, Codable, CaseIterable {
    case fridge = "Fridge"
    case freezer = "Freezer"
    case storage = "Storage"
    var icon: String {
        switch self { case .fridge: return "🧊"; case .freezer: return "❄️"; case .storage: return "📦" }
    }
}

enum FridgeTrackingMode: String, Codable, CaseIterable {
    case percentage = "Percentage"
    case count = "Count"
}

struct FridgeItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var emoji: String
    var location: FridgeLocation
    var trackingMode: FridgeTrackingMode
    var percentageLeft: Double
    var count: Int
    var totalCount: Int
    var expiryDate: Date?
    var hasExpiry: Bool

    init(id: UUID = UUID(), name: String, emoji: String, location: FridgeLocation,
         trackingMode: FridgeTrackingMode = .percentage, percentageLeft: Double = 1.0,
         count: Int = 1, totalCount: Int = 1, expiryDate: Date? = nil, hasExpiry: Bool = true) {
        self.id = id; self.name = name; self.emoji = emoji; self.location = location
        self.trackingMode = trackingMode; self.percentageLeft = percentageLeft
        self.count = count; self.totalCount = totalCount
        self.expiryDate = expiryDate; self.hasExpiry = hasExpiry
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🥦"
        location = try c.decodeIfPresent(FridgeLocation.self, forKey: .location) ?? .fridge
        trackingMode = try c.decodeIfPresent(FridgeTrackingMode.self, forKey: .trackingMode) ?? .percentage
        percentageLeft = try c.decodeIfPresent(Double.self, forKey: .percentageLeft) ?? 1.0
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        totalCount = try c.decodeIfPresent(Int.self, forKey: .totalCount) ?? 1
        expiryDate = try c.decodeIfPresent(Date.self, forKey: .expiryDate)
        hasExpiry = try c.decodeIfPresent(Bool.self, forKey: .hasExpiry) ?? (expiryDate != nil)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, location, trackingMode,
             percentageLeft, count, totalCount, expiryDate, hasExpiry
    }

    var fillRatio: Double {
        switch trackingMode {
        case .percentage: return percentageLeft
        case .count: guard totalCount > 0 else { return 0 }
            return Double(count) / Double(totalCount)
        }
    }

    var isOverStocked: Bool {
        switch trackingMode {
        case .percentage: return percentageLeft > 1.05
        case .count: return count > totalCount
        }
    }

    var isEmpty: Bool {
        switch trackingMode {
        case .percentage: return percentageLeft <= 0.05
        case .count: return count <= 0
        }
    }

    enum StockStatus {
        case empty, critical, low, ok, full, overStocked
        var label: String {
            switch self {
            case .empty: return "Empty"
            case .critical: return "Almost gone"
            case .low: return "Running low"
            case .ok: return "Good"
            case .full: return "Full"
            case .overStocked: return "Overstocked"
            }
        }
        var color: Color {
            switch self {
            case .empty: return .gray
            case .critical: return .red
            case .low: return .orange
            case .ok: return .green
            case .full: return .green
            case .overStocked: return .purple
            }
        }
        var icon: String {
            switch self {
            case .empty: return "circle"
            case .critical: return "exclamationmark.circle.fill"
            case .low: return "exclamationmark.triangle.fill"
            case .ok: return "checkmark.circle.fill"
            case .full: return "checkmark.circle.fill"
            case .overStocked: return "exclamationmark.triangle.fill"
            }
        }
    }

    var status: StockStatus {
        if isOverStocked { return .overStocked }
        let r = min(fillRatio, 1.0)
        if r <= 0.05 { return .empty }
        if r <= 0.25 { return .critical }
        if r <= 0.5  { return .low }
        if r < 1.0   { return .ok }
        return .full
    }

    var displayAmount: String {
        switch trackingMode {
        case .percentage:
            if isOverStocked { return "Over \(Int(percentageLeft * 100))%" }
            return "\(Int(percentageLeft * 100))%"
        case .count:
            return "\(count)/\(totalCount)"
        }
    }

    var daysUntilExpiry: Int? {
        guard hasExpiry, let expiry = expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }

    var expiryLabel: String {
        guard hasExpiry else { return "" }
        guard let days = daysUntilExpiry else { return "" }
        if days < 0 { return "Expired \(-days)d ago" }
        if days == 0 { return "Expires today!" }
        if days == 1 { return "Tomorrow" }
        return "\(days)d left"
    }

    var expiryColor: Color {
        guard let days = daysUntilExpiry else { return .secondary }
        if days < 0 { return .red }
        if days <= 2 { return .orange }
        if days <= 5 { return .yellow }
        return .secondary
    }
}

// MARK: - Store

class FridgeStore: ObservableObject {
    @Published var items: [FridgeItem] = [] { didSet { save() } }
    init() { load() }
    func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "fridgeItems_v2")
        }
    }
    func load() {
        if let data = UserDefaults.standard.data(forKey: "fridgeItems_v2"),
           let decoded = try? JSONDecoder().decode([FridgeItem].self, from: data) {
            items = decoded; return
        }
        if let data = UserDefaults.standard.data(forKey: "fridgeItems"),
           let decoded = try? JSONDecoder().decode([FridgeItem].self, from: data) {
            items = decoded; save()
        }
    }
    func updateItem(_ updated: FridgeItem) {
        if let i = items.firstIndex(where: { $0.id == updated.id }) { items[i] = updated }
    }
    func filteredItems(for location: FridgeLocation) -> [FridgeItem] {
        items.filter { $0.location == location }
    }
}

// MARK: - Fridge View (list layout)

struct FridgeView: View {
    @StateObject private var store = FridgeStore()
    @State private var showAddItem = false
    @State private var selectedLocation: FridgeLocation = .fridge
    @State private var searchText = ""
    @State private var selectedItem: FridgeItem? = nil

    var filteredItems: [FridgeItem] {
        let base = searchText.isEmpty
            ? store.filteredItems(for: selectedLocation)
            : store.items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        return base.sorted {
            // Sort: overstocked first, then critical/empty, then by name
            let order: (FridgeItem) -> Int = { item in
                switch item.status {
                case .overStocked: return 0
                case .critical: return 1
                case .empty: return 2
                case .low: return 3
                case .ok: return 4
                case .full: return 5
                }
            }
            return order($0) < order($1)
        }
    }

    var statusCounts: (empty: Int, low: Int, ok: Int, over: Int) {
        let loc = store.filteredItems(for: selectedLocation)
        return (
            empty: loc.filter { $0.status == .empty || $0.status == .critical }.count,
            low: loc.filter { $0.status == .low }.count,
            ok: loc.filter { $0.status == .ok || $0.status == .full }.count,
            over: loc.filter { $0.status == .overStocked }.count
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // Location tabs
                Picker("Location", selection: $selectedLocation) {
                    ForEach(FridgeLocation.allCases, id: \.self) { loc in
                        Text(loc.icon + " " + loc.rawValue).tag(loc)
                    }
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.top, 8)

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search all items…", text: $searchText)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal).padding(.top, 8)

                // Status summary row (only when not searching)
                if searchText.isEmpty {
                    let counts = statusCounts
                    let total = store.filteredItems(for: selectedLocation).count
                    if total > 0 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if counts.over > 0 {
                                    StatusChip(label: "Overstocked", count: counts.over, color: .purple)
                                }
                                if counts.empty > 0 {
                                    StatusChip(label: "Need soon", count: counts.empty, color: .red)
                                }
                                if counts.low > 0 {
                                    StatusChip(label: "Running low", count: counts.low, color: .orange)
                                }
                                if counts.ok > 0 {
                                    StatusChip(label: "Good", count: counts.ok, color: .green)
                                }
                                Spacer()
                                Text("\(total) items").font(.caption2).foregroundColor(.secondary)
                            }.padding(.horizontal).padding(.vertical, 6)
                        }
                    }
                } else {
                    // Search hint
                    if !filteredItems.isEmpty {
                        Text("Found \(filteredItems.count) result\(filteredItems.count == 1 ? "" : "s") across all locations")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal).padding(.top, 6)
                    }
                }

                Divider().padding(.top, 4)

                // List
                if filteredItems.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        if searchText.isEmpty {
                            Text(selectedLocation.icon).font(.system(size: 60))
                            Text("\(selectedLocation.rawValue) is empty")
                                .font(.title3).foregroundColor(.secondary)
                            Text("Tap + to add items")
                                .font(.subheadline).foregroundColor(.secondary)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.4))
                            Text("No items matching \"\(searchText)\"")
                                .font(.subheadline).foregroundColor(.secondary)
                            Text("You don't have this item")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            FridgeListRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedItem = item }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.items.removeAll { $0.id == item.id }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { selectedItem = item } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }.tint(.blue)
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("My Fridge")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddItem = true }) { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddEditFridgeItemView(store: store, defaultLocation: selectedLocation)
            }
            .sheet(item: $selectedItem) { item in
                ItemEditSheet(item: item, store: store)
            }
        }
    }
}

// MARK: - Status Chip

struct StatusChip: View {
    let label: String; let count: Int; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count) \(label)").font(.caption2).foregroundColor(color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1)).cornerRadius(20)
    }
}

// MARK: - Fridge List Row

struct FridgeListRow: View {
    let item: FridgeItem

    var body: some View {
        HStack(spacing: 12) {

            // Emoji with color background
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.status.color.opacity(0.12))
                    .frame(width: 48, height: 48)
                Text(item.emoji).font(.system(size: 26))
            }

            // Name + expiry
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline).fontWeight(.semibold)
                HStack(spacing: 6) {
                    // Location tag (when searching across all)
                    Text(item.location.icon + " " + item.location.rawValue)
                        .font(.caption2).foregroundColor(.secondary)
                    if !item.expiryLabel.isEmpty {
                        Text("·").foregroundColor(.secondary)
                        Text(item.expiryLabel).font(.caption2).foregroundColor(item.expiryColor)
                    }
                }
            }

            Spacer()

            // Amount + status badge
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.displayAmount)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(item.status.color)

                HStack(spacing: 3) {
                    Image(systemName: item.status.icon)
                        .font(.system(size: 9))
                    Text(item.status.label).font(.caption2)
                }
                .foregroundColor(item.status.color)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(item.status.color.opacity(0.1))
                .cornerRadius(20)
            }

            // Fill bar (vertical)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray5))
                .frame(width: 6, height: 40)
                .overlay(
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.status.color)
                                .frame(width: 6, height: geo.size.height * CGFloat(min(item.fillRatio, 1.0)))
                        }
                    }
                )
                .animation(.spring(response: 0.4), value: item.fillRatio)

            Image(systemName: "chevron.right")
                .font(.caption2).foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Item Edit Sheet (quick inline editor)

struct ItemEditSheet: View {
    let item: FridgeItem
    @ObservedObject var store: FridgeStore
    @Environment(\.dismiss) var dismiss

    @State private var percentage: Double = 1.0
    @State private var count: Int = 1
    @State private var showFullEdit = false

    init(item: FridgeItem, store: FridgeStore) {
        self.item = item; self.store = store
        _percentage = State(initialValue: item.percentageLeft)
        _count = State(initialValue: item.count)
    }

    var currentStatus: FridgeItem.StockStatus {
        var temp = item
        if item.trackingMode == .percentage { temp.percentageLeft = percentage }
        else { temp.count = count }
        return temp.status
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {

                // Item header
                VStack(spacing: 8) {
                    Text(item.emoji).font(.system(size: 60))
                    Text(item.name).font(.title2).fontWeight(.bold)
                    HStack(spacing: 6) {
                        Image(systemName: currentStatus.icon)
                        Text(currentStatus.label)
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(currentStatus.color)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(currentStatus.color.opacity(0.1))
                    .cornerRadius(20)
                }
                .frame(maxWidth: .infinity).padding(.top, 20)

                Divider()

                // Percentage editor
                if item.trackingMode == .percentage {
                    VStack(spacing: 16) {
                        Text(percentage > 1.05
                             ? "Overstocked — \(Int(percentage * 100))%"
                             : "\(Int(percentage * 100))% remaining")
                            .font(.title3).fontWeight(.bold)
                            .foregroundColor(currentStatus.color)

                        // Slider
                        Slider(value: $percentage, in: 0...1.5, step: 0.05)
                            .tint(currentStatus.color)
                            .padding(.horizontal)

                        // Quick buttons
                        HStack(spacing: 8) {
                            ForEach([
                                (0.0, "Empty"), (0.25, "25%"), (0.5, "Half"),
                                (0.75, "75%"), (1.0, "Full"), (1.25, "Over!")
                            ], id: \.0) { pct, label in
                                Button(action: { withAnimation { percentage = pct } }) {
                                    Text(label).font(.caption)
                                        .foregroundColor(abs(percentage - pct) < 0.05 ? .white : .secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .background(abs(percentage - pct) < 0.05
                                                    ? (pct > 1.0 ? Color.purple : currentStatus.color)
                                                    : Color(.systemGray6))
                                        .cornerRadius(10)
                                }
                            }
                        }.padding(.horizontal)
                    }
                }

                // Count editor
                if item.trackingMode == .count {
                    VStack(spacing: 16) {
                        Text(count > item.totalCount
                             ? "Overstocked! \(count) of \(item.totalCount) expected"
                             : "\(count) of \(item.totalCount) remaining")
                            .font(.title3).fontWeight(.bold)
                            .foregroundColor(currentStatus.color)
                            .multilineTextAlignment(.center)

                        // Big stepper
                        HStack(spacing: 32) {
                            Button(action: { if count > 0 { withAnimation { count -= 1 } } }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(count > 0 ? currentStatus.color : .secondary)
                            }.disabled(count <= 0)

                            Text("\(count)")
                                .font(.system(size: 64, weight: .bold))
                                .foregroundColor(count > item.totalCount ? .purple : currentStatus.color)
                                .frame(minWidth: 80, alignment: .center)
                                .animation(.none, value: count)

                            Button(action: { withAnimation { count += 1 } }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(count >= item.totalCount ? .purple : currentStatus.color)
                            }
                        }

                        // Dot preview
                        let total = max(count, item.totalCount)
                        let showDots = min(total, 24)
                        HStack(spacing: 4) {
                            ForEach(0..<showDots, id: \.self) { i in
                                Circle()
                                    .fill(i < count
                                          ? (count > item.totalCount ? Color.purple : Color.green)
                                          : Color(.systemGray5))
                                    .frame(width: 14, height: 14)
                            }
                            if total > 24 {
                                Text("+\(total - 24)").font(.caption2).foregroundColor(.secondary)
                            }
                        }

                        // Quick-set row
                        let presets: [(Int, String)] = {
                            let q = max(1, Int((Double(item.totalCount) * 0.25).rounded()))
                            let h = max(1, Int((Double(item.totalCount) * 0.5).rounded()))
                            let t = max(1, Int((Double(item.totalCount) * 0.75).rounded()))
                            let over = item.totalCount + max(1, item.totalCount / 2)
                            return [(0, "0"), (q, "\(q)"), (h, "\(h)"), (t, "\(t)"),
                                    (item.totalCount, "\(item.totalCount)"), (over, "Over!")]
                        }()
                        HStack(spacing: 6) {
                            ForEach(presets, id: \.0) { target, label in
                                Button(action: { withAnimation { count = target } }) {
                                    Text(label).font(.caption)
                                        .foregroundColor(count == target ? .white : .secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .background(count == target
                                                    ? (target > item.totalCount ? Color.purple : Color.green)
                                                    : Color(.systemGray6))
                                        .cornerRadius(10)
                                }
                            }
                        }.padding(.horizontal)
                    }
                }

                Spacer()

                // Full edit button
                Button(action: { showFullEdit = true }) {
                    Label("Edit Details (name, expiry, mode…)", systemImage: "pencil.circle")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
            }
            .navigationTitle("Update Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var updated = item
                        if item.trackingMode == .percentage { updated.percentageLeft = percentage }
                        else { updated.count = count }
                        store.updateItem(updated)
                        dismiss()
                    }.fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showFullEdit) {
                AddEditFridgeItemView(store: store, existingItem: item)
            }
        }
    }
}

// MARK: - Add / Edit Fridge Item View

struct AddEditFridgeItemView: View {
    @ObservedObject var store: FridgeStore
    @Environment(\.dismiss) var dismiss

    var existingItem: FridgeItem?
    var defaultLocation: FridgeLocation

    @State private var name = ""
    @State private var emoji = "🥦"
    @State private var location: FridgeLocation = .fridge
    @State private var trackingMode: FridgeTrackingMode = .percentage
    @State private var startPercentage: Double = 1.0
    @State private var startCount: Int = 1
    @State private var totalCount: Int = 6
    @State private var hasExpiry = true
    @State private var expiryDate = Date().addingTimeInterval(7 * 24 * 3600)

    var isEditing: Bool { existingItem != nil }

    init(store: FridgeStore, defaultLocation: FridgeLocation = .fridge, existingItem: FridgeItem? = nil) {
        self.store = store; self.defaultLocation = defaultLocation; self.existingItem = existingItem
    }

    let commonEmojis = [
        "🥬","🧃","🍎","🍞","🥩","🐟","🥫","🧄","🥚","🫙","🍗",
        "🧅","🍋","🍇","🍓","🌽","🥔","🍆","🫑",
        "🧈","🍜","🥟","🥐","🍱","🥤",
        "🧊","🫐","🍈","🍌","🍍","🥭","🍑","🍒","🍅","🫒"
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Item Details") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonEmojis, id: \.self) { e in
                                Text(e).font(.system(size: 28)).padding(6)
                                    .background(emoji == e ? Color.green.opacity(0.2) : Color.clear)
                                    .cornerRadius(8).onTapGesture { emoji = e }
                            }
                        }.padding(.vertical, 4)
                    }
                    TextField("Item name (e.g. Apples, Milk, 豆腐)", text: $name)
                }

                Section("Storage") {
                    Picker("Location", selection: $location) {
                        ForEach(FridgeLocation.allCases, id: \.self) { loc in
                            Text(loc.icon + " " + loc.rawValue).tag(loc)
                        }
                    }.pickerStyle(.segmented)
                    Toggle("Has expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expiry Date", selection: $expiryDate, displayedComponents: .date)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "infinity").foregroundColor(.secondary)
                            Text("No expiry date").foregroundColor(.secondary).font(.subheadline)
                        }.padding(.vertical, 2)
                    }
                }

                Section("How do you track this?") {
                    Picker("Track by", selection: $trackingMode) {
                        Label("Percentage  (milk, juice, sauce…)", systemImage: "percent")
                            .tag(FridgeTrackingMode.percentage)
                        Label("Count  (apples, eggs, cans…)", systemImage: "number")
                            .tag(FridgeTrackingMode.count)
                    }.pickerStyle(.inline)
                }

                if trackingMode == .percentage {
                    Section("Current Amount") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("How full is it?").foregroundColor(.secondary)
                                Spacer()
                                Text(startPercentage > 1.05 ? "Over! \(Int(startPercentage * 100))%"
                                     : startPercentage >= 1.0 ? "Full"
                                     : startPercentage <= 0.0 ? "Empty"
                                     : "\(Int(startPercentage * 100))%")
                                    .fontWeight(.semibold)
                                    .foregroundColor(startPercentage > 1.05 ? .purple
                                                     : startPercentage > 0.6 ? .green
                                                     : startPercentage > 0.3 ? .orange : .red)
                            }
                            Slider(value: $startPercentage, in: 0...1.5, step: 0.05).tint(.green)
                            HStack(spacing: 3) {
                                ForEach([(0.0,"Empty"),(0.25,"25%"),(0.5,"Half"),
                                         (0.75,"75%"),(1.0,"Full"),(1.25,"Over!")], id: \.0) { pct, label in
                                    Button(action: { startPercentage = pct }) {
                                        Text(label).font(.system(size: 10))
                                            .foregroundColor(abs(startPercentage - pct) < 0.05 ? .white : .secondary)
                                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                                            .background(abs(startPercentage - pct) < 0.05
                                                        ? (pct > 1.0 ? Color.purple : Color.green)
                                                        : Color(.systemGray6))
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }

                if trackingMode == .count {
                    Section("Count Setup") {
                        HStack {
                            Text("Total I need").foregroundColor(.secondary)
                            Spacer()
                            Stepper("", value: $totalCount, in: 1...999).labelsHidden()
                            Text("\(totalCount)").font(.headline).fontWeight(.bold)
                                .frame(width: 44, alignment: .trailing)
                        }
                        HStack {
                            Text("Currently have").foregroundColor(.secondary)
                            Spacer()
                            Stepper("", value: $startCount, in: 0...999).labelsHidden()
                            Text("\(startCount)").font(.headline).fontWeight(.bold)
                                .foregroundColor(startCount > totalCount ? .purple
                                                 : startCount == 0 ? .red
                                                 : Double(startCount) / Double(totalCount) > 0.5 ? .green : .orange)
                                .frame(width: 44, alignment: .trailing)
                        }
                        let dotTotal = min(max(startCount, totalCount), 30)
                        HStack(spacing: 3) {
                            ForEach(0..<dotTotal, id: \.self) { i in
                                Circle()
                                    .fill(i < startCount
                                          ? (startCount > totalCount ? Color.purple : Color.green)
                                          : Color(.systemGray5))
                                    .frame(width: 12, height: 12)
                            }
                            if max(startCount, totalCount) > 30 {
                                Text("+\(max(startCount, totalCount) - 30)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }.padding(.vertical, 4)
                        if startCount > totalCount {
                            Label("Overstocked — \(startCount - totalCount) extra",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundColor(.purple)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Save" : "Add") {
                        guard !name.isEmpty else { return }
                        let item = FridgeItem(
                            id: existingItem?.id ?? UUID(),
                            name: name, emoji: emoji, location: location,
                            trackingMode: trackingMode,
                            percentageLeft: startPercentage,
                            count: startCount, totalCount: totalCount,
                            expiryDate: hasExpiry ? expiryDate : nil,
                            hasExpiry: hasExpiry
                        )
                        if isEditing { store.updateItem(item) } else { store.items.append(item) }
                        dismiss()
                    }.fontWeight(.bold).disabled(name.isEmpty)
                }
            }
            .onAppear {
                guard let item = existingItem else { location = defaultLocation; return }
                name = item.name; emoji = item.emoji; location = item.location
                trackingMode = item.trackingMode; startPercentage = item.percentageLeft
                startCount = item.count; totalCount = item.totalCount
                hasExpiry = item.hasExpiry
                if let d = item.expiryDate { expiryDate = d }
            }
        }
    }
}
