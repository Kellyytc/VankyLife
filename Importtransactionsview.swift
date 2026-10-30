import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// ─────────────────────────────────────────────────────────────────────────────
// Import past purchases from a bank or credit-card CSV file.
//
// Works with the CSV downloads from most banks and cards (Chase, Amex, Capital One,
// Citi, Bank of America, Wells Fargo, Discover, Apple Card, RBC, TD, Scotiabank,
// BMO, CIBC and others): it finds the date, description and amount columns by
// itself, shows a preview, skips card payments and anything already in the app,
// and guesses each category from the shop name.
// Main app target only. Opened from Finance → + → Import from Bank CSV.
// ─────────────────────────────────────────────────────────────────────────────

struct ImportRow: Identifiable {
    let id = UUID()
    let date: Date
    let title: String
    let amount: Double            // always positive
    let signed: Double            // as written in the file (single-amount files)
    let fromSplitColumns: Bool    // file had separate debit / credit columns
    let splitIsExpense: Bool
    let typeHint: Bool?           // from a "Type" column (Sale / Payment…), if any
    var isExpense: Bool
    var category: TransactionCategory
    var include: Bool
    var isDuplicate: Bool
    var isCardPayment: Bool
}

// MARK: - Reading the file

enum BankCSV {
    struct Result {
        var rows: [ImportRow]
        var usedSignGuess: Bool     // single amount column without a Type column
    }

    static func read(_ data: Data) -> String? {
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
        if text?.hasPrefix("\u{FEFF}") == true { text?.removeFirst() }
        return text
    }

    /// Splits CSV text into rows of fields (handles quotes, commas inside quotes, ; and tab files).
    static func table(_ text: String) -> [[String]] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let sample = lines.split(separator: "\n").prefix(10).joined(separator: "\n")
        var delimiter: Character = ","
        var bestCount = -1
        for candidate in [Character(","), Character(";"), Character("\t")] {
            let n = sample.filter { $0 == candidate }.count
            if n > bestCount { bestCount = n; delimiter = candidate }
        }
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(lines)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
            } else if c == "\n" {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        return rows
    }

    // MARK: Values

    static func money(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let wrapped = t.hasPrefix("(") && t.hasSuffix(")")
        let minus = t.hasPrefix("-") || t.hasPrefix("−") || t.hasSuffix("-")
        var negative = wrapped || minus
        if t.uppercased().hasSuffix("CR") { negative = true; t = String(t.dropLast(2)) }
        if t.uppercased().hasSuffix("DR") { t = String(t.dropLast(2)) }
        let digits = t.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard digits.contains(where: { $0.isNumber }) else { return nil }
        // Letters other than currency codes mean it's not an amount
        let letters = t.filter { $0.isLetter }.uppercased()
        if !letters.isEmpty && !["USD", "CAD", "CA", "US", "C", "EUR", "GBP"].contains(letters) { return nil }
        guard let v = PurchaseLogger.parseAmount(digits) else { return nil }
        return negative ? -v : v
    }

    private static let formats = ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy", "yyyy/MM/dd",
                                  "dd MMM yyyy", "d MMM yyyy", "MMM d, yyyy", "MMM dd, yyyy", "dd-MMM-yyyy",
                                  "yyyyMMdd", "MM-dd-yyyy", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"]
    private static let dayFirst = ["dd/MM/yyyy", "d/M/yyyy", "dd/MM/yy", "dd-MM-yyyy"]

    static func date(_ s: String, dayFirstFirst: Bool) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 6, t.count <= 25, t.contains(where: { $0.isNumber }) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let list = dayFirstFirst ? dayFirst + formats : formats + dayFirst
        for fmt in list {
            f.dateFormat = fmt
            if let d = f.date(from: t) {
                let year = Calendar.current.component(.year, from: d)
                if year > 1990 && year < 2100 { return d }
            }
        }
        return nil
    }

    /// True when slash dates in this column are written day-first (a first number over 12 appears).
    static func looksDayFirst(_ values: [String]) -> Bool {
        values.contains { v in
            let parts = v.split(separator: "/")
            return parts.count == 3 && (Int(parts[0]) ?? 0) > 12
        }
    }

    // MARK: Columns

    private static func find(_ header: [String], _ words: [String], avoid: [String] = []) -> Int? {
        for w in words {
            if let i = header.firstIndex(where: { h in h.contains(w) && !avoid.contains { h.contains($0) } }) { return i }
        }
        return nil
    }

    static func parse(_ text: String) -> Result {
        let grid = table(text)
        guard !grid.isEmpty else { return Result(rows: [], usedSignGuess: false) }

        // Find the header row (some banks put a few lines of account info first)
        let headerIndex = grid.prefix(15).firstIndex { row in
            let lower = row.map { $0.lowercased() }
            return lower.contains { $0.contains("date") } && lower.count >= 3
        }
        var dateCol: Int?, descCol: Int?, amountCol: Int?, debitCol: Int?, creditCol: Int?, typeCol: Int?
        let body: [[String]]
        if let h = headerIndex {
            let header = grid[h].map { $0.lowercased() }
            body = Array(grid[(h + 1)...])
            dateCol = find(header, ["transaction date", "trans. date", "trans date", "date"], avoid: ["post", "settle"])
                ?? find(header, ["date"])
            descCol = find(header, ["description", "merchant", "payee", "name", "details", "narrative", "memo", "transaction"],
                           avoid: ["date", "type", "category", "id"])
            debitCol = find(header, ["debit", "withdrawal", "money out", "paid out", "charges"])
            creditCol = find(header, ["credit", "deposit", "money in", "paid in", "payments"], avoid: ["card"])
            amountCol = find(header, ["amount", "cad$", "usd$", "value"], avoid: ["balance"])
            typeCol = find(header, ["type"], avoid: ["account"])
            if debitCol != nil && debitCol == creditCol { creditCol = nil }
        } else {
            // No header (e.g. TD): work it out from the values
            body = grid
            let width = grid.map(\.count).max() ?? 0
            let sample = Array(grid.prefix(30))
            func share(_ col: Int, _ test: (String) -> Bool) -> Double {
                var total = 0
                var hits = 0
                for row in sample where row.indices.contains(col) && !row[col].isEmpty {
                    total += 1
                    if test(row[col]) { hits += 1 }
                }
                return total == 0 ? 0 : Double(hits) / Double(total)
            }
            func isDate(_ v: String) -> Bool { date(v, dayFirstFirst: false) != nil }
            func isMoney(_ v: String) -> Bool { money(v) != nil }
            func totalLength(_ col: Int) -> Int {
                var n = 0
                for row in sample where row.indices.contains(col) { n += row[col].count }
                return n
            }
            dateCol = nil
            for col in 0..<width where share(col, isDate) > 0.8 { dateCol = col; break }
            var numeric: [Int] = []
            for col in 0..<width where col != dateCol && share(col, isMoney) > 0.6 { numeric.append(col) }
            var bestText: Int?
            var bestLength = -1
            for col in 0..<width where col != dateCol && !numeric.contains(col) {
                let len = totalLength(col)
                if len > bestLength { bestLength = len; bestText = col }
            }
            descCol = bestText
            if numeric.count >= 2 { debitCol = numeric[0]; creditCol = numeric[1] }   // debit, credit, (balance)
            else { amountCol = numeric.first }
        }
        guard let dCol = dateCol, let tCol = descCol else { return Result(rows: [], usedSignGuess: false) }
        let split = debitCol != nil && (creditCol != nil || amountCol == nil)
        let dayFirst = looksDayFirst(body.compactMap { $0.indices.contains(dCol) ? $0[dCol] : nil })

        func cell(_ row: [String], _ c: Int?) -> String { c.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? "" }

        var rows: [ImportRow] = []
        for r in body {
            guard let d = date(cell(r, dCol), dayFirstFirst: dayFirst) else { continue }
            let title = cell(r, tCol).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            var signed: Double = 0
            var splitExpense = true
            if split {
                let debit = money(cell(r, debitCol)).map(abs) ?? 0
                let credit = money(cell(r, creditCol)).map(abs) ?? 0
                if debit > 0 { signed = -debit; splitExpense = true }
                else if credit > 0 { signed = credit; splitExpense = false }
                else { continue }
            } else {
                guard let v = money(cell(r, amountCol)), v != 0 else { continue }
                signed = v
            }
            var typeHint: Bool?
            let type = cell(r, typeCol).lowercased()
            if !type.isEmpty {
                if ["sale", "purchase", "debit", "fee", "interest", "withdrawal", "charge"].contains(where: { type.contains($0) }) { typeHint = true }
                else if ["payment", "credit", "refund", "return", "deposit", "adjustment"].contains(where: { type.contains($0) }) { typeHint = false }
            }
            rows.append(ImportRow(date: d, title: title, amount: abs(signed), signed: signed, fromSplitColumns: split,
                                  splitIsExpense: splitExpense, typeHint: typeHint, isExpense: true, category: .other,
                                  include: true, isDuplicate: false, isCardPayment: false))
        }
        let usedGuess = !split && !rows.contains { $0.typeHint != nil }
        return Result(rows: rows, usedSignGuess: usedGuess)
    }

    // MARK: After reading

    static func isCardPayment(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["payment thank you", "payment - thank you", "payment received", "autopay", "auto pay", "online payment",
                "mobile payment", "payment from", "credit card payment", "card payment", "pymt", "online banking payment",
                "transfer to", "transfer from", "internet transfer", "balance transfer"].contains { t.contains($0) }
    }

    static func incomeCategory(_ title: String) -> TransactionCategory {
        let t = title.lowercased()
        if ["payroll", "salary", "direct dep", "pay "].contains(where: { t.contains($0) }) { return .salary }
        return .other
    }

    /// Same day (±1), same amount, and the names share a word: already in the app.
    static func isDuplicate(_ row: ImportRow, existing: [Transaction]) -> Bool {
        let cal = Calendar.current
        let rowDay = cal.startOfDay(for: row.date)
        var words: [String] = []
        for part in row.title.lowercased().split(whereSeparator: { !$0.isLetter }) where part.count >= 3 {
            words.append(String(part))
        }
        for t in existing {
            if abs(t.amount - row.amount) >= 0.005 { continue }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: t.date), to: rowDay).day ?? 9
            if abs(days) > 1 { continue }
            let other = t.title.lowercased()
            if words.isEmpty || other.count < 3 { return true }
            for w in words where other.contains(w) { return true }
        }
        return false
    }
}

// MARK: - Statements shared through the share sheet

/// Statements the share extension left in the App Group for Finance to import.
enum PendingStatements {
    static func next() -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.kelly.kellylife") else { return nil }
        let dir = base.appendingPathComponent("PendingStatements", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }
}

// MARK: - PDF statements

enum BankPDF {
    /// Text lines from every page. Scanned PDFs (no text) are read with text recognition.
    /// The PDF's own text, page by page.
    static func textLines(_ url: URL) -> [String] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var out: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let text = page.string else { continue }
            out += text.components(separatedBy: .newlines)
        }
        return out
    }

    /// Reads each page as a picture, one line per row, the way it looks on screen.
    static func ocrLines(_ url: URL) async -> [String] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var out: [String] = []
        for i in 0..<min(doc.pageCount, 15) {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2200 / max(bounds.width, bounds.height, 1)
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            out += await RecipeOCR.lines(in: image, joinWrapped: false, skipScreenBars: false)
        }
        return out
    }

    /// Tries the PDF's text first; if that finds few transactions (columns come out jumbled
    /// in some statements), reads the pages as pictures and keeps whichever found more.
    static func parseFile(_ url: URL) async -> BankCSV.Result {
        let fromText = parse(textLines(url))
        if fromText.rows.count >= 8 { return fromText }
        let fromPictures = parse(await ocrLines(url))
        return fromPictures.rows.count > fromText.rows.count ? fromPictures : fromText
    }

    private static let datePattern = #"(?:\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}(?:/\d{2,4})?|[A-Za-z]{3}\.?\s?\d{1,2}(?:,?\s\d{4})?|\d{1,2}\s?[A-Za-z]{3}(?:\s\d{4})?)"#
    private static let amountPattern = #"(?:\(?-?\s?\$?\s?-?[\d,]+\.\d{2}\)?(?:\s?CR)?-?)"#
    private static let lineRegex = try! NSRegularExpression(
        pattern: "^\\s*(" + datePattern + ")\\s+(?:(" + datePattern + ")\\s+)?(.+?)\\s+(" + amountPattern + ")(?:\\s+(" + amountPattern + "))?\\s*$",
        options: .caseInsensitive)

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        let r = m.range(at: i)
        guard r.location != NSNotFound else { return nil }
        return (s as NSString).substring(with: r)
    }

    /// The statement's year (most common 4-digit year near the top), so "Oct 03" gets the right year.
    private static func statementYear(_ lines: [String]) -> Int {
        var counts: [Int: Int] = [:]
        let re = try! NSRegularExpression(pattern: #"\b(20\d{2})\b"#)
        for line in lines.prefix(80) {
            for m in re.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                if let y = Int((line as NSString).substring(with: m.range(at: 1))) { counts[y, default: 0] += 1 }
            }
        }
        return counts.max { $0.value < $1.value }?.key ?? Calendar.current.component(.year, from: Date())
    }

    private static func date(_ raw: String, year: Int) -> Date? {
        var t = raw.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        if let d = BankCSV.date(t, dayFirstFirst: false) { return d }
        // "Oct03" → "Oct 03", "03Oct" → "03 Oct"
        t = t.replacingOccurrences(of: #"([A-Za-z])(\d)"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d)([A-Za-z])"#, with: "$1 $2", options: .regularExpression)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        var found: Date?
        if t.contains("/") {
            f.dateFormat = "M/d/yyyy"
            found = f.date(from: t + "/\(year)")
        } else {
            for fmt in ["MMM d yyyy", "d MMM yyyy"] {
                f.dateFormat = fmt
                if let d = f.date(from: t + " \(year)") { found = d; break }
            }
        }
        guard let d = found else { return nil }
        // A December purchase on a January statement belongs to last year
        if d > Date().addingTimeInterval(86_400 * 2) {
            return Calendar.current.date(byAdding: .year, value: -1, to: d)
        }
        return d
    }

    /// Removes symbols statements put next to amounts and dates (Amex ⧫, *, ◆…).
    static func clean(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in raw.unicodeScalars {
            let privateUse = (0xE000...0xF8FF).contains(u.value)
            let symbol = ["⧫", "◆", "♦", "✱", "*", "†", "‡", "•"].contains(Character(u))
            scalars.append(privateUse || symbol ? " " : u)
        }
        return String(scalars).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let startsWithDate = try! NSRegularExpression(pattern: "^\\s*" + datePattern + "\\b", options: .caseInsensitive)

    static func parse(_ lines: [String]) -> BankCSV.Result {
        let year = statementYear(lines)
        var rows: [ImportRow] = []
        var lastBalance: Double?
        var usedBalance = false
        var pending: String?     // a transaction whose amount is on a following line

        func tryRow(_ line: String) -> Bool {
            let ns = line as NSString
            guard let m = lineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let dateText = group(m, 1, line), let d = date(dateText, year: year),
                  var title = group(m, 3, line), let amountText = group(m, 4, line),
                  let value = BankCSV.money(amountText.replacingOccurrences(of: " ", with: "")) else { return false }
            title = title.replacingOccurrences(of: "^(AplPay|APPLE PAY|TST)\\s+", with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespaces)
            guard title.count >= 2, value != 0 else { return false }
            // Statements with a running balance: the balance going down means money went out
            var split = false
            var splitExpense = true
            if let balanceText = group(m, 5, line), let balance = BankCSV.money(balanceText.replacingOccurrences(of: " ", with: "")) {
                if let previous = lastBalance {
                    split = true
                    splitExpense = balance < previous
                    usedBalance = true
                }
                lastBalance = balance
            }
            rows.append(ImportRow(date: d, title: title, amount: abs(value), signed: value, fromSplitColumns: split,
                                  splitIsExpense: splitExpense, typeHint: nil, isExpense: true, category: .other,
                                  include: true, isDuplicate: false, isCardPayment: false))
            return true
        }

        for raw in lines {
            let line = clean(raw.replacingOccurrences(of: "\t", with: " "))
            guard !line.isEmpty else { continue }
            let ns = line as NSString
            let isNewRecord = startsWithDate.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
            if isNewRecord {
                pending = nil
                if !tryRow(line) { pending = line }
            } else if let p = pending {
                let joined = p + " " + line
                if tryRow(joined) { pending = nil }
                else { pending = joined.count < 220 ? joined : nil }
            }
        }
        return BankCSV.Result(rows: rows, usedSignGuess: !usedBalance)
    }
}

// MARK: - Screen

struct ImportTransactionsView: View {
    @ObservedObject var store: FinanceStore
    var initialURL: URL? = nil          // a file shared to Kelly Life from another app
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [ImportRow] = []
    @State private var isLoading = false
    @State private var fileName = ""
    @State private var showPicker = false
    @State private var message: String?
    @State private var usedSignGuess = false
    @State private var flipSigns = false
    @State private var showSkipped = false

    private var selected: [ImportRow] { rows.filter(\.include) }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty {
                    introSection
                } else {
                    summarySection
                    Section {
                        ForEach($rows) { $row in
                            if showSkipped || !(row.isDuplicate || row.isCardPayment) || row.include {
                                ImportRowView(row: $row)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Transactions")
                            Spacer()
                            Button(showSkipped ? "Hide skipped" : "Show skipped") { showSkipped.toggle() }
                                .font(.caption).textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Import from Bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !rows.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import \(selected.count)") { importSelected() }
                            .fontWeight(.semibold)
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .pdf, .plainText, .text, .data]) { result in
                if case .success(let url) = result { Task { await load(url) } }
            }
            .task {
                if let initialURL, rows.isEmpty { await load(initialURL) }
            }
            .overlay {
                if isLoading { ProgressView("Reading statement…").padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12)) }
            }
        }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Bring in past purchases", systemImage: "tray.and.arrow.down")
                    .font(.headline)
                Text("Choose a CSV or PDF statement from your bank or card. You can also share a statement straight from Mail, Files or your bank's app: tap Share → Kelly Life.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("You'll see everything before it's added. Card payments and purchases already in the app are skipped.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button {
                showPicker = true
            } label: {
                Label("Choose CSV or PDF file", systemImage: "doc.badge.plus")
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var summarySection: some View {
        Section {
            let expenses = selected.filter(\.isExpense)
            let total = expenses.reduce(0) { $0 + $1.amount }
            VStack(alignment: .leading, spacing: 6) {
                Text(fileName).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                if let first = rows.map(\.date).min(), let last = rows.map(\.date).max() {
                    let range = first.formatted(date: .abbreviated, time: .omitted) + " – " + last.formatted(date: .abbreviated, time: .omitted)
                    Text("\(rows.count) transactions · \(range)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(addingText(expenses: expenses.count, total: total))
                    .font(.caption)
                let dupes = rows.filter(\.isDuplicate).count
                let payments = rows.filter(\.isCardPayment).count
                if dupes + payments > 0 {
                    Text("Skipping \(dupes) already in the app and \(payments) card payments or transfers.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if usedSignGuess {
                Toggle(isOn: $flipSigns) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Swap purchases and refunds").font(.subheadline)
                        Text("Turn on if purchases show up green (as income).").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: flipSigns) { _, _ in applyDefaults() }
            }
            HStack {
                Button("Select all") { for i in rows.indices { rows[i].include = true } }
                Spacer()
                Button("Purchases only") { for i in rows.indices { rows[i].include = rows[i].isExpense && !rows[i].isDuplicate && !rows[i].isCardPayment } }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            Button("Choose a different file") { rows = []; showPicker = true }
                .font(.subheadline)
        }
    }

    private func addingText(expenses: Int, total: Double) -> String {
        var text = "Adding \(selected.count): \(expenses) purchases (" + String(format: "$%.2f", total) + ")"
        let others = selected.count - expenses
        if others > 0 { text += ", \(others) income/refunds" }
        return text
    }

    // MARK: Actions

    private func load(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
            // Files shared from other apps are copied into Kelly Life's Inbox; tidy up afterwards
            if url.path.contains("/Inbox/") || url.path.contains("/PendingStatements/") {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let result: BankCSV.Result
        if url.pathExtension.lowercased() == "pdf" {
            result = await BankPDF.parseFile(url)
        } else {
            guard let data = try? Data(contentsOf: url), let text = BankCSV.read(data) else {
                message = "Couldn't open that file."; return
            }
            result = BankCSV.parse(text)
        }
        guard !result.rows.isEmpty else {
            message = "Couldn't find dates and amounts in that file. If it's a PDF, try the CSV download instead; statement layouts vary a lot."
            return
        }
        fileName = url.lastPathComponent
        usedSignGuess = result.usedSignGuess
        rows = result.rows
        // Purchases are usually the most common kind of row, so their sign is the majority sign
        let negatives = rows.filter { $0.signed < 0 }.count
        flipSigns = usedSignGuess && negatives < rows.count - negatives   // purchases written as positive
        applyDefaults()
        message = nil
    }

    private func applyDefaults() {
        for i in rows.indices {
            let r = rows[i]
            let expense: Bool
            if r.fromSplitColumns { expense = r.splitIsExpense }
            else if let hint = r.typeHint { expense = hint }
            else { expense = flipSigns ? r.signed > 0 : r.signed < 0 }
            rows[i].isExpense = expense
            rows[i].isCardPayment = BankCSV.isCardPayment(r.title)
            rows[i].category = expense ? PurchaseLogger.guessCategory(r.title) : BankCSV.incomeCategory(r.title)
            rows[i].isDuplicate = BankCSV.isDuplicate(rows[i], existing: store.transactions)
            rows[i].include = expense && !rows[i].isCardPayment && !rows[i].isDuplicate
        }
        // Newest first, like the Records list
        rows.sort { $0.date > $1.date }
    }

    private func importSelected() {
        let note = "Imported from \(fileName)"
        let new = selected.map { r in
            Transaction(title: r.title, amount: r.amount, type: r.isExpense ? .expense : .income,
                        category: r.category, date: r.date, note: note, emoji: r.category.emoji)
        }
        store.transactions.append(contentsOf: new)
        dismiss()
    }
}

// MARK: - One row

private struct ImportRowView: View {
    @Binding var row: ImportRow

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                row.include.toggle()
            } label: {
                Image(systemName: row.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.include ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    if row.isDuplicate { tag("Already added", .orange) }
                    if row.isCardPayment { tag("Card payment", .gray) }
                }
                .font(.caption2).foregroundStyle(.secondary)
                Menu {
                    Picker("Category", selection: $row.category) {
                        ForEach(TransactionCategory.allCases, id: \.self) { c in
                            Text("\(c.emoji) \(c.rawValue)").tag(c)
                        }
                    }
                    Button(row.isExpense ? "Mark as income / refund" : "Mark as purchase") { row.isExpense.toggle() }
                } label: {
                    Text("\(row.category.emoji) \(row.category.rawValue) ▾").font(.caption)
                }
            }
            Spacer()
            Text((row.isExpense ? "-" : "+") + String(format: "$%.2f", row.amount))
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(row.isExpense ? .red : .green)
        }
        .opacity(row.include ? 1 : 0.5)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
