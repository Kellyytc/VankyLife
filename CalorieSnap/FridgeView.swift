import SwiftUI
import Combine

// MARK: - Models

struct FridgeItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var quantity: String
    var expiryDate: Date?
    var location: FridgeLocation
    var emoji: String
    var percentageLeft: Double = 1.0
}

enum FridgeLocation: String, Codable, CaseIterable {
    case fridge = "Fridge"
    case freezer = "Freezer"
    case storage = "Storage"

    var icon: String {
        switch self {
        case .fridge: return "🧊"
        case .freezer: return "❄️"
        case .storage: return "📦"
        }
    }
}

// MARK: - Store

class FridgeStore: ObservableObject {
    @Published var items: [FridgeItem] = [] { didSet { save() } }

    init() { load() }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "fridgeItems")
        }
    }
    func load() {
        if let data = UserDefaults.standard.data(forKey: "fridgeItems"),
           let items = try? JSONDecoder().decode([FridgeItem].self, from: data) {
            self.items = items
        }
    }
    func filteredItems(for location: FridgeLocation) -> [FridgeItem] {
        items.filter { $0.location == location }
    }
    func updatePercentage(id: UUID, percentage: Double) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].percentageLeft = percentage
        }
    }
}

// MARK: - Fridge View

struct FridgeView: View {
    @StateObject private var store = FridgeStore()
    @State private var showAddItem = false
    @State private var selectedLocation: FridgeLocation = .fridge

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Location", selection: $selectedLocation) {
                    ForEach(FridgeLocation.allCases, id: \.self) { loc in
                        Text(loc.icon + " " + loc.rawValue).tag(loc)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                let items = store.filteredItems(for: selectedLocation)

                if items.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Text(selectedLocation.icon).font(.system(size: 60))
                        Text("\(selectedLocation.rawValue) is empty").font(.title3).foregroundColor(.secondary)
                        Text("Tap + to add items").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(items) { item in
                                FridgeItemCard(item: item, store: store)
                            }
                        }
                        .padding(.horizontal).padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("My \(selectedLocation.rawValue)")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddItem = true }) { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddFridgeItemView(store: store, defaultLocation: selectedLocation)
            }
        }
    }
}

// MARK: - Fridge Item Card

struct FridgeItemCard: View {
    let item: FridgeItem
    @ObservedObject var store: FridgeStore
    @State private var dragPercentage: Double = 1.0
    @State private var isDragging = false
    @State private var showEmptyAlert = false

    init(item: FridgeItem, store: FridgeStore) {
        self.item = item
        self.store = store
        _dragPercentage = State(initialValue: item.percentageLeft)
    }

    var daysUntilExpiry: Int? {
        guard let expiry = item.expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }

    var expiryColor: Color {
        guard let days = daysUntilExpiry else { return .secondary }
        if days < 0 { return .red }
        if days <= 2 { return .orange }
        if days <= 5 { return .yellow }
        return .green
    }

    var expiryText: String {
        guard let days = daysUntilExpiry else { return "No expiry" }
        if days < 0 { return "Expired \(-days)d ago" }
        if days == 0 { return "Expires today!" }
        if days == 1 { return "Expires tomorrow" }
        return "\(days)d left"
    }

    var expiryIcon: String {
        guard let days = daysUntilExpiry else { return "infinity" }
        if days < 0 { return "exclamationmark.circle.fill" }
        if days <= 2 { return "exclamationmark.triangle.fill" }
        return "calendar"
    }

    var percentageColor: Color {
        if dragPercentage > 0.6 { return .green }
        if dragPercentage > 0.3 { return .orange }
        return .red
    }

    var percentageText: String {
        if dragPercentage <= 0.05 { return "Empty" }
        return "\(Int(dragPercentage * 100))%"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(item.emoji).font(.system(size: 36))
                    .frame(width: 50, height: 50)
                    .background(percentageColor.opacity(0.12)).cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.headline)
                    Text(item.quantity).font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(percentageText).font(.title3).fontWeight(.bold).foregroundColor(percentageColor)
                    HStack(spacing: 4) {
                        Image(systemName: expiryIcon).font(.system(size: 10)).foregroundColor(expiryColor)
                        Text(expiryText).font(.caption2).foregroundColor(expiryColor)
                    }
                }
            }

            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)).frame(height: 28)
                        RoundedRectangle(cornerRadius: 10).fill(percentageColor.opacity(0.2))
                            .frame(width: max(28, geo.size.width * CGFloat(dragPercentage)), height: 28)
                        RoundedRectangle(cornerRadius: 6).fill(percentageColor)
                            .frame(width: max(4, geo.size.width * CGFloat(dragPercentage) - 24), height: 10)
                            .padding(.leading, 12)
                        HStack(spacing: 0) {
                            Spacer().frame(width: max(14, geo.size.width * CGFloat(dragPercentage) - 14))
                            ZStack {
                                Circle().fill(Color.white).frame(width: 28, height: 28)
                                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                                Circle().fill(percentageColor).frame(width: 14, height: 14)
                            }
                        }
                        Color.clear.frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    dragPercentage = min(1.0, max(0.0, value.location.x / geo.size.width))
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    let snapped = (dragPercentage * 20).rounded() / 20
                                    dragPercentage = snapped
                                    if snapped <= 0.05 {
                                        showEmptyAlert = true
                                    } else {
                                        store.updatePercentage(id: item.id, percentage: snapped)
                                    }
                                }
                            )
                    }
                }.frame(height: 28)

                HStack(spacing: 4) {
                    ForEach([(0.0, "Empty"), (0.25, "25%"), (0.5, "Half"), (0.75, "75%"), (1.0, "Full")], id: \.0) { pct, label in
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                dragPercentage = pct
                                if pct <= 0.05 {
                                    showEmptyAlert = true
                                } else {
                                    store.updatePercentage(id: item.id, percentage: pct)
                                }
                            }
                        }) {
                            Text(label).font(.system(size: 11))
                                .foregroundColor(abs(dragPercentage - pct) < 0.01 ? .white : .secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                                .background(abs(dragPercentage - pct) < 0.01 ? percentageColor : Color(.systemGray6))
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding().background(.regularMaterial).cornerRadius(16)
        .opacity(dragPercentage <= 0.05 ? 0.5 : 1.0)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.items.removeAll { $0.id == item.id }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .onAppear { dragPercentage = item.percentageLeft }
        .alert("Item is Empty", isPresented: $showEmptyAlert) {
            Button("Delete Item", role: .destructive) {
                store.items.removeAll { $0.id == item.id }
            }
            Button("Keep It") {
                store.updatePercentage(id: item.id, percentage: 0.0)
            }
            Button("Cancel", role: .cancel) {
                dragPercentage = item.percentageLeft
            }
        } message: {
            Text("'\(item.name)' is empty. Would you like to remove it from your \(item.location.rawValue.lowercased())?")
        }
    }
}

// MARK: - Add Fridge Item View

struct AddFridgeItemView: View {
    @ObservedObject var store: FridgeStore
    var defaultLocation: FridgeLocation
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var quantity = ""
    @State private var expiryDate = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var hasExpiry = true
    @State private var location: FridgeLocation = .fridge
    @State private var emoji = "🥦"
    @State private var startPercentage: Double = 1.0

    let commonEmojis = [
        "🥦","🥕","🍎","🍊","🥩","🐟","🥛","🧀","🥚","🍗",
        "🥬","🧄","🧅","🍋","🍇","🫐","🥝","🍓","🌽","🥑",
        "🍞","🧈","🫙","🍜","🥟","🍱","🧆","🫒","🥜","🌶️",
        "🧂","🥫","🍶","🫚","🫛","🥡","🍣","🥩","📦","🛢️"
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
                    TextField("Item name (e.g. 豆腐, 老干妈, Milk)", text: $name)
                    TextField("Quantity (e.g. 2 packs, 500g, 1 jar)", text: $quantity)
                }

                Section("Storage Location") {
                    Picker("Location", selection: $location) {
                        ForEach(FridgeLocation.allCases, id: \.self) { loc in
                            Text(loc.icon + " " + loc.rawValue).tag(loc)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Has expiry date", isOn: $hasExpiry)

                    if hasExpiry {
                        DatePicker("Expiry Date", selection: $expiryDate, displayedComponents: .date)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "infinity").foregroundColor(.secondary).font(.system(size: 16))
                            Text("No expiry date").foregroundColor(.secondary).font(.subheadline)
                        }.padding(.vertical, 2)
                    }
                }

                Section("Starting Amount") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("How full is it?").foregroundColor(.secondary)
                            Spacer()
                            Text(startPercentage >= 1.0 ? "Full" : startPercentage <= 0.0 ? "Empty" : "\(Int(startPercentage * 100))%")
                                .fontWeight(.semibold)
                                .foregroundColor(startPercentage > 0.6 ? .green : startPercentage > 0.3 ? .orange : .red)
                        }
                        Slider(value: $startPercentage, in: 0...1, step: 0.05).tint(.green)
                        HStack(spacing: 4) {
                            ForEach([(0.25, "25%"), (0.5, "Half"), (0.75, "75%"), (1.0, "Full")], id: \.0) { pct, label in
                                Button(action: { startPercentage = pct }) {
                                    Text(label).font(.caption)
                                        .foregroundColor(abs(startPercentage - pct) < 0.01 ? .white : .secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                                        .background(abs(startPercentage - pct) < 0.01 ? Color.green : Color(.systemGray6))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
            .navigationTitle("Add Item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        guard !name.isEmpty else { return }
                        let item = FridgeItem(
                            name: name,
                            quantity: quantity.isEmpty ? "1" : quantity,
                            expiryDate: hasExpiry ? expiryDate : nil,
                            location: location,
                            emoji: emoji,
                            percentageLeft: startPercentage
                        )
                        store.items.append(item)
                        dismiss()
                    }.fontWeight(.bold).disabled(name.isEmpty)
                }
            }
            .onAppear { location = defaultLocation }
        }
    }
}
