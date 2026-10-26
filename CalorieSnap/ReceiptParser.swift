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
    var extraImages: [Data] = []      // more screenshots/photos of the same recipe
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
    /// Every photo of this recipe, first one first.
    var images: [UIImage] { ([imageData].compactMap { $0 } + extraImages).compactMap { UIImage(data: $0) } }
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
         tags: [String] = [], imageData: Data? = nil, extraImages: [Data] = [], createdAt: Date = Date(),
         note: String = "", isFavorite: Bool = false) {
        self.id = id; self.title = title; self.rawText = rawText; self.lines = lines
        self.tags = tags; self.imageData = imageData; self.extraImages = extraImages; self.createdAt = createdAt
        self.note = note; self.isFavorite = isFavorite
    }

    enum CodingKeys: String, CodingKey {
        case id, title, rawText, lines, tags, imageData, extraImages, createdAt, note, isFavorite
    }

    // Tolerant decoding — also reads items saved by the earlier "receipt" version.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title      = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        rawText    = try c.decodeIfPresent(String.self, forKey: .rawText) ?? ""
        tags       = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        imageData  = try c.decodeIfPresent(Data.self, forKey: .imageData)
        extraImages = (try? c.decodeIfPresent([Data].self, forKey: .extraImages)) ?? []
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
        var tips: [String] = []
        var isEmpty: Bool { ingredients.isEmpty && steps.isEmpty }
    }

    // MARK: Patterns

    // "1. Mix", "2) Stir", "3、加水", "Step 4: Bake" — but not clock times like "10:28"
    private static let stepRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:step\s*)?(\d{1,2})\s*(?:[.)、]|[:：](?=\s))\s*(\D.*)$"#,
        options: .caseInsensitive)
    // "(1) Mix", "[2] 加水", "【3】…"
    private static let bracketStepRegex = try! NSRegularExpression(
        pattern: #"^\s*[\[(（【]\s*(\d{1,2})\s*[\])）】]\s*(.+)$"#)
    // "第1步：…", "第三步 …"
    private static let chineseStepRegex = try! NSRegularExpression(
        pattern: #"^\s*第\s*(\d{1,2}|[一二三四五六七八九十]+)\s*步\s*[:：、.]?\s*(.+)$"#)
    // "1 后油后盐…" / "5二发…" — a number with no punctuation (how emoji numbers like 1️⃣ get read)
    private static let looseStepRegex = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,2})\s*[|｜]?\s*(?![\d.,/:：\-–~～%])(\D.*)$"#)
    // "- 60g milk", "• 2 eggs"
    private static let bulletRegex = try! NSRegularExpression(
        pattern: #"^\s*[-•*·▪◦]\s*(.+)$"#)
    private static let units = #"g|kg|mg|ml|mL|l|L|tbsp|tsp|cups?|oz|lbs?|pcs?|cloves?|slices?|克|千克|公斤|毫升|升|勺|小勺|大勺|汤匙|茶匙|杯|碗|个|只|枚|片|根|颗|瓣|块|条|把|包|袋|盒|罐"#
    // "300mL water", "2 tbsp sugar", "3 克 盐"
    private static let quantityRegex = try! NSRegularExpression(
        pattern: #"^\s*(\d+(?:[./]\d+)?|½|¼|¾|⅓|一|两|半)\s*("# + units + #")(?![A-Za-z])"#,
        options: .caseInsensitive)
    // "高筋粉 430g", "高筋面粉 500", "鸡蛋1个（约50g）", "牛奶 200g (预留20g)", "Flour 200 g", "盐 适量", "salt to taste"
    private static let trailingQuantityRegex = try! NSRegularExpression(
        pattern: #"^\s*[^\d\s][^\d]{0,20}?\s*(?:(?:\d+(?:[./]\d+)?|½|¼|¾|⅓|一|两|半)\s*(?:"# + units + #")?|适量|少许|若干|少量|to taste|a pinch|pinch)\s*(?:[（(][^)）]*[)）]?)?\s*[,，;；。]?\s*$"#,
        options: .caseInsensitive)
    // "Ingredients", "Method", "做法:" …
    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^(ingredients?|method|directions?|instructions?|steps?|材料|配料|食材|用料|做法|步骤)\s*[:：]?$"#,
        options: .caseInsensitive)
    // "【面团】:", "[Sauce]"
    private static let bracketHeadingRegex = try! NSRegularExpression(
        pattern: #"^\s*[【\[]\s*([^】\]]{1,20})\s*[】\]]\s*[:：]?\s*$"#)
    private static let timeRegex = try! NSRegularExpression(pattern: #"^\s*\d{1,2}:\d{2}"#)
    private static let countRegex = try! NSRegularExpression(pattern: #"^[\d,.\s]+[kKwW万千]?\+?$"#)
    private static let dateRegex = try! NSRegularExpression(pattern: #"^\s*\d{1,4}[/\-.年]\d{1,2}[/\-.月]\d{0,4}"#)

    private static let stepWords = ["method", "directions", "direction", "instructions", "instruction", "steps", "step",
                                    "preparation", "how to make", "做法", "步骤", "制作过程", "制作方法", "制作步骤",
                                    "过程", "操作步骤", "操作", "烘焙过程", "教程"]
    private static let ingredientWords = ["ingredients", "ingredient", "材料", "配料", "食材", "用料", "原料", "准备材料"]

    /// App buttons and labels that show up in screenshots of Xiaohongshu, Instagram, TikTok etc.
    private static let junkWords: Set<String> = [
        "follow", "following", "followed", "关注", "已关注", "+关注", "say something", "说点什么", "说点什么...",
        "translate", "翻译", "see translation", "dislike", "不喜欢", "share", "分享", "like", "赞", "collect",
        "收藏", "comment", "comments", "评论", "reply", "回复", "more", "更多", "展开", "收起", "edited", "已编辑",
        "save", "saved", "保存", "send", "发送", "author", "作者", "置顶", "pinned",
    ]

    private static func match(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        (s as NSString).substring(with: m.range(at: i)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Clean-up

    /// Turns emoji and circled numbers (1️⃣, ①) into "1. " and trims the line.
    static func normalize(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: "\u{FE0F}", with: "")
            .replacingOccurrences(of: "\u{20E3}", with: ". ")
            .replacingOccurrences(of: "🔟", with: "10. ")
            .trimmingCharacters(in: .whitespaces)
        let circled = Array("①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳")
        if let f = t.first, let i = circled.firstIndex(of: f) {
            t = "\(i + 1). " + t.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    /// Screen clutter: status bar time, app buttons, like counts, dates, lone dots.
    static func isJunk(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        let meaningful = t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        if meaningful == 0 { return true }
        if junkWords.contains(t.lowercased()) { return true }
        if match(timeRegex, t) != nil && t.count <= 8 { return true }
        if match(countRegex, t) != nil { return true }
        if match(dateRegex, t) != nil && t.count <= 40 { return true }
        let lower = t.lowercased()
        return ["originality declared", "编辑于", "发布于", "原创声明", "已声明原创"].contains { lower.contains($0) }
    }

    static func isHashtagLine(_ line: String) -> Bool {
        let parts = line.split(separator: " ")
        return !parts.isEmpty && line.hasPrefix("#") && parts.filter { $0.hasPrefix("#") }.count * 2 >= parts.count
    }

    // MARK: Line kinds

    enum Heading: Equatable { case ingredients, steps, tips, group(String) }

    private static let tipWords = ["tips", "tip", "notes", "note", "小贴士", "贴士", "小提示", "提示", "注意", "注意事项", "备注", "心得", "tips & tricks"]

    static func heading(_ line: String) -> Heading? {
        var t = line.trimmingCharacters(in: .whitespaces)
        var marked = false
        if let m = match(bracketHeadingRegex, t) {
            t = group(m, 1, in: t); marked = true
        } else if t.hasSuffix(":") || t.hasSuffix("：") {
            t = String(t.dropLast()).trimmingCharacters(in: .whitespaces); marked = true
        }
        let lower = t.lowercased()
        if stepWords.contains(lower) || (marked && stepWords.contains { lower.contains($0) }) { return .steps }
        if ingredientWords.contains(lower) || (marked && ingredientWords.contains { lower.contains($0) }) { return .ingredients }
        if tipWords.contains(lower) || (marked && tipWords.contains { lower.contains($0) }) { return .tips }
        if marked, !t.isEmpty, t.count <= 14, t.rangeOfCharacter(from: .decimalDigits) == nil { return .group(t) }
        return nil
    }

    static func isIngredient(_ line: String) -> Bool {
        match(bulletRegex, line) != nil || match(quantityRegex, line) != nil
            || match(trailingQuantityRegex, line) != nil
    }

    /// The text of a numbered step, or nil. `loose` also accepts a bare number with no punctuation.
    static func stepText(_ line: String, loose: Bool) -> String? {
        for re in [stepRegex, bracketStepRegex, chineseStepRegex] {
            if let m = match(re, line) { return group(m, 2, in: line) }
        }
        if let m = match(looseStepRegex, line) {
            let rest = group(m, 2, in: line)
            let hasChinese = rest.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            if loose || (hasChinese && rest.count >= 6) { return rest }
        }
        return nil
    }

    private static func stripBulletText(_ line: String) -> String {
        if let m = match(bulletRegex, line) { return group(m, 1, in: line) }
        return line
    }

    // MARK: Parse

    /// Splits recipe text into ingredients and steps. Understands section headings like
    /// "Ingredients" / "【面团】" / "【制作过程】", emoji step numbers, and amounts written
    /// before or after the ingredient name. Wrapped step lines are joined back together.
    static func parse(_ rawLines: [String]) -> Parsed {
        enum Section { case unknown, ingredients, steps, tips }
        var result = Parsed()
        var section = Section.unknown
        var lastWasStep = false
        var sawNumbered = false

        func appendToLastStep(_ line: String) {
            guard let last = result.steps.last else { return }
            result.steps[result.steps.count - 1] = joinText(last, line)
        }

        for raw in rawLines {
            let line = normalize(raw)
            guard !line.isEmpty, !isJunk(line) else { continue }
            if isHashtagLine(line) { lastWasStep = false; continue }

            if let h = heading(line), !(section == .steps && h != .steps && line.count > 14) {
                switch h {
                case .steps: section = .steps
                case .ingredients: section = .ingredients
                case .tips: section = .tips
                case .group(let name):
                    if section == .steps && lastWasStep { break }
                    section = .ingredients
                    result.ingredients.append("【\(name)】")
                }
                lastWasStep = false
                continue
            }

            if section == .tips {
                result.tips.append(line); continue
            }

            if section == .steps {
                if let step = stepText(line, loose: true) {
                    result.steps.append(step); sawNumbered = true; lastWasStep = true
                } else if sawNumbered && lastWasStep {
                    appendToLastStep(line)
                } else {
                    result.steps.append(line); lastWasStep = true
                }
                continue
            }

            if isIngredient(line) {
                result.ingredients.append(stripBulletText(line)); lastWasStep = false; continue
            }
            if let step = stepText(line, loose: false) {
                result.steps.append(step); sawNumbered = true; lastWasStep = true; continue
            }
            if section == .ingredients && line.count <= 30 {
                result.ingredients.append(line); continue
            }
            if lastWasStep, let last = result.steps.last {
                // A short line without ending punctuation after a finished step is a
                // section heading (e.g. "Cook Roti"), not a continuation.
                let ended = last.hasSuffix(".") || last.hasSuffix("!") || last.hasSuffix("?") || last.hasSuffix("。")
                let looksLikeHeading = line.split(separator: " ").count <= 4
                    && !(line.hasSuffix(".") || line.hasSuffix(",") || line.hasSuffix("。"))
                if !(ended && looksLikeHeading) { appendToLastStep(line); continue }
            }
            lastWasStep = false
        }
        // Drop group labels that ended up with nothing under them
        result.ingredients = result.ingredients.enumerated().filter { i, item in
            !(item.hasPrefix("【") && (i == result.ingredients.count - 1 || result.ingredients[i + 1].hasPrefix("【")))
        }.map(\.element)
        return result
    }

    /// Joins two pieces of a wrapped line; Chinese text joins without a space.
    static func joinText(_ a: String, _ b: String) -> String {
        func isCJK(_ c: Character?) -> Bool {
            guard let u = c?.unicodeScalars.first else { return false }
            return (0x3000...0x9FFF).contains(u.value) || (0xFF00...0xFFEF).contains(u.value)
        }
        return isCJK(a.last) || isCJK(b.first) ? a + b : a + " " + b
    }

    // MARK: Title

    /// Guesses the recipe name: a short line above the ingredients; otherwise the hashtag
    /// that best matches the recipe (e.g. "#椰蓉奶酥包"); otherwise nothing.
    static func detectTitle(in rawLines: [String]) -> String {
        let lines = rawLines.map(normalize).filter { !$0.isEmpty && !isJunk($0) }
        func ok(_ s: String) -> Bool {
            let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            return letters >= 2 && s.count <= 60 && match(timeRegex, s) == nil && heading(s) == nil
                && match(headerRegex, s) == nil && !isIngredient(s) && stepText(s, loose: false) == nil
                && !isHashtagLine(s)
        }
        let firstContent = lines.firstIndex { isIngredient($0) || heading($0) != nil || stepText($0, loose: false) != nil }
            ?? min(lines.count, 10)
        let before = Array(lines[..<firstContent])
        if let near = before.suffix(2).last(where: ok) { return near }
        if let any = before.first(where: ok) { return any }
        return hashtagTitle(lines) ?? ""
    }

    private static func hashtagTitle(_ lines: [String]) -> String? {
        let tags = lines.filter(isHashtagLine)
            .flatMap { $0.split(separator: " ") }
            .flatMap { $0.split(separator: "#") }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 }
        let body = lines.filter { !isHashtagLine($0) }.joined()
        func pairs(_ s: String) -> [String] {
            let c = Array(s); return c.count < 2 ? [] : (0..<(c.count - 1)).map { String(c[$0...$0 + 1]) }
        }
        let scored = tags.map { tag in (tag, pairs(tag).filter { body.contains($0) }.count) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 2 else { return nil }
        return best.0
    }

    // MARK: Screenshots

    /// One piece of text Vision found, with its position (0–1, measured from the top-left).
    nonisolated struct TextBox: Sendable { let text: String; let minX: Double; let maxX: Double; let midY: Double; let height: Double }

    /// Builds clean lines from Vision's text boxes:
    /// - pieces on the same row are joined left-to-right (e.g. "1️⃣" + "后油后盐…")
    /// - on phone screenshots, the app header and bottom bar are ignored
    /// - lines that wrap to the next row are joined back together
    static func assembleLines(_ boxes: [TextBox], isScreenshot: Bool, joinWrapped: Bool = true) -> [String] {
        var items = boxes.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        if isScreenshot { items = items.filter { $0.midY > 0.12 && $0.midY < 0.9 } }
        items.sort { $0.midY < $1.midY }

        struct Row { var boxes: [TextBox]; var midY: Double; var height: Double }
        var rows: [Row] = []
        for b in items {
            if var last = rows.last, abs(b.midY - last.midY) < max(b.height, last.height) * 0.5 {
                last.boxes.append(b); rows[rows.count - 1] = last
            } else {
                rows.append(Row(boxes: [b], midY: b.midY, height: b.height))
            }
        }
        let built: [(text: String, maxX: Double)] = rows.map { row in
            let sorted = row.boxes.sorted { $0.minX < $1.minX }
            return (sorted.map(\.text).joined(separator: " "), sorted.map(\.maxX).max() ?? 0)
        }
        let rightEdge = built.map(\.maxX).max() ?? 1

        var out: [(text: String, maxX: Double)] = []
        for row in built {
            // Recipes: tidy up and drop screen clutter. Statements (joinWrapped == false): keep every row as read.
            let text = joinWrapped ? normalize(row.text) : row.text
            if joinWrapped && isJunk(text) { continue }
            if joinWrapped, let prev = out.last, prev.maxX >= max(rightEdge - 0.06, 0.75), prev.text.count >= 8,
               !startsNewItem(text), !isJunk(prev.text) {
                out[out.count - 1] = (joinText(prev.text, text), row.maxX)
            } else {
                out.append((text, row.maxX))
            }
        }
        return out.map(\.text)
    }

    private static func startsNewItem(_ line: String) -> Bool {
        line.hasPrefix("#") || line.hasPrefix("【") || line.hasPrefix("[") || heading(line) != nil
            || match(bulletRegex, line) != nil || stepText(line, loose: true) != nil
            || match(quantityRegex, line) != nil
    }

    /// Joins the text of several screenshots into one list, in order.
    /// Screenshots usually overlap, so lines already seen at the end of the previous page are skipped.
    /// The last line of a page is often cut off, so a longer copy on the next page replaces it.
    static func mergePages(_ pages: [[String]]) -> [String] {
        func key(_ s: String) -> String {
            s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
        var merged: [String] = []
        for raw in pages {
            let page = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !isJunk($0) }
            let tail = Array(merged.suffix(40)).map(key)
            let head = page.map(key)
            var overlap = 0
            var replaceLast = false
            if !tail.isEmpty && !head.isEmpty {
                for k in stride(from: min(tail.count, head.count), through: 1, by: -1) {
                    let t = Array(tail.suffix(k)), h = Array(head.prefix(k))
                    if t == h { overlap = k; break }
                    if Array(t.dropLast()) == Array(h.dropLast()), let lt = t.last, let lh = h.last,
                       min(lt.count, lh.count) >= 6, lh.hasPrefix(lt) || lt.hasPrefix(lh) {
                        overlap = k; replaceLast = lh.count > lt.count; break
                    }
                }
            }
            if replaceLast { merged[merged.count - 1] = page[overlap - 1] }
            merged += page.dropFirst(overlap)
        }
        return merged
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
