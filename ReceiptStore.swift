import Foundation
import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// Recipes — storage shared with the KellyLifeShare extension via the App Group.
// (File keeps its old name "ReceiptStore.swift". It must be in BOTH targets.)
// ─────────────────────────────────────────────────────────────────────────────

class RecipeStore: ObservableObject {

    static let groupID = "group.com.kelly.kellylife"
    static let key     = "scannedReceipts"   // unchanged so already-saved items stay

    @Published var recipes: [SavedRecipe] = [] { didSet { save() } }

    init() { load() }

    var allTags: [String] { Array(Set(recipes.flatMap(\.tags))).sorted() }

    func save() {
        if let d = try? JSONEncoder().encode(recipes) {
            UserDefaults(suiteName: RecipeStore.groupID)?.set(d, forKey: RecipeStore.key)
        }
    }

    func load() {
        guard
            let d = UserDefaults(suiteName: RecipeStore.groupID)?.data(forKey: RecipeStore.key),
            let decoded = try? JSONDecoder().decode([SavedRecipe].self, from: d)
        else { return }
        recipes = decoded
    }

    func refresh() { load() }

    func update(_ recipe: SavedRecipe) {
        if let i = recipes.firstIndex(where: { $0.id == recipe.id }) { recipes[i] = recipe }
    }

    func delete(_ recipe: SavedRecipe) {
        recipes.removeAll { $0.id == recipe.id }
    }

    func toggleFavorite(_ recipe: SavedRecipe) {
        var r = recipe; r.isFavorite.toggle(); update(r)
    }
}

// Old name, so any existing references still compile.
typealias ReceiptStore = RecipeStore
