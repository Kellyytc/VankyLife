import AppIntents
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Apple Pay purchases → Finance.
//
// The "Log Purchase in Kelly Life" Shortcuts action now lives in the
// KellyLifeIntents extension (so it works without opening the app). It leaves each
// purchase in the App Group; mergePending() moves them into Finance when Kelly
// Life opens. Main app target only.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Saving

@MainActor
enum PurchaseLogger {
    static let didAddPurchase = Notification.Name("KellyLife.didAddPurchase")
    private static let key = "financeTransactions"

    /// Adds purchases the Shortcuts action saved while Kelly Life was closed.
    /// Items whose amount can't be parsed stay in the App Group so they're retried next time.
    /// Items that parse to exactly 0 are dropped.
    static func mergePending() {
        #if DEBUG
        _ = parseAmountSelfTest
        #endif
        guard let shared = UserDefaults(suiteName: "group.com.kelly.kellylife"),
              let waiting = shared.array(forKey: "pendingPurchases") as? [[String: Any]], !waiting.isEmpty else { return }
        var stillPending: [[String: Any]] = []
        for item in waiting {
            let text = item["amount"] as? String
            guard let text, let value = parseAmount(text) else {
                #if DEBUG
                print("[PurchaseLogger] Couldn't parse pending purchase, keeping it. Raw amount: \(text.map { "\"\($0)\"" } ?? "nil"), item: \(item)")
                #endif
                stillPending.append(item)
                continue
            }
            if value == 0 { continue }
            let when = (item["date"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            add(amount: value, merchant: item["merchant"] as? String ?? "", card: item["card"] as? String ?? "", date: when)
        }
        // The extension may have queued more purchases while we were looping; keep those too.
        let current = shared.array(forKey: "pendingPurchases") as? [[String: Any]] ?? []
        if current.count > waiting.count {
            stillPending.append(contentsOf: current.dropFirst(waiting.count))
        }
        if stillPending.isEmpty {
            shared.removeObject(forKey: "pendingPurchases")
        } else {
            shared.set(stillPending, forKey: "pendingPurchases")
        }
    }

    /// Reads "$5.00", "USD 5.00", "5,00", "CA$1,234.56", "12,34 €", "-5.00" and similar,
    /// including extra spaces and non-breaking spaces. Parsed as Decimal to avoid binary rounding.
    nonisolated static func parseAmount(_ text: String) -> Double? {
        let negative = text.contains("-") || text.contains("−")
        // Keep only ASCII digits and separators. This drops symbols, letters and all whitespace (incl. U+00A0, U+202F).
        var digits = text.filter { ($0.isASCII && $0.isNumber) || $0 == "." || $0 == "," }
        guard !digits.isEmpty else { return nil }
        if let lastComma = digits.lastIndex(of: ","), let lastDot = digits.lastIndex(of: ".") {
            // Whichever comes last is the decimal mark
            if lastComma > lastDot {
                digits = digits.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                digits = digits.replacingOccurrences(of: ",", with: "")
            }
        } else if let comma = digits.lastIndex(of: ",") {
            // "12,34" is a decimal; "1,234" is thousands
            let after = digits.distance(from: comma, to: digits.endIndex) - 1
            digits = after == 2 ? digits.replacingOccurrences(of: ",", with: ".") : digits.replacingOccurrences(of: ",", with: "")
        }
        // Never half-parse: Decimal(string:) accepts a valid prefix ("1.2.3" -> 1.2), so reject
        // leftover commas and multiple decimal points up front.
        guard !digits.contains(","), digits.filter({ $0 == "." }).count <= 1,
              let d = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let v = NSDecimalNumber(decimal: d).doubleValue
        return negative ? -v : v
    }

    #if DEBUG
    /// Runs once per launch (first mergePending call) and traps if a known Apple Pay format regresses.
    private static let parseAmountSelfTest: Void = {
        let cases: [(String, Double)] = [
            ("$5.00", 5), ("USD 5.00", 5), ("5,00", 5), ("12,34 €", 12.34),
            ("1,234.56", 1234.56), ("CA$1,234.56", 1234.56), ("-5.00", -5), ("5.00\u{00A0}", 5),
            ("12,34", 12.34), ("1,234", 1234),
        ]
        for (text, expected) in cases {
            let got = parseAmount(text)
            assert(got.map { abs($0 - expected) < 0.0001 } ?? false, "parseAmount(\"\(text)\") = \(String(describing: got)), expected \(expected)")
        }
        assert(parseAmount("abc") == nil && parseAmount("1.2.3") == nil, "parseAmount should reject garbage")
    }()
    #endif

    /// Adds the purchase unless the same one was logged in the last 3 minutes.
    @discardableResult
    static func add(amount: Double, merchant: String, card: String, date: Date = Date()) -> Bool {
        let d = UserDefaults.standard
        var all = (d.data(forKey: key).flatMap { try? JSONDecoder().decode([Transaction].self, from: $0) }) ?? []
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? "Apple Pay purchase" : name
        let isRefund = amount < 0
        let value = abs(amount)

        if all.contains(where: { $0.title == title && abs($0.amount - value) < 0.005 && abs($0.date.timeIntervalSince(date)) < 180 }) {
            return false
        }
        let category: TransactionCategory = isRefund ? .other : guessCategory(title)
        let note = (isRefund ? "Refund" : "Auto-added from Apple Pay") + (card.isEmpty ? "" : " · \(card)")
        all.append(Transaction(title: title, amount: value, type: isRefund ? .income : .expense,
                               category: category, date: date, note: note, emoji: category.emoji))
        if let data = try? JSONEncoder().encode(all) { d.set(data, forKey: key) }
        NotificationCenter.default.post(name: didAddPurchase, object: nil)
        return true
    }

    /// Category from the shop name. Anything unknown goes to Other; you can change it in the Finance tab.
    static func guessCategory(_ merchant: String) -> TransactionCategory {
        let m = merchant.lowercased()
        let table: [(TransactionCategory, [String])] = [
            (.grocery, ["costco", "walmart", "whole foods", "trader joe", "safeway", "kroger", "t&t", "superstore", "save-on",
                        "no frills", "loblaw", "sobeys", "aldi", "h mart", "99 ranch", "wegmans", "publix", "market", "grocery",
                        "supermarket", "超市"]),
            (.food, ["starbucks", "mcdonald", "tim hortons", "coffee", "cafe", "café", "restaurant", "bakery", "pizza", "sushi",
                     "burger", "chipotle", "subway", "kfc", "uber eats", "doordash", "skip the dishes", "grubhub", "bubble tea",
                     "boba", "kitchen", "noodle", "ramen", "dim sum", "餐", "茶"]),
            (.transport, ["uber", "lyft", "compass", "translink", "mta", "metro", "transit", "shell", "esso", "chevron", "petro",
                          "exxon", "mobil", "parking", "parkade", "evo car", "presto", "gas station"]),
            (.health, ["pharmacy", "shoppers drug", "london drugs", "cvs", "walgreens", "rexall", "clinic", "dental", "medical",
                       "physio", "optometr"]),
            (.entertainment, ["netflix", "spotify", "disney", "cinema", "cineplex", "amc", "theatre", "theater", "steam",
                              "playstation", "nintendo", "xbox", "ticketmaster"]),
            (.bills, ["rogers", "telus", "bell canada", "bell mobility", "fido", "koodo", "verizon", "at&t", "t-mobile", "hydro", "fortis", "con edison",
                      "insurance", "icloud", "apple.com/bill"]),
            (.travel, ["air canada", "westjet", "delta", "united", "american airlines", "airbnb", "hotel", "marriott", "hilton",
                       "expedia", "booking.com", "airport"]),
            (.education, ["bookstore", "university", "college", "udemy", "coursera"]),
            (.shopping, ["amazon", "apple store", "target", "uniqlo", "sephora", "h&m", "zara", "ikea", "best buy", "winners",
                         "marshalls", "tj maxx", "aritzia", "lululemon", "nike", "muji", "daiso"]),
        ]
        for (category, words) in table where words.contains(where: { m.contains($0) }) { return category }
        return .other
    }
}
