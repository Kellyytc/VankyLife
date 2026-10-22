import SwiftUI
import VisionKit
import Vision
import PhotosUI

// ─────────────────────────────────────────────────────────────────────────────
// Recipes tab. (File keeps its old name "ReceiptsView.swift" — main app only.)
// ─────────────────────────────────────────────────────────────────────────────

// Old name, so ContentView's `ReceiptsView()` still works.
typealias ReceiptsView = RecipesView

// MARK: - Kitchen tab (Fridge + Recipes in one tab)

enum KitchenSection: String, CaseIterable, Identifiable {
    case fridge = "Fridge"
    case recipes = "Recipes"
    var id: String { rawValue }
    var icon: String { self == .fridge ? "refrigerator" : "book.closed" }
}

struct KitchenView: View {
    @AppStorage("kitchenSection") private var section: KitchenSection = .fridge

    var body: some View {
        VStack(spacing: 0) {
            Picker("Kitchen", selection: $section) {
                ForEach(KitchenSection.allCases) { s in
                    Label(s.rawValue, systemImage: s.icon).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(Color(.systemGroupedBackground))

            switch section {
            case .fridge:  FridgeView()
            case .recipes: RecipesView()
            }
        }
    }
}

// MARK: - List

struct RecipesView: View {
    @StateObject private var store = RecipeStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var selectedTag: String? = nil
    @State private var favoritesOnly = false
    @State private var showNewRecipe = false

    private var filtered: [SavedRecipe] {
        store.recipes.filter { r in
            if favoritesOnly && !r.isFavorite { return false }
            if let tag = selectedTag, !r.tags.contains(tag) { return false }
            guard !searchText.isEmpty else { return true }
            return [r.displayTitle, r.note, r.keptText, r.tags.joined(separator: " ")]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.recipes.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                RecipeTagChip(text: "All", selected: selectedTag == nil && !favoritesOnly) {
                                    selectedTag = nil; favoritesOnly = false
                                }
                                RecipeTagChip(text: "♥ Favourites", selected: favoritesOnly) {
                                    favoritesOnly.toggle()
                                }
                                ForEach(store.allTags, id: \.self) { tag in
                                    RecipeTagChip(text: tag, selected: selectedTag == tag) {
                                        selectedTag = (selectedTag == tag) ? nil : tag
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    } footer: {
                        Text("\(filtered.count) recipe\(filtered.count == 1 ? "" : "s")")
                    }
                }

                Section {
                    ForEach(filtered) { r in
                        NavigationLink(value: r.id) { RecipeRow(recipe: r) }
                            .swipeActions(edge: .leading) {
                                Button { store.toggleFavorite(r) } label: {
                                    Image(systemName: r.isFavorite ? "heart.slash" : "heart.fill")
                                }
                                .tint(.pink)
                            }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { filtered[$0].id }
                        for id in ids {
                            if let r = store.recipes.first(where: { $0.id == id }) { store.delete(r) }
                        }
                    }
                }
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: UUID.self) { id in
                RecipeDetailView(store: store, recipeID: id)
            }
            .searchable(text: $searchText, prompt: "Search recipes or ingredients")
            .refreshable { store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewRecipe = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add recipe")
                }
            }
            .sheet(isPresented: $showNewRecipe) {
                NewRecipeView(existingTags: store.allTags) { recipe in
                    store.recipes.insert(recipe, at: 0)
                }
            }
            .overlay {
                if store.recipes.isEmpty {
                    ContentUnavailableView(
                        "No recipes yet",
                        systemImage: "fork.knife",
                        description: Text("Tap + to write one in, or share a recipe from Photos, Instagram or Safari to KellyLifeShare.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .onAppear { store.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.refresh() }
            }
        }
    }
}

// MARK: - Row

struct RecipeRow: View {
    let recipe: SavedRecipe

    var body: some View {
        let parsed = recipe.parsed
        HStack(spacing: 12) {
            Group {
                if let img = recipe.image {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "fork.knife").font(.title3).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.tertiarySystemFill))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(recipe.displayTitle).font(.headline).lineLimit(2)
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(recipe.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2).fontWeight(.medium)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    if recipe.tags.count > 2 {
                        Text("+\(recipe.tags.count - 2)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !parsed.isEmpty {
                        Text("\(parsed.ingredients.count) ingredients · \(parsed.steps.count) steps")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct RecipeDetailView: View {
    @ObservedObject var store: RecipeStore
    let recipeID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var showImage = false
    @State private var showLines = false
    @State private var confirmDelete = false
    @State private var checkedIngredients: Set<Int> = []
    @State private var showFullText = false

    private var recipe: SavedRecipe? { store.recipes.first { $0.id == recipeID } }

    var body: some View {
        if let r = recipe {
            let parsed = r.parsed
            List {
                if let img = r.image {
                    Section {
                        Button { showImage = true } label: {
                            Image(uiImage: img)
                                .resizable().scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    } footer: {
                        Text("Tap the photo to zoom in and select text.")
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Text(r.displayTitle).font(.title3).fontWeight(.bold)
                    if !r.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(r.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption).fontWeight(.medium)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    if !r.note.isEmpty {
                        Text(r.note).font(.subheadline)
                    }
                }

                if !parsed.ingredients.isEmpty {
                    Section {
                        ForEach(Array(parsed.ingredients.enumerated()), id: \.offset) { i, item in
                            Button {
                                if checkedIngredients.contains(i) { checkedIngredients.remove(i) }
                                else { checkedIngredients.insert(i) }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: checkedIngredients.contains(i) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(checkedIngredients.contains(i) ? .green : .secondary)
                                    Text(item)
                                        .strikethrough(checkedIngredients.contains(i))
                                        .foregroundStyle(checkedIngredients.contains(i) ? .secondary : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Ingredients")
                    } footer: {
                        Text("Tap an ingredient to tick it off while you cook.")
                    }
                }

                if !parsed.steps.isEmpty {
                    Section("Steps") {
                        ForEach(Array(parsed.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.caption).fontWeight(.bold)
                                    .frame(width: 22, height: 22)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(.orange)
                                    .clipShape(Circle())
                                Text(step).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    if parsed.isEmpty || showFullText {
                        Text(r.keptText.isEmpty ? "No text kept" : r.keptText)
                            .font(.footnote)
                            .foregroundStyle(r.keptText.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                    if !parsed.isEmpty {
                        Button(showFullText ? "Hide full text" : "Show full text") {
                            showFullText.toggle()
                        }
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Label("Edit recipe", systemImage: "pencil")
                    }
                    Button {
                        showLines = true
                    } label: {
                        Label("Choose text to keep", systemImage: "text.badge.checkmark")
                    }
                } header: {
                    Text("Text")
                } footer: {
                    Text("\(r.lines.filter(\.kept).count) of \(r.lines.count) lines kept. Press and hold the text to copy it.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete recipe", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.toggleFavorite(r) } label: {
                        Image(systemName: r.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(.pink)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }
                }
            }
            .confirmationDialog("Delete this recipe?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.delete(r); dismiss() }
            }
            .sheet(isPresented: $showEdit) {
                RecipeEditView(recipe: r, existingTags: store.allTags) { store.update($0) }
            }
            .sheet(isPresented: $showLines) {
                RecipeLinePickerView(recipe: r) { updated in
                    store.update(updated)
                    checkedIngredients = []
                }
            }
            .fullScreenCover(isPresented: $showImage) {
                if let img = r.image { RecipeImageViewer(image: img) }
            }
        } else {
            ContentUnavailableView("Recipe not found", systemImage: "fork.knife")
        }
    }
}

// MARK: - New recipe (typed in by hand, optional photo)

struct NewRecipeView: View {
    let existingTags: [String]
    let onSave: (SavedRecipe) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var note = ""
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var ingredients = ""
    @State private var steps = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isReading = false
    @State private var readMessage: String?

    private var tagChoices: [String] {
        var seen = Set<String>(); var out: [String] = []
        for t in RecipeParser.presetTags + existingTags + tags where seen.insert(t).inserted { out.append(t) }
        return out
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !ingredients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !steps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowBackground(Color.clear)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photo == nil ? "Add a photo" : "Change photo", systemImage: "photo")
                    }
                    if photo != nil {
                        Button {
                            Task { await readTextFromPhoto() }
                        } label: {
                            HStack {
                                Label("Read text from photo", systemImage: "text.viewfinder")
                                if isReading { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(isReading)
                        Button("Remove photo", role: .destructive) { photo = nil; photoItem = nil }
                    }
                } header: {
                    Text("Photo (optional)")
                } footer: {
                    if let readMessage {
                        Text(readMessage)
                    } else {
                        Text("Add a photo of the dish, or of a recipe page and tap Read text from photo to fill in the boxes below.")
                    }
                }

                Section("Recipe") {
                    TextField("Title (e.g. Tomato egg stir-fry)", text: $title)
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(1...4)
                }

                Section {
                    editor($ingredients, placeholder: "2 eggs\n3 tomatoes\n1 tsp sugar")
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("One ingredient per line.")
                }

                Section {
                    editor($steps, placeholder: "Beat the eggs\nCut the tomatoes\nStir-fry together")
                } header: {
                    Text("Steps")
                } footer: {
                    Text("One step per line. They're numbered for you.")
                }

                Section("Tags") {
                    FlowLayout(spacing: 8) {
                        ForEach(tagChoices, id: \.self) { tag in
                            RecipeTagChip(text: tag, selected: tags.contains(tag)) {
                                if let i = tags.firstIndex(of: tag) { tags.remove(at: i) } else { tags.append(tag) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        TextField("Add your own tag", text: $newTag).onSubmit(addTag)
                        Button("Add", action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!canSave)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        photo = img
                        readMessage = nil
                    }
                }
            }
        }
    }

    private func editor(_ text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8).padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .frame(minHeight: 120)
        }
        .font(.subheadline)
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if !tags.contains(t) { tags.append(t) }
        newTag = ""
    }

    private static func cleanLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Removes a leading bullet ("- ", "• ") so we can add our own. Amounts like "1.5 cups" stay intact.
    private static func stripBullet(_ line: String) -> String {
        line.replacingOccurrences(of: #"^\s*[-•*·▪◦]\s*"#, with: "", options: .regularExpression)
    }

    /// Removes a leading step number ("1. ", "2) ", "Step 3: ", "4、") so we can number steps ourselves.
    private static func stripNumber(_ line: String) -> String {
        line.replacingOccurrences(of: #"^\s*(?:[-•*·▪◦]\s*|(?:step\s*)?\d{1,2}\s*(?:[.):：]\s+|、\s*))"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
    }

    private func save() {
        let ingredientLines = Self.cleanLines(ingredients).map { "- " + Self.stripBullet($0) }
        let stepLines = Self.cleanLines(steps).enumerated().map { "\($0.offset + 1). " + Self.stripNumber($0.element) }
        let all = ingredientLines + stepLines
        let recipe = SavedRecipe(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            rawText: all.joined(separator: "\n"),
            lines: all.map { RecipeLine(text: $0) },
            tags: tags,
            imageData: photo.flatMap { RecipeParser.downscaled($0).jpegData(compressionQuality: 0.6) },
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onSave(recipe)
        dismiss()
    }

    private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    /// Reads the text in the photo and sorts it into ingredients and steps.
    private func readTextFromPhoto() async {
        guard let image = photo, let cg = image.cgImage else { return }
        let orientation = Self.cgOrientation(image.imageOrientation)
        isReading = true
        defer { isReading = false }
        let lines: [String] = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]
            try? VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value

        guard !lines.isEmpty else { readMessage = "No text found in this photo."; return }
        let parsed = RecipeParser.parse(lines)
        if title.isEmpty { title = RecipeParser.detectTitle(in: lines) }
        if parsed.isEmpty {
            steps = lines.joined(separator: "\n")
            readMessage = "Couldn't tell ingredients from steps, so all the text went into Steps. Move lines as needed."
        } else {
            if !parsed.ingredients.isEmpty { ingredients = parsed.ingredients.joined(separator: "\n") }
            if !parsed.steps.isEmpty { steps = parsed.steps.joined(separator: "\n") }
            readMessage = "Found \(parsed.ingredients.count) ingredients and \(parsed.steps.count) steps. Check them before saving."
        }
    }
}

// MARK: - Edit title, tags, note

struct RecipeEditView: View {
    let recipe: SavedRecipe
    let existingTags: [String]
    let onSave: (SavedRecipe) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var tags: [String]
    @State private var note: String
    @State private var text: String
    @State private var newTag = ""

    init(recipe: SavedRecipe, existingTags: [String], onSave: @escaping (SavedRecipe) -> Void) {
        self.recipe = recipe
        self.existingTags = existingTags
        self.onSave = onSave
        _title = State(initialValue: recipe.title.isEmpty ? recipe.displayTitle : recipe.title)
        _tags  = State(initialValue: recipe.tags)
        _note  = State(initialValue: recipe.note)
        _text  = State(initialValue: recipe.keptText)
    }

    private var preview: RecipeParser.Parsed {
        RecipeParser.parse(text.components(separatedBy: "\n"))
    }

    private var tagChoices: [String] {
        var seen = Set<String>(); var out: [String] = []
        for t in RecipeParser.presetTags + existingTags + tags where seen.insert(t).inserted { out.append(t) }
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Title (e.g. Roti Canai)", text: $title)
                    TextField("Note (e.g. from @sheldo, try with curry)", text: $note, axis: .vertical)
                        .lineLimit(1...5)
                }
                Section("Tags") {
                    FlowLayout(spacing: 8) {
                        ForEach(tagChoices, id: \.self) { tag in
                            RecipeTagChip(text: tag, selected: tags.contains(tag)) {
                                if let i = tags.firstIndex(of: tag) { tags.remove(at: i) } else { tags.append(tag) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        TextField("Add your own tag", text: $newTag).onSubmit(addTag)
                        Button("Add", action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    TextEditor(text: $text)
                        .font(.subheadline)
                        .frame(minHeight: 260)
                } header: {
                    Text("Recipe text")
                } footer: {
                    Text("Fix any words the photo got wrong. Start ingredients with \"- \" and steps with \"1. \" so they're sorted automatically. Now: \(preview.ingredients.count) ingredients · \(preview.steps.count) steps.")
                }
            }
            .navigationTitle("Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var r = recipe
                        r.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        r.tags = tags
                        r.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        if text != recipe.keptText {
                            // Text was edited: it becomes the recipe's text (all lines kept).
                            let newLines = text.components(separatedBy: "\n")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            r.lines = newLines.map { RecipeLine(text: $0) }
                            r.rawText = newLines.joined(separator: "\n")
                        }
                        onSave(r); dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if !tags.contains(t) { tags.append(t) }
        newTag = ""
    }
}

// MARK: - Choose which text lines to keep

struct RecipeLinePickerView: View {
    let recipe: SavedRecipe
    let onSave: (SavedRecipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [RecipeLine]

    init(recipe: SavedRecipe, onSave: @escaping (SavedRecipe) -> Void) {
        self.recipe = recipe
        self.onSave = onSave
        _lines = State(initialValue: recipe.lines)
    }

    private var preview: RecipeParser.Parsed {
        RecipeParser.parse(lines.filter(\.kept).map(\.text))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($lines) { $line in
                        Button { line.kept.toggle() } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: line.kept ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(line.kept ? .green : .secondary)
                                Text(line.text)
                                    .font(.subheadline)
                                    .foregroundStyle(line.kept ? .primary : .secondary)
                                    .strikethrough(!line.kept)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Keep only from here down", systemImage: "arrow.down.to.line") {
                                keep(from: line.id, down: true)
                            }
                            Button("Keep only up to here", systemImage: "arrow.up.to.line") {
                                keep(from: line.id, down: false)
                            }
                        }
                    }
                } header: {
                    Text("Found \(preview.ingredients.count) ingredients · \(preview.steps.count) steps")
                } footer: {
                    Text("Tap a line to keep or remove it. Press and hold a line to keep everything above or below it.")
                }
            }
            .navigationTitle("Choose Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var r = recipe
                        r.lines = lines
                        r.rawText = lines.filter(\.kept).map(\.text).joined(separator: "\n")
                        onSave(r); dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu("Select") {
                        Button("Keep all") { setAll(true) }
                        Button("Remove all") { setAll(false) }
                    }
                }
            }
        }
    }

    private func setAll(_ kept: Bool) {
        for i in lines.indices { lines[i].kept = kept }
    }

    private func keep(from id: UUID, down: Bool) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        for i in lines.indices { lines[i].kept = down ? i >= idx : i <= idx }
    }
}

// MARK: - Tag chip

struct RecipeTagChip: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Color.orange : Color(.tertiarySystemFill))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-screen photo with zoom + Live Text selection

struct RecipeImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            RecipeLiveTextImage(image: image).ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
    }
}

/// Zoomable photo with VisionKit Live Text, so you can press on words to select and copy them.
struct RecipeLiveTextImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> RecipeZoomScrollView {
        let view = RecipeZoomScrollView(image: image)
        if ImageAnalyzer.isSupported {
            let interaction = ImageAnalysisInteraction()
            view.imageView.addInteraction(interaction)
            Task { @MainActor in
                let analyzer = ImageAnalyzer()
                let config = ImageAnalyzer.Configuration([.text])
                if let analysis = try? await analyzer.analyze(image, configuration: config) {
                    interaction.analysis = analysis
                    interaction.preferredInteractionTypes = .textSelection
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: RecipeZoomScrollView, context: Context) {}
}

final class RecipeZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()

    init(image: UIImage) {
        super.init(frame: .zero)
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 {
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}
