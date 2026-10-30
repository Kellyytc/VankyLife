import SwiftUI
import Combine
import MapKit
import CoreLocation
import UserNotifications

// ─────────────────────────────────────────────────────────────────────────────
// Kitchen → Shopping: a buy list for each store (Costco, T&T, Trader Joe's…),
// with a reminder when you get near one of that store's locations.
//
// Reminders use iOS location notifications: iPhone watches the store locations
// itself, even when Kelly Life is closed, and only needs "While Using the App"
// location permission. iOS allows about 20 watched places per app, so the
// closest locations are used.
// Needs "Privacy - Location When In Use Usage Description" in Info.
// Main app target only.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Models

struct ShopItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var isDone = false
}

struct ShopBranch: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct ShopList: Identifiable, Codable {
    var id = UUID()
    var name: String
    var emoji: String = "🛒"
    var items: [ShopItem] = []
    var branches: [ShopBranch] = []          // locations you picked yourself
    var remind = true
    /// "Any Star Market near me": the app keeps the closest branches of this store up to date.
    var anyBranch = true
    var nearby: [ShopBranch] = []            // found automatically around where you are
    var nearbyUpdated: Date?

    var openItems: [ShopItem] { items.filter { !$0.isDone } }

    /// Every location to watch: the ones you picked plus the nearby ones (no duplicates).
    var watchedBranches: [ShopBranch] {
        var seen = Set<String>()
        return (branches + (anyBranch ? nearby : [])).filter {
            seen.insert(String(format: "%.4f,%.4f", $0.latitude, $0.longitude)).inserted
        }
    }

    init(name: String, emoji: String = "🛒") { self.name = name; self.emoji = emoji }

    enum CodingKeys: String, CodingKey { case id, name, emoji, items, branches, remind, anyBranch, nearby, nearbyUpdated }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Store"
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🛒"
        items = try c.decodeIfPresent([ShopItem].self, forKey: .items) ?? []
        branches = try c.decodeIfPresent([ShopBranch].self, forKey: .branches) ?? []
        remind = try c.decodeIfPresent(Bool.self, forKey: .remind) ?? true
        anyBranch = try c.decodeIfPresent(Bool.self, forKey: .anyBranch) ?? true
        nearby = try c.decodeIfPresent([ShopBranch].self, forKey: .nearby) ?? []
        nearbyUpdated = try c.decodeIfPresent(Date.self, forKey: .nearbyUpdated)
    }
}

// MARK: - Storage + reminders

@MainActor
final class ShoppingStore: ObservableObject {
    static let shared = ShoppingStore()
    private let key = "shoppingLists_v1"

    @Published var lists: [ShopList] = [] {
        didSet { save(); GeoReminders.schedule(for: lists) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ShopList].self, from: data) {
            lists = decoded
        }
        GeoReminders.schedule(for: lists)   // refresh reminders (closest stores) each launch
    }

    private func save() {
        if let data = try? JSONEncoder().encode(lists) { UserDefaults.standard.set(data, forKey: key) }
    }

    func binding(for id: UUID) -> Binding<ShopList>? {
        guard lists.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.lists.first(where: { $0.id == id }) ?? ShopList(name: "") },
            set: { new in if let i = self.lists.firstIndex(where: { $0.id == id }) { self.lists[i] = new } }
        )
    }

    var totalOpenItems: Int { lists.reduce(0) { $0 + $1.openItems.count } }
}

/// Location notifications for every store that still has something to buy.
enum GeoReminders {
    private static let prefix = "shop-"
    static let radius: CLLocationDistance = 150      // metres around the store
    static let maxRegions = 20                       // iOS limit per app

    static func schedule(for lists: [ShopList]) {
        // Work out everything here first; the notification centre calls back on another thread.
        let here = CLLocationManager().location
        struct Place { let id: String; let title: String; let body: String; let lat: Double; let lon: Double; let distance: Double }
        var places: [Place] = []
        for list in lists where list.remind && !list.openItems.isEmpty {
            let names = list.openItems.map(\.name)
            var body = "Don't forget: " + names.prefix(6).joined(separator: ", ")
            if names.count > 6 { body += " and \(names.count - 6) more" }
            for b in list.watchedBranches {
                let d = here?.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) ?? 0
                places.append(Place(id: prefix + b.id.uuidString, title: "\(list.emoji) You're near \(b.name)",
                                    body: body, lat: b.latitude, lon: b.longitude, distance: d))
            }
        }
        places.sort { $0.distance < $1.distance }
        let chosen = Array(places.prefix(maxRegions))
        let tag = prefix
        let metres = radius

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(tag) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for p in chosen {
                let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon),
                                              radius: metres, identifier: p.id)
                region.notifyOnEntry = true
                region.notifyOnExit = false
                let content = UNMutableNotificationContent()
                content.title = p.title
                content.body = p.body
                content.sound = .default
                let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
                center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
            }
        }
    }
}

// MARK: - Permissions + current location

@MainActor
final class ShopLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = ShopLocation()
    private let manager = CLLocationManager()
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var notificationsAllowed = true
    @Published var isRefreshing = false
    /// "Update as I move": needs Always location so iPhone can wake Kelly Life after you've moved ~500 m+.
    @Published var followMe = UserDefaults.standard.bool(forKey: "shop.followMe")

    private var lastRefresh: (place: CLLocation, time: Date)?

    private override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    /// Call when the app starts: turns "Update as I move" back on.
    func resume() {
        if followMe && status == .authorizedAlways { manager.startMonitoringSignificantLocationChanges() }
    }

    func requestPermissions() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in self.notificationsAllowed = granted }
        }
    }

    func setFollowMe(_ on: Bool) {
        followMe = on
        UserDefaults.standard.set(on, forKey: "shop.followMe")
        if on {
            if manager.authorizationStatus != .authorizedAlways { manager.requestAlwaysAuthorization() }
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    var canRemind: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    // MARK: Delegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s == .authorizedWhenInUse || s == .authorizedAlways { await self.refreshNearby(force: true) }
        }
    }

    /// Significant move (only with "Update as I move"): find the closest branches around the new spot.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in await self.refreshNearby(at: loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Location

    /// Where you are now. Gives up after a few seconds (nil) instead of waiting forever,
    /// e.g. when location permission hasn't been answered yet or is turned off.
    func currentLocation(timeout: Double = 6) async -> CLLocation? {
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -600 { return recent }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            return manager.location
        default:
            break
        }
        manager.requestLocation()   // one quick fix; the result also lands in manager.location
        let fallback = manager.location
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let loc = update.location { return loc }
                        if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? self.manager.location ?? fallback
        }
    }

    // MARK: Nearby branches ("any Star Market near me")

    /// Finds the closest branches of every "any location" store around you.
    /// Skips the search if you haven't moved 1 km and it's been under 30 minutes, unless forced.
    func refreshNearby(force: Bool = false) async {
        guard canRemind, let here = await currentLocation() else { return }
        await refreshNearby(at: here, force: force)
    }

    func refreshNearby(at here: CLLocation, force: Bool = false) async {
        if !force, let last = lastRefresh, here.distance(from: last.place) < 1000, Date().timeIntervalSince(last.time) < 1800 { return }
        let store = ShoppingStore.shared
        let wanted = store.lists.filter { $0.anyBranch && !$0.openItems.isEmpty }
        guard !wanted.isEmpty, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastRefresh = (here, Date())

        var updated = store.lists
        for list in wanted {
            let found = await Self.branches(named: list.name, near: here)
            guard let i = updated.firstIndex(where: { $0.id == list.id }) else { continue }
            updated[i].nearby = found
            updated[i].nearbyUpdated = Date()
        }
        store.lists = updated          // saves and re-schedules the reminders
    }

    /// Up to 8 closest places whose name matches the store (e.g. every "Star Market" within ~15 km).
    static func branches(named name: String, near here: CLLocation) async -> [ShopBranch] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        func simple(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "&" } }
        let key = simple(name)
        var out: [(ShopBranch, Double)] = []
        for item in response.mapItems {
            let title = item.name ?? ""
            guard simple(title).contains(key) || key.contains(simple(title)) && !simple(title).isEmpty else { continue }
            let c = item.placemark.coordinate
            let d = here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            guard d < 25_000 else { continue }
            out.append((ShopBranch(name: title, address: item.placemark.title ?? "", latitude: c.latitude, longitude: c.longitude), d))
        }
        return out.sorted { $0.1 < $1.1 }.prefix(8).map(\.0)
    }
}

// MARK: - Shopping lists

struct ShoppingView: View {
    @ObservedObject private var store = ShoppingStore.shared
    @ObservedObject private var location = ShopLocation.shared
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if !location.canRemind && !store.lists.isEmpty {
                    Section {
                        Button {
                            if location.status == .denied || location.status == .restricted {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            } else {
                                location.requestPermissions()
                            }
                        } label: {
                            Label(location.status == .denied ? "Turn on Location in Settings for store reminders"
                                                             : "Allow location for store reminders",
                                  systemImage: "location.circle")
                        }
                    } footer: {
                        Text("Kelly Life only uses your location to remind you when you're near a store on your lists.")
                    }
                }

                if location.canRemind && !store.lists.isEmpty {
                    Section {
                        Toggle(isOn: Binding(get: { location.followMe }, set: { location.setFollowMe($0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update as I move")
                                Text(location.followMe && location.status != .authorizedAlways
                                     ? "Choose \"Always\" for Location in Settings so this works in the background."
                                     : "Keeps finding the nearest stores while you're out, even when Kelly Life is closed.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.green)
                    }
                }

                if store.lists.isEmpty {
                    ContentUnavailableView {
                        Label("No shopping lists", systemImage: "cart")
                    } description: {
                        Text("Add a store like Costco or Trader Joe's, list what to buy there, and get a reminder when you're nearby.")
                    } actions: {
                        Button("Add a store") { showAdd = true }.buttonStyle(.borderedProminent).tint(.green)
                    }
                } else {
                    Section {
                        ForEach(store.lists) { list in
                            NavigationLink {
                                ShopListDetailView(listID: list.id)
                            } label: {
                                ShopListRow(list: list)
                            }
                        }
                        .onDelete { store.lists.remove(atOffsets: $0) }
                    } footer: {
                        Text("You'll get a reminder within about \(Int(GeoReminders.radius)) m of one of the store's branches while its list has items.")
                    }
                }
            }
            .navigationTitle("Shopping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddShopListView() }
            .onAppear { location.status = CLLocationManager().authorizationStatus }
        }
    }
}

private struct ShopListRow: View {
    let list: ShopList
    var body: some View {
        HStack(spacing: 12) {
            Text(list.emoji).font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name).font(.headline)
                let open = list.openItems
                Text(open.isEmpty ? "Nothing to buy" : open.prefix(4).map(\.name).joined(separator: ", ") + (open.count > 4 ? "…" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    Label("\(list.watchedBranches.count)", systemImage: "mappin.and.ellipse")
                    if list.remind && !list.watchedBranches.isEmpty && !open.isEmpty {
                        Label("Reminder on", systemImage: "bell.fill").foregroundStyle(.green)
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !list.openItems.isEmpty {
                Text("\(list.openItems.count)")
                    .font(.subheadline).fontWeight(.bold)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color.green.opacity(0.15)).foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - New store list

private struct AddShopListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ShoppingStore.shared
    @State private var name = ""
    @State private var emoji = "🛒"
    private let emojis = ["🛒", "🥬", "🍎", "🥩", "🐟", "🍞", "🧴", "💊", "🏠", "🍜", "🧋", "🌸"]
    private let suggestions = ["Costco", "Trader Joe's", "Whole Foods", "Target", "H Mart", "T&T", "Walmart", "CVS"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Store") {
                    TextField("Store name (e.g. Costco)", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestions, id: \.self) { s in
                                Button(s) { name = s }
                                    .font(.caption).buttonStyle(.bordered)
                            }
                        }
                    }
                }
                Section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(emojis, id: \.self) { e in
                                Text(e).font(.title2).padding(6)
                                    .background(emoji == e ? Color.green.opacity(0.2) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture { emoji = e }
                            }
                        }
                    }
                }
                Section {
                    Text("Next you can add what to buy and which locations to be reminded at.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Store List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        store.lists.append(ShopList(name: n, emoji: emoji))
                        ShopLocation.shared.requestPermissions()
                        Task { await ShopLocation.shared.refreshNearby(force: true) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - One store

struct ShopListDetailView: View {
    let listID: UUID
    @ObservedObject private var store = ShoppingStore.shared
    @ObservedObject private var location = ShopLocation.shared
    @State private var newItem = ""
    @State private var showFindBranch = false
    @FocusState private var adding: Bool

    var body: some View {
        if let list = store.binding(for: listID) {
            List {
                Section {
                    HStack {
                        TextField("Add item (e.g. milk, 鸡蛋)", text: $newItem)
                            .focused($adding)
                            .onSubmit { add(to: list) }
                        Button { add(to: list) } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                            .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(list.items) { $item in
                        Button {
                            item.isDone.toggle()
                        } label: {
                            HStack {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? .green : .secondary)
                                Text(item.name)
                                    .strikethrough(item.isDone)
                                    .foregroundStyle(item.isDone ? .secondary : .primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { list.wrappedValue.items.remove(atOffsets: $0) }
                } header: {
                    Text("To buy")
                } footer: {
                    HStack {
                        if list.wrappedValue.items.contains(where: \.isDone) {
                            Button("Clear bought items") { list.wrappedValue.items.removeAll(where: \.isDone) }
                        }
                        Spacer()
                        Button("Add running-low fridge items") { addFromFridge(to: list) }
                    }
                    .font(.caption)
                }

                Section {
                    Toggle(isOn: list.remind) {
                        Label("Remind me when I'm nearby", systemImage: "bell")
                    }
                    .tint(.green)
                    Toggle(isOn: Binding(
                        get: { list.wrappedValue.anyBranch },
                        set: { on in
                            list.wrappedValue.anyBranch = on
                            if on { Task { await ShopLocation.shared.refreshNearby(force: true) } }
                        })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Any \(list.wrappedValue.name) near me")
                            Text("Finds the closest branches wherever you are")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
                } header: {
                    Text("Reminders")
                }

                if list.wrappedValue.anyBranch {
                    Section {
                        if list.wrappedValue.nearby.isEmpty {
                            Text(list.wrappedValue.openItems.isEmpty
                                 ? "Add something to buy and Kelly Life will look for nearby branches."
                                 : "No \(list.wrappedValue.name) found near you yet.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(list.wrappedValue.nearby) { b in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.name).font(.subheadline)
                                Text(b.address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            Task { await ShopLocation.shared.refreshNearby(force: true) }
                        } label: {
                            Label(location.isRefreshing ? "Looking…" : "Look again from here", systemImage: "location.magnifyingglass")
                        }
                        .disabled(location.isRefreshing)
                    } header: {
                        Text("Nearby branches")
                    } footer: {
                        if let when = list.wrappedValue.nearbyUpdated {
                            Text("Updated \(when.formatted(.relative(presentation: .named))). Updates whenever you open Kelly Life\(location.followMe ? " and as you move around" : ""). Turn on \"Update as I move\" on the Shopping page to keep it fresh in the background.")
                        }
                    }
                }

                Section {
                    ForEach(list.wrappedValue.branches) { b in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.name).font(.subheadline)
                            Text(b.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { list.wrappedValue.branches.remove(atOffsets: $0) }
                    Button {
                        showFindBranch = true
                    } label: {
                        Label("Add a specific location", systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("Saved locations")
                } footer: {
                    Text("Optional: always watch particular branches, e.g. the one near home or work. Reminders stop when everything on the list is ticked off.")
                }
            }
            .navigationTitle("\(list.wrappedValue.emoji) \(list.wrappedValue.name)")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFindBranch) {
                FindBranchView(storeName: list.wrappedValue.name) { picked in
                    let existing = Set(list.wrappedValue.branches.map { "\($0.latitude),\($0.longitude)" })
                    for b in picked where !existing.contains("\(b.latitude),\(b.longitude)") {
                        list.wrappedValue.branches.append(b)
                    }
                    ShopLocation.shared.requestPermissions()
                }
            }
        } else {
            ContentUnavailableView("List deleted", systemImage: "cart")
        }
    }

    private func add(to list: Binding<ShopList>) {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let wasEmpty = list.wrappedValue.openItems.isEmpty
        list.wrappedValue.items.insert(ShopItem(name: name), at: 0)
        newItem = ""
        if wasEmpty && list.wrappedValue.anyBranch { Task { await ShopLocation.shared.refreshNearby(force: true) } }
        adding = true
    }

    /// Fridge items that are empty or running low and not already on this list.
    private func addFromFridge(to list: Binding<ShopList>) {
        let have = Set(list.wrappedValue.items.filter { !$0.isDone }.map { $0.name.lowercased() })
        for item in FridgeReader.items() where item.isLow && !have.contains(item.name.lowercased()) {
            list.wrappedValue.items.append(ShopItem(name: item.name))
        }
    }
}

// MARK: - Find a store location

private struct FindBranchView: View {
    let storeName: String
    let onAdd: ([ShopBranch]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [(branch: ShopBranch, distance: Double?)] = []
    @State private var picked: Set<UUID> = []
    @State private var searching = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Store name or address", text: $query)
                            .onSubmit { Task { await search() } }
                        Button("Search") { Task { await search() } }
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Shows locations near you. Pick every branch you might shop at.")
                }
                if searching {
                    HStack { ProgressView(); Text("Searching nearby…").foregroundStyle(.secondary) }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results, id: \.branch.id) { r in
                            Button {
                                if picked.contains(r.branch.id) { picked.remove(r.branch.id) } else { picked.insert(r.branch.id) }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: picked.contains(r.branch.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(picked.contains(r.branch.id) ? .green : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.branch.name).font(.subheadline)
                                        Text(r.branch.address).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let d = r.distance {
                                        Text(distanceText(d)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(picked.count)") {
                        onAdd(results.map(\.branch).filter { picked.contains($0.id) })
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(picked.isEmpty)
                }
            }
            .task {
                query = storeName
                await search()
            }
        }
    }

    private func distanceText(_ metres: Double) -> String {
        let miles = metres / 1609.34
        return miles < 0.1 ? "nearby" : String(format: "%.1f mi", miles)
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        message = nil
        let here = await ShopLocation.shared.currentLocation()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.pointOfInterest, .address]
        if let here {
            request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            var found: [(branch: ShopBranch, distance: Double?)] = []
            for item in response.mapItems {
                let coord = item.placemark.coordinate
                let branch = ShopBranch(name: item.name ?? q,
                                        address: item.placemark.title ?? "",
                                        latitude: coord.latitude, longitude: coord.longitude)
                let distance = here.map { $0.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) }
                found.append((branch, distance))
            }
            found.sort { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }
            results = Array(found.prefix(15))
            if results.isEmpty { message = "No places found. Try a different name or an address." }
            if here == nil { message = "Location is off, so results aren't sorted by distance." }
        } catch {
            results = []
            message = "Couldn't search right now. Check your internet connection."
        }
    }
}
