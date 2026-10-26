import AppIntents
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Log Wallet purchases automatically.
//
// Adds a "Log Purchase in Kelly Life" action to the Shortcuts app. Pair it with
// a Shortcuts "Transaction" automation (runs every time you pay with Apple Pay)
// and each tap is saved as an expense in the Finance tab, with a category
// guessed from the shop name.
// Main app target only.
// ─────────────────────────────────────────────────────────────────────────────

struct LogPurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Purchase in Kelly Life"
    static let description = IntentDescription("Saves a purchase as an expense in Kelly Life's Finance tab.")
    static let openAppWhenRun = false

    @Parameter(title: "Amount", description: "For example $12.50")
    var amount: String

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Card")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let value = PurchaseLogger.parseAmount(amount), value != 0 else { return .result() }
        PurchaseLogger.add(amount: value, merchant: merchant ?? "", card: card ?? "")
        return .result()
    }
}

struct KellyLifeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPurchaseIntent(),
            phrases: ["Log a purchase in \(.applicationName)"],
            shortTitle: "Log Purchase",
            systemImageName: "creditcard"
        )
    }
}

// MARK: - Saving

@MainActor
enum PurchaseLogger {
    static let didAddPurchase = Notification.Name("KellyLife.didAddPurchase")
    private static let key = "financeTransactions"

    /// Reads "$12.34", "CA$1,234.56", "12,34 €", "-5.00" and similar.
    nonisolated static func parseAmount(_ text: String) -> Double? {
        let negative = text.contains("-") || text.contains("−")
        var digits = text.filter { $0.isNumber || $0 == "." || $0 == "," }
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
        guard let v = Double(digits) else { return nil }
        return negative ? -v : v
    }

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
