import UIKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Recipes — models + parser.
// (File keeps its old name "ReceiptParser.swift" so Xcode target membership
//  doesn't need to change. It must be in BOTH targets.)
// ─────────────────────────────────────────────────────────────────────────────

struct RecipeLine: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var kept: Bool = true
}

struct SavedRecipe: Codable, Identifiable {
    var id = UUID()
    var title: String = ""
    var rawText: String
    var lines: [RecipeLine] = []
    var tags: [String] = []
    var imageData: Data?
    var createdAt: Date = Date()
    var note: String = ""
    var isFavorite: Bool = false

    // MARK: Helpers
    var keptLines: [String] {
        lines.isEmpty
            ? rawText.components(separatedBy: "\n")
            : lines.filter(\.kept).map(\.text)
    }
    var keptText: String { keptLines.joined(separator: "\n") }
    var image: UIImage? { imageData.flatMap { UIImage(data: $0) } }
    var parsed: RecipeParser.Parsed { RecipeParser.parse(keptLines) }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let guess = RecipeParser.detectTitle(in: keptLines)
        return guess.isEmpty ? "Untitled recipe" : guess
    }
    var dateLabel: String {
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: createdAt)
    }

    init(id: UUID = UUID(), title: String = "", rawText: String, lines: [RecipeLine] = [],
         tags: [String] = [], imageData: Data? = nil, createdAt: Date = Date(),
         note: String = "", isFavorite: Bool = false) {
        self.id = id; self.title = title; self.rawText = rawText; self.lines = lines
        self.tags = tags; self.imageData = imageData; self.createdAt = createdAt
        self.note = note; self.isFavorite = isFavorite
    }

    enum CodingKeys: String, CodingKey {
        case id, title, rawText, lines, tags, imageData, createdAt, note, isFavorite
    }

    // Tolerant decoding — also reads items saved by the earlier "receipt" version.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title      = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        rawText    = try c.decodeIfPresent(String.self, forKey: .rawText) ?? ""
        tags       = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        imageData  = try c.decodeIfPresent(Data.self, forKey: .imageData)
        createdAt  = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        note       = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        if let l = try? c.decodeIfPresent([RecipeLine].self, forKey: .lines), !l.isEmpty {
            lines = l
        } else {
            lines = rawText.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { RecipeLine(text: $0) }
        }
    }
}

// Old names, so any existing references still compile.
typealias ScannedReceipt = SavedRecipe

// MARK: - Parser

struct RecipeParser {

    static let presetTags = [
        "Breakfast", "Lunch", "Dinner", "Dessert", "Snack", "Drink", "Baking",
        "Soup", "Noodles", "Rice", "Chinese", "Asian", "Western", "Healthy",
        "Quick", "Try later"
    ]

    struct Parsed {
        var ingredients: [String] = []
        var steps: [String] = []
        var isEmpty: Bool { ingredients.isEmpty && steps.isEmpty }
    }

    // "1. Mix", "2) Stir", "3、加水", "Step 4: Bake" — but not clock times like "10:28"
    private static let stepRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:step\s*)?(\d{1,2})\s*(?:[.)、]|[:：](?=\s))\s*(\D.*)$"#,
        options: .caseInsensitive)
    // "- 60g milk", "• 2 eggs"
    private static let bulletRegex = try! NSRegularExpression(
        pattern: #"^\s*[-•*·▪◦]\s*(.+)$"#)
    // "300mL water", "2 tbsp sugar", "3 克 盐"
    private static let quantityRegex = try! NSRegularExpression(
        pattern: #"^\s*(\d+(?:[./]\d+)?|½|¼|¾|⅓|一|两|半)\s*(g|kg|mg|ml|l|tbsp|tsp|cups?|oz|lbs?|pcs?|cloves?|克|毫升|勺|汤匙|茶匙|个|片|根|颗|瓣)(?![A-Za-z])"#,
        options: .caseInsensitive)
    // "Ingredients", "Method", "做法:" …
    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^(ingredients?|method|directions?|instructions?|steps?|材料|配料|食材|做法|步骤)\s*[:：]?$"#,
        options: .caseInsensitive)
    private static let timeRegex = try! NSRegularExpression(pattern: #"^\s*\d{1,2}:\d{2}"#)

    private static func match(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        (s as NSString).substring(with: m.range(at: i)).trimmingCharacters(in: .whitespaces)
    }

    static func isIngredient(_ line: String) -> Bool {
        match(bulletRegex, line) != nil || match(quantityRegex, line) != nil
    }

    /// Splits recipe text into ingredients and numbered steps.
    /// Lines that continue a step on the next line are joined back together.
    static func parse(_ rawLines: [String]) -> Parsed {
        enum Mode { case none, ingredient, step }
        var result = Parsed()
        var mode = Mode.none

        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let m = match(stepRegex, line) {
                result.steps.append(group(m, 2, in: line)); mode = .step; continue
            }
            if let m = match(bulletRegex, line) {
                result.ingredients.append(group(m, 1, in: line)); mode = .ingredient; continue
            }
            if match(quantityRegex, line) != nil {
                result.ingredients.append(line); mode = .ingredient; continue
            }
            if match(headerRegex, line) != nil { mode = .none; continue }

            if mode == .step, let last = result.steps.last {
                // A short line without ending punctuation after a finished step is a
                // section heading (e.g. "Cook Roti"), not a continuation.
                let ended = last.hasSuffix(".") || last.hasSuffix("!") || last.hasSuffix("?") || last.hasSuffix("。")
                let looksLikeHeading = line.split(separator: " ").count <= 4
                    && !(line.hasSuffix(".") || line.hasSuffix(",") || line.hasSuffix("。"))
                if !(ended && looksLikeHeading) {
                    result.steps[result.steps.count - 1] = last + " " + line
                    continue
                }
            }
            mode = .none
        }
        return result
    }

    /// Guesses the recipe name: the short line just above the first ingredient,
    /// otherwise the first sensible line.
    static func detectTitle(in rawLines: [String]) -> String {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func ok(_ s: String) -> Bool {
            let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            return letters >= 3 && s.count <= 60 && match(timeRegex, s) == nil
                && match(headerRegex, s) == nil && !isIngredient(s) && match(stepRegex, s) == nil
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
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
