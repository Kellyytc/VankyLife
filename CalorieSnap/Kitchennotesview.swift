import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// My Kitchen Notes: one simple bullet list of things that are true every time you
// cook, e.g. "Oven runs hot, set 10°C lower" or "Mixer: knead on speed 2 for 5 min".
//
// Shown as a card at the top of Kitchen → Recipes, and (folded up) inside every recipe.
// Main app target only.
// ─────────────────────────────────────────────────────────────────────────────

struct KitchenNote: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String

    init(text: String) { self.text = text }

    enum CodingKeys: String, CodingKey { case id, text }
    init(from decoder: Decoder) throws {       // also reads notes saved by the earlier version
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

@MainActor
final class KitchenNotesStore: ObservableObject {
    static let shared = KitchenNotesStore()
    private let key = "kitchenNotes_v1"

    @Published var notes: [KitchenNote] = [] {
        didSet { if let d = try? JSONEncoder().encode(notes) { UserDefaults.standard.set(d, forKey: key) } }
    }

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([KitchenNote].self, from: d) {
            notes = decoded.filter { !$0.text.isEmpty }
        }
    }
}

// MARK: - Card at the top of Recipes

struct KitchenNotesCard: View {
    @ObservedObject private var store = KitchenNotesStore.shared

    var body: some View {
        NavigationLink {
            KitchenNotesView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "note.text")
                    .font(.title3).foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("My Kitchen Notes").font(.subheadline).fontWeight(.semibold)
                    Text(store.notes.first?.text ?? "Oven, mixer, anything you always do")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !store.notes.isEmpty {
                    Text("\(store.notes.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - The list

struct KitchenNotesView: View {
    @ObservedObject private var store = KitchenNotesStore.shared
    @State private var newNote = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•").foregroundStyle(.orange)
                    TextField("Add a note…", text: $newNote, axis: .vertical)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                    if !newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: add) { Image(systemName: "plus.circle.fill").font(.title3) }
                            .buttonStyle(.borderless)
                    }
                }
            } footer: {
                if store.notes.isEmpty {
                    Text("For example: \"Oven runs hot, set 10°C lower\", \"Mixer: knead bread dough on speed 2 for 5 min\".")
                }
            }

            if !store.notes.isEmpty {
                Section {
                    ForEach($store.notes) { $note in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("•").foregroundStyle(.orange)
                            TextField("Note", text: $note.text, axis: .vertical)
                        }
                    }
                    .onDelete { store.notes.remove(atOffsets: $0) }
                    .onMove { store.notes.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Tap a note to change it. Swipe left to delete. These show inside every recipe.")
                }
            }
        }
        .navigationTitle("My Kitchen Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.notes.isEmpty { EditButton() }
        }
        .onDisappear { store.notes.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    private func add() {
        let text = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.notes.append(KitchenNote(text: text))
        newNote = ""
        addFocused = true
    }
}

// MARK: - Inside a recipe

/// Your kitchen notes, folded up under each recipe's steps.
struct RecipeKitchenNotesSection: View {
    let recipeText: String          // kept so ReceiptsView doesn't need to change
    @ObservedObject private var store = KitchenNotesStore.shared
    @State private var expanded = false

    var body: some View {
        if !store.notes.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(store.notes) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.orange)
                            Text(note.text).font(.subheadline)
                        }
                    }
                    NavigationLink("Edit my kitchen notes") { KitchenNotesView() }
                        .font(.caption)
                } label: {
                    Label("My kitchen notes (\(store.notes.count))", systemImage: "note.text")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
