import UIKit
import SwiftUI
import Combine
import Vision
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// KellyLifeShare — save a recipe from Photos / Safari / Instagram screenshots.
// Reads the text in the shared image, then lets you set a title, tags and note
// and choose which lines of text to keep. Self-contained on purpose.
// Saves into the App Group using the same JSON keys as SavedRecipe.
// ─────────────────────────────────────────────────────────────────────────────

private let kGroupID = "group.com.kelly.kellylife"
private let kKey     = "scannedReceipts"   // same key the main app reads

private let kPresetTags = [
    "Breakfast", "Lunch", "Dinner", "Dessert", "Snack", "Drink", "Baking",
    "Soup", "Noodles", "Rice", "Chinese", "Asian", "Western", "Healthy",
    "Quick", "Try later"
]

// MARK: - Codable mirror of SavedRecipe (same keys)

private struct SRLine: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var kept: Bool = true
}

private struct SRRecipe: Codable {
    var id = UUID()
    var title: String
    var rawText: String
    var lines: [SRLine]
    var tags: [String]
    var imageData: Data?
    var createdAt = Date()
    var note: String
    var isFavorite = false
}

/// Inserts at the front of the stored array without re-decoding older entries.
private func saveToGroup(_ recipe: SRRecipe) -> Bool {
    guard let defaults = UserDefaults(suiteName: kGroupID),
          let newData = try? JSONEncoder().encode(recipe),
          let newObj = try? JSONSerialization.jsonObject(with: newData) else { return false }
    var all: [Any] = []
    if let d = defaults.data(forKey: kKey),
       let existing = try? JSONSerialization.jsonObject(with: d) as? [Any] {
        all = existing
    }
    all.insert(newObj, at: 0)
    guard let out = try? JSONSerialization.data(withJSONObject: all) else { return false }
    defaults.set(out, forKey: kKey)
    return true
}

// MARK: - Small text helpers

private enum SRText {
    static let stepRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:step\s*)?(\d{1,2})\s*(?:[.)、]|[:：](?=\s))\s*(\D.*)$"#, options: .caseInsensitive)
    static let bulletRegex = try! NSRegularExpression(pattern: #"^\s*[-•*·▪◦]\s*(.+)$"#)
    static let quantityRegex = try! NSRegularExpression(
        pattern: #"^\s*(\d+(?:[./]\d+)?|½|¼|¾|⅓|一|两|半)\s*(g|kg|mg|ml|l|tbsp|tsp|cups?|oz|lbs?|pcs?|cloves?|克|毫升|勺|汤匙|茶匙|个|片|根|颗|瓣)(?![A-Za-z])"#,
        options: .caseInsensitive)
    static let headerRegex = try! NSRegularExpression(
        pattern: #"^(ingredients?|method|directions?|instructions?|steps?|材料|配料|食材|做法|步骤)\s*[:：]?$"#,
        options: .caseInsensitive)
    static let timeRegex = try! NSRegularExpression(pattern: #"^\s*\d{1,2}:\d{2}"#)

    static func has(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
    static func isIngredient(_ s: String) -> Bool { has(bulletRegex, s) || has(quantityRegex, s) }

    static func counts(_ lines: [String]) -> (ingredients: Int, steps: Int) {
        (lines.filter { isIngredient($0) }.count, lines.filter { has(stepRegex, $0) }.count)
    }

    static func title(in lines: [String]) -> String {
        func ok(_ s: String) -> Bool {
            let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            return letters >= 3 && s.count <= 60 && !has(timeRegex, s) && !has(headerRegex, s)
                && !isIngredient(s) && !has(stepRegex, s)
        }
        if let first = lines.firstIndex(where: { isIngredient($0) }) {
            for j in stride(from: first - 1, through: max(0, first - 2), by: -1) where ok(lines[j]) {
                return lines[j]
            }
        }
        return lines.prefix(10).first(where: { ok($0) && $0.lowercased() != "saved" }) ?? ""
    }

    static func downscaled(_ image: UIImage, maxSide: CGFloat = 1600) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let s = maxSide / side
        let size = CGSize(width: image.size.width * s, height: image.size.height * s)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Form model

@MainActor
private final class ShareModel: ObservableObject {
    enum Phase: Equatable { case loading(String), form, saved, failed(String) }

    @Published var phase: Phase = .loading("Opening image…")
    @Published var title = ""
    @Published var note = ""
    @Published var tags: [String] = []
    @Published var lines: [SRLine] = []
    var image: UIImage?

    var keptLines: [String] { lines.filter(\.kept).map(\.text) }

    func load(lines raw: [String], image: UIImage) {
        let clean = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.image = image
        self.lines = clean.map { SRLine(text: $0) }
        self.title = SRText.title(in: clean)
        phase = .form
    }

    func toggleTag(_ tag: String) {
        if let i = tags.firstIndex(of: tag) { tags.remove(at: i) } else { tags.append(tag) }
    }

    func makeRecipe() -> SRRecipe {
        SRRecipe(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            rawText: keptLines.joined(separator: "\n"),
            lines: lines,
            tags: tags,
            imageData: image.flatMap { SRText.downscaled($0).jpegData(compressionQuality: 0.6) },
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - View controller

class ShareViewController: UIViewController {

    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareRootView(
            model: model,
            onCancel: { [weak self] in self?.close() },
            onSave:   { [weak self] in self?.save() }
        )
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        loadSharedItem()
    }

    private func loadSharedItem() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            model.phase = .failed("Nothing to save"); return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            _ = provider.loadDataRepresentation(for: .image) { [weak self] data, _ in
                let image = data.flatMap { UIImage(data: $0) }
                Task { @MainActor in self?.handle(image: image) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            _ = provider.loadFileRepresentation(for: .pdf) { [weak self] url, _, _ in
                let image = url.flatMap { Self.renderPDF(url: $0) }   // render before the file is removed
                Task { @MainActor in self?.handle(image: image) }
            }
        } else {
            model.phase = .failed("Share a photo, screenshot or PDF of a recipe")
        }
    }

    @MainActor
    private func handle(image: UIImage?) {
        guard let image else { model.phase = .failed("Couldn't open that file"); return }
        model.phase = .loading("Reading recipe…")
        Task.detached(priority: .userInitiated) {
            let lines = Self.recognizeText(in: image)
            await MainActor.run { [weak self] in self?.model.load(lines: lines, image: image) }
        }
    }

    nonisolated private static func recognizeText(in image: UIImage) -> [String] {
        guard let cg = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]
        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation))
        try? handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    nonisolated private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
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

    nonisolated private static func renderPDF(url: URL) -> UIImage? {
        guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1) else { return nil }
        let rect = page.getBoxRect(.mediaBox)
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: rect.size))
            ctx.cgContext.translateBy(x: 0, y: rect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            ctx.cgContext.drawPDFPage(page)
        }
    }

    private func save() {
        if saveToGroup(model.makeRecipe()) {
            model.phase = .saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.close() }
        } else {
            model.phase = .failed("Couldn't save. Check the App Group is enabled.")
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - SwiftUI views

private struct ShareRootView: View {
    @ObservedObject var model: ShareModel
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading(let msg): StatusView(emoji: "🍳", message: msg, showSpinner: true)
                case .saved:            StatusView(emoji: "✅", message: "Saved to Recipes", showSpinner: false)
                case .failed(let msg):  StatusView(emoji: "⚠️", message: msg, showSpinner: false)
                case .form:             ShareFormView(model: model)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                if model.phase == .form {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: onSave).fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle(model.phase == .form ? "Save Recipe" : "")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct StatusView: View {
    let emoji: String; let message: String; let showSpinner: Bool
    var body: some View {
        VStack(spacing: 16) {
            Text(emoji).font(.system(size: 56))
            if showSpinner { ProgressView() }
            Text(message).font(.headline).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShareFormView: View {
    @ObservedObject var model: ShareModel
    @State private var newTag = ""

    private var allTags: [String] { kPresetTags + model.tags.filter { !kPresetTags.contains($0) } }

    var body: some View {
        let counts = SRText.counts(model.keptLines)
        Form {
            if let img = model.image {
                Section {
                    HStack {
                        Spacer()
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("Recipe") {
                TextField("Title (e.g. Roti Canai)", text: $model.title)
                TextField("Note (optional)", text: $model.note, axis: .vertical).lineLimit(1...4)
            }

            Section("Tags") {
                SRFlowLayout(spacing: 8) {
                    ForEach(allTags, id: \.self) { tag in
                        let on = model.tags.contains(tag)
                        Button { model.toggleTag(tag) } label: {
                            Text(tag)
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(on ? Color.orange : Color(.tertiarySystemFill))
                                .foregroundStyle(on ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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
                NavigationLink {
                    SRLinePickerView(model: model)
                } label: {
                    HStack {
                        Label("Choose text to keep", systemImage: "text.badge.checkmark")
                        Spacer()
                        Text("\(model.lines.filter(\.kept).count)/\(model.lines.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Text")
            } footer: {
                Text("Found \(counts.ingredients) ingredients and \(counts.steps) steps. Untick lines you don't need, like the status bar or chatty intro.")
            }
        }
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if !model.tags.contains(t) { model.tags.append(t) }
        newTag = ""
    }
}

private struct SRLinePickerView: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        List {
            Section {
                ForEach($model.lines) { $line in
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
            } footer: {
                Text("Tap a line to keep or remove it. Press and hold a line to keep everything above or below it.")
            }
        }
        .navigationTitle("Choose Text")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Keep all") { setAll(true) }
                    Button("Remove all") { setAll(false) }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func setAll(_ kept: Bool) {
        for i in model.lines.indices { model.lines[i].kept = kept }
    }

    private func keep(from id: UUID, down: Bool) {
        guard let idx = model.lines.firstIndex(where: { $0.id == id }) else { return }
        for i in model.lines.indices { model.lines[i].kept = down ? i >= idx : i <= idx }
    }
}

private struct SRFlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}
