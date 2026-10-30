import UIKit
import SwiftUI
import Combine
import Vision
import UniformTypeIdentifiers
import PDFKit

// ─────────────────────────────────────────────────────────────────────────────
// KellyLifeShare — save a recipe from Photos / Safari / Instagram screenshots.
// Bank statements (CSV, or a PDF that looks like a statement) are handed to the
// Finance tab instead: the file waits in the App Group and the import preview
// opens the next time Kelly Life is opened.
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
    var extraImages: [Data] = []
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

nonisolated private struct SRBox: Sendable { let text: String; let minX: Double; let maxX: Double; let midY: Double; let height: Double }

nonisolated private enum SRText {
    nonisolated(unsafe) static let stepRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:step\s*)?(\d{1,2})\s*(?:[.)、]|[:：](?=\s))\s*(\D.*)$"#, options: .caseInsensitive)
    nonisolated(unsafe) static let bulletRegex = try! NSRegularExpression(pattern: #"^\s*[-•*·▪◦]\s*(.+)$"#)
    nonisolated(unsafe) static let quantityRegex = try! NSRegularExpression(
        pattern: #"^\s*(\d+(?:[./]\d+)?|½|¼|¾|⅓|一|两|半)\s*(g|kg|mg|ml|l|tbsp|tsp|cups?|oz|lbs?|pcs?|cloves?|克|毫升|勺|汤匙|茶匙|个|片|根|颗|瓣)(?![A-Za-z])"#,
        options: .caseInsensitive)
    nonisolated(unsafe) static let headerRegex = try! NSRegularExpression(
        pattern: #"^(ingredients?|method|directions?|instructions?|steps?|材料|配料|食材|做法|步骤)\s*[:：]?$"#,
        options: .caseInsensitive)
    nonisolated(unsafe) static let timeRegex = try! NSRegularExpression(pattern: #"^\s*\d{1,2}:\d{2}"#)

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
        let lines = lines.filter { !isJunk($0) }
        let firstContent = lines.firstIndex { isIngredient($0) || has(stepRegex, $0) || $0.hasPrefix("【") || $0.hasPrefix("[") }
            ?? min(lines.count, 10)
        let before = Array(lines[..<firstContent]).filter { ok($0) && !$0.hasPrefix("#") }
        if let near = before.suffix(2).last { return near }
        // Otherwise the hashtag that best matches the recipe text (e.g. "#椰蓉奶酥包")
        let tags = lines.filter { $0.hasPrefix("#") }
            .flatMap { $0.split(separator: "#") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 2 }
        let body = lines.filter { !$0.hasPrefix("#") }.joined()
        func pairs(_ s: String) -> [String] {
            let c = Array(s); return c.count < 2 ? [] : (0..<(c.count - 1)).map { String(c[$0...$0 + 1]) }
        }
        let best = tags.map { ($0, pairs($0).filter { body.contains($0) }.count) }.max { $0.1 < $1.1 }
        return (best?.1 ?? 0) >= 2 ? best!.0 : ""
    }

    // MARK: Screen clean-up (matches RecipeParser in the main app)

    static let junkWords: Set<String> = [
        "follow", "following", "关注", "已关注", "+关注", "say something", "说点什么", "translate", "翻译",
        "dislike", "不喜欢", "share", "分享", "like", "赞", "collect", "收藏", "comment", "评论", "reply", "回复",
        "more", "更多", "展开", "收起", "save", "saved", "保存",
    ]
    nonisolated(unsafe) static let countRegex = try! NSRegularExpression(pattern: #"^[\d,.\s]+[kKwW万千]?\+?$"#)
    nonisolated(unsafe) static let dateRegex = try! NSRegularExpression(pattern: #"^\s*\d{1,4}[/\-.年]\d{1,2}[/\-.月]\d{0,4}"#)

    static func isJunk(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.unicodeScalars.filter({ CharacterSet.alphanumerics.contains($0) }).isEmpty { return true }
        if junkWords.contains(t.lowercased()) { return true }
        if has(timeRegex, t) && t.count <= 8 { return true }
        if has(countRegex, t) { return true }
        if has(dateRegex, t) && t.count <= 40 { return true }
        let lower = t.lowercased()
        return ["originality declared", "编辑于", "发布于", "原创声明"].contains { lower.contains($0) }
    }

    static func normalize(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: "\u{FE0F}", with: "")
            .replacingOccurrences(of: "\u{20E3}", with: ". ")
            .trimmingCharacters(in: .whitespaces)
        let circled = Array("①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳")
        if let f = t.first, let i = circled.firstIndex(of: f) {
            t = "\(i + 1). " + t.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    static func join(_ a: String, _ b: String) -> String {
        func cjk(_ c: Character?) -> Bool {
            guard let u = c?.unicodeScalars.first else { return false }
            return (0x3000...0x9FFF).contains(u.value) || (0xFF00...0xFFEF).contains(u.value)
        }
        return cjk(a.last) || cjk(b.first) ? a + b : a + " " + b
    }

    /// Same-row pieces joined left-to-right, screenshot header/bottom bar skipped, wrapped lines rejoined.
    static func assemble(_ boxes: [SRBox], isScreenshot: Bool) -> [String] {
        var items = boxes
        if isScreenshot { items = items.filter { $0.midY > 0.12 && $0.midY < 0.9 } }
        items.sort { $0.midY < $1.midY }
        var rows: [[SRBox]] = []
        for b in items {
            if let first = rows.last?.first, abs(b.midY - first.midY) < max(b.height, first.height) * 0.5 {
                rows[rows.count - 1].append(b)
            } else { rows.append([b]) }
        }
        let built = rows.map { row -> (String, Double) in
            let sorted = row.sorted { $0.minX < $1.minX }
            return (normalize(sorted.map(\.text).joined(separator: " ")), sorted.map(\.maxX).max() ?? 0)
        }
        let edge = built.map(\.1).max() ?? 1
        var out: [(String, Double)] = []
        for (text, maxX) in built where !isJunk(text) {
            let startsNew = text.first.map { "#【[-•*·0123456789".contains($0) } ?? true
            if let prev = out.last, prev.1 >= max(edge - 0.06, 0.75), prev.0.count >= 8, !startsNew {
                out[out.count - 1] = (join(prev.0, text), maxX)
            } else { out.append((text, maxX)) }
        }
        return out.map(\.0)
    }

    /// Joins several screenshots' text in order, skipping lines that overlap with the previous
    /// screenshot. A cut-off last line is replaced by the full copy on the next screenshot.
    static func mergePages(_ pages: [[String]]) -> [String] {
        func key(_ s: String) -> String {
            s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
        var merged: [String] = []
        for (index, raw) in pages.enumerated() {
            let page = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !isJunk($0) }
            _ = index
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
    enum Phase: Equatable { case loading(String), form, saved, failed(String), statement(String), statementSaved }

    @Published var phase: Phase = .loading("Opening image…")
    @Published var title = ""
    @Published var note = ""
    @Published var tags: [String] = []
    @Published var lines: [SRLine] = []
    var images: [UIImage] = []
    var image: UIImage? { images.first }
    /// A bank statement waiting for the main app, and its first page as a picture (for "save as recipe instead").
    var statementURL: URL?
    var statementImage: UIImage?
    var statementConfirmed = false
    var statementName = ""

    var keptLines: [String] { lines.filter(\.kept).map(\.text) }

    /// One page of text per screenshot, joined in order.
    func load(pages: [[String]], images: [UIImage]) {
        let merged = SRText.mergePages(pages)
        self.images = images
        self.lines = merged.map { SRLine(text: $0) }
        self.title = SRText.title(in: merged)
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
            extraImages: images.dropFirst().compactMap { SRText.downscaled($0, maxSide: 1200).jpegData(compressionQuality: 0.5) },
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
            onSave:   { [weak self] in self?.save() },
            onImportStatement: { [weak self] in self?.confirmStatement() },
            onStatementAsRecipe: { [weak self] in self?.useStatementAsRecipe() },
            onFormToFinance: { [weak self] in self?.sendToFinanceFromForm() }
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

    /// Reads every shared screenshot (up to 10), in the order they were selected.
    private func loadSharedItem() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else { model.phase = .failed("Nothing to save"); return }
        let total = min(providers.count, 10)

        Task { @MainActor in
            // Bank statement? Send it to Finance instead of Recipes.
            // Apps like Amex share several items (a link or text plus the PDF), so check them all.
            for provider in providers {
                guard let shared = await Self.loadStatementCandidate(provider) else { continue }
                model.statementURL = shared.url          // kept so the recipe form can still send it to Finance
                model.statementImage = shared.image
                model.statementName = shared.displayName
                if shared.isStatement {
                    model.phase = .statement(shared.displayName)
                    return
                }
                break
            }
            var images: [UIImage] = []
            for (i, provider) in providers.prefix(10).enumerated() {
                model.phase = .loading(total > 1 ? "Opening \(i + 1) of \(total)…" : "Opening image…")
                if let img = await Self.loadImage(from: provider) { images.append(img) }
            }
            guard !images.isEmpty else {
                model.phase = .failed("Share a photo, screenshot or PDF of a recipe"); return
            }
            var pages: [[String]] = []
            for (i, img) in images.enumerated() {
                model.phase = .loading(images.count > 1 ? "Reading screenshot \(i + 1) of \(images.count)…" : "Reading recipe…")
                let lines = await Task.detached(priority: .userInitiated) { Self.recognizeText(in: img) }.value
                pages.append(lines)
            }
            model.load(pages: pages, images: images)
        }
    }

    // MARK: Bank statements

    struct StatementCandidate { let url: URL; let displayName: String; let isStatement: Bool; let image: UIImage? }

    nonisolated private static func pendingFolder() -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: kGroupID) else { return nil }
        let dir = base.appendingPathComponent("PendingStatements", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies a shared file into the App Group, where the main app can pick it up.
    nonisolated private static func copyToPending(_ url: URL) -> URL? {
        guard let dir = pendingFolder() else { return nil }
        let dest = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: url, to: dest); return dest } catch { return nil }
    }

    /// CSV files are always statements; PDFs are checked for statement words and transaction lines.
    nonisolated private static func loadStatementCandidate(_ provider: NSItemProvider) async -> StatementCandidate? {
        let csvTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText]
        for type in csvTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            return await withCheckedContinuation { cont in
                _ = provider.loadFileRepresentation(for: type) { url, _, _ in
                    guard let url, let copy = copyToPending(url) else { cont.resume(returning: nil); return }
                    cont.resume(returning: StatementCandidate(url: copy, displayName: url.lastPathComponent, isStatement: true, image: nil))
                }
            }
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) else { return nil }
        let name = (provider.suggestedName ?? "Statement") + ".pdf"
        // Some apps hand over a file, others only the bytes
        let copied: URL? = await withCheckedContinuation { cont in
            _ = provider.loadFileRepresentation(for: .pdf) { url, _, _ in
                cont.resume(returning: url.flatMap { copyToPending($0) })
            }
        }
        var file = copied
        if file == nil {
            file = await withCheckedContinuation { cont in
                _ = provider.loadDataRepresentation(for: .pdf) { data, _ in
                    guard let data, let dir = pendingFolder() else { cont.resume(returning: nil); return }
                    let dest = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(name)")
                    cont.resume(returning: (try? data.write(to: dest)) != nil ? dest : nil)
                }
            }
        }
        guard let file else { return nil }
        let display = file.lastPathComponent.split(separator: "-", maxSplits: 1).last.map(String.init) ?? name
        return StatementCandidate(url: file, displayName: display, isStatement: looksLikeStatement(file), image: renderPDF(url: file))
    }

    nonisolated private static func looksLikeStatement(_ url: URL) -> Bool {
        guard let doc = PDFDocument(url: url) else { return false }
        var text = ""
        for i in 0..<min(doc.pageCount, 3) { text += (doc.page(at: i)?.string ?? "") + "\n" }
        let lower = text.lowercased()
        let words = ["statement", "account number", "account ending", "previous balance", "new balance", "payment due",
                     "minimum payment", "credit limit", "closing date", "opening balance", "closing balance", "transactions",
                     "payments/credits", "new charges", "interest charged", "账单", "对账单", "余额"]
        let wordHits = words.filter { lower.contains($0) }.count
        let lineRegex = try! NSRegularExpression(
            pattern: #"^\s*(?:\d{1,2}/\d{1,2}|[A-Za-z]{3}\.?\s?\d{1,2}|\d{1,2}\s?[A-Za-z]{3}|\d{4}-\d{2}-\d{2})\b.*\d+\.\d{2}\s*(?:CR)?\s*$"#,
            options: [.anchorsMatchLines, .caseInsensitive])
        let lineHits = lineRegex.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        return wordHits >= 2 || lineHits >= 4
            || url.lastPathComponent.lowercased().contains("statement")
    }

    /// The user chose "Save as recipe instead" for a PDF.
    private func useStatementAsRecipe() {
        if let url = model.statementURL { try? FileManager.default.removeItem(at: url) }
        model.statementURL = nil
        guard let img = model.statementImage else { model.phase = .failed("Couldn't read that PDF as a recipe"); return }
        model.phase = .loading("Reading recipe…")
        Task { @MainActor in
            let lines = await Task.detached(priority: .userInitiated) { Self.recognizeText(in: img) }.value
            model.load(pages: [lines], images: [img])
        }
    }

    private func confirmStatement() {
        model.statementConfirmed = true
        model.phase = .statementSaved
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.close() }
    }

    nonisolated private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await withCheckedContinuation { cont in
                _ = provider.loadDataRepresentation(for: .image) { data, _ in
                    cont.resume(returning: data.flatMap { UIImage(data: $0) })
                }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return await withCheckedContinuation { cont in
                _ = provider.loadFileRepresentation(for: .pdf) { url, _, _ in
                    cont.resume(returning: url.flatMap { renderPDF(url: $0) })   // render before the file is removed
                }
            }
        }
        return nil
    }

    nonisolated private static func recognizeText(in image: UIImage) -> [String] {
        guard let cg = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]   // Chinese must come first, or Chinese text turns into symbols
        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgOrientation(image.imageOrientation))
        try? handler.perform([request])
        let boxes: [SRBox] = (request.results ?? []).compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let r = obs.boundingBox
            return SRBox(text: text, minX: r.minX, maxX: r.maxX, midY: 1 - r.midY, height: r.height)
        }
        let isScreenshot = image.size.height / max(image.size.width, 1) >= 1.9
        return SRText.assemble(boxes, isScreenshot: isScreenshot)
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

    /// "This is a bank statement" button on the recipe form.
    func sendToFinanceFromForm() {
        guard model.statementURL != nil else { return }
        confirmStatement()
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
        // Cancelled a statement: don't leave the file waiting
        if let url = model.statementURL, !model.statementConfirmed { try? FileManager.default.removeItem(at: url) }
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - SwiftUI views

private struct ShareRootView: View {
    @ObservedObject var model: ShareModel
    let onCancel: () -> Void
    let onSave: () -> Void
    let onImportStatement: () -> Void
    let onStatementAsRecipe: () -> Void
    let onFormToFinance: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading(let msg): StatusView(emoji: "🍳", message: msg, showSpinner: true)
                case .saved:            StatusView(emoji: "✅", message: "Saved to Recipes", showSpinner: false)
                case .failed(let msg):  StatusView(emoji: "⚠️", message: msg, showSpinner: false)
                case .form:             ShareFormView(model: model, onToFinance: onFormToFinance)
                case .statement(let name):
                    StatementChoiceView(name: name, canBeRecipe: model.statementImage != nil,
                                        onImport: onImportStatement, onRecipe: onStatementAsRecipe)
                case .statementSaved:
                    StatusView(emoji: "💳", message: "Ready to import.\nOpen Kelly Life to check the transactions and add them to Finance.", showSpinner: false)
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
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension ShareRootView {
    var navTitle: String {
        switch model.phase {
        case .form: return "Save Recipe"
        case .statement: return "Bank Statement"
        default: return ""
        }
    }
}

private struct StatementChoiceView: View {
    let name: String
    let canBeRecipe: Bool
    let onImport: () -> Void
    let onRecipe: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("💳").font(.system(size: 56))
            Text("This looks like a bank statement").font(.title3).fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text(name).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            Text("Import its transactions into Finance? You'll see a preview to check before anything is added.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button(action: onImport) {
                Label("Import to Finance", systemImage: "tray.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if canBeRecipe {
                Button("Save as a recipe instead", action: onRecipe)
                    .font(.subheadline)
            }
        }
        .padding(24)
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
    var onToFinance: () -> Void = {}
    @State private var newTag = ""

    private var allTags: [String] { kPresetTags + model.tags.filter { !kPresetTags.contains($0) } }

    var body: some View {
        let counts = SRText.counts(model.keptLines)
        Form {
            if !model.images.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(model.images.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img)
                                    .resizable().scaledToFit()
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } footer: {
                    if model.images.count > 1 {
                        Text("\(model.images.count) screenshots joined into one recipe. Overlapping lines were removed.")
                    }
                }
                .listRowBackground(Color.clear)
            }

            if model.statementURL != nil {
                Section {
                    Button(action: onToFinance) {
                        Label("This is a bank statement: import to Finance", systemImage: "creditcard")
                    }
                }
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
