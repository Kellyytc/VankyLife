import SwiftUI
import Combine
import FoundationModels

// ─────────────────────────────────────────────────────────────────────────────
// Kelly AI — suggestions from Apple Intelligence's on-device model
// (Foundation Models framework, iOS 26). Everything runs on the iPhone:
// no account, no internet, and your data never leaves the phone.
//
// The on-device model has a small memory, so for each topic the app sends a
// short summary of only the data that topic needs.
// Needs Apple Intelligence turned on (Settings → Apple Intelligence & Siri).
// Main app target only.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Topics

enum AITopic: String, CaseIterable, Identifiable {
    case recipes, weight, health, training, money, news, chat
    var id: String { rawValue }

    var title: String {
        switch self {
        case .recipes: return "Meals & recipes"
        case .weight:  return "Weight"
        case .health:  return "Sleep & energy"
        case .training: return "Training & rest"
        case .money:   return "Money & investing"
        case .news:    return "News on my stocks"
        case .chat:    return "Ask anything"
        }
    }
    var shortTitle: String {
        switch self {
        case .recipes: return "Meals"
        case .weight:  return "Weight"
        case .health:  return "Sleep"
        case .training: return "Training"
        case .money:   return "Money"
        case .news:    return "News"
        case .chat:    return "Chat"
        }
    }
    var icon: String {
        switch self {
        case .recipes: return "fork.knife"
        case .weight:  return "scalemass"
        case .health:  return "moon.zzz"
        case .training: return "figure.run"
        case .money:   return "chart.line.uptrend.xyaxis"
        case .news:    return "newspaper"
        case .chat:    return "bubble.left.and.text.bubble.right"
        }
    }
    var color: Color {
        switch self {
        case .recipes: return .orange
        case .weight:  return .blue
        case .health:  return .purple
        case .training: return .red
        case .money:   return .green
        case .news:    return .teal
        case .chat:    return .pink
        }
    }
    /// First question asked automatically when the topic opens.
    var opener: String? {
        switch self {
        case .recipes: return "Plan my meals for today."
        case .weight:  return "How is my weight trend going compared with my goal, and what is one thing to focus on this week?"
        case .health:  return "Summarise my sleep and energy over the last two weeks and give me two practical tips."
        case .training: return "Plan my training for this week."
        case .money:   return "Give me a short overview of my portfolio and spending this month, and point out anything worth thinking about."
        case .news:    return "What's in the news about the stocks I own? For each stock, summarise what matters in one or two bullet points, and say if anything looks important to read in full."
        case .chat:    return nil
        }
    }
    var suggestions: [String] {
        switch self {
        case .recipes: return ["What can I cook with my fridge?", "What's expiring soon?", "How many calories left today?", "Plan my meals for 3 days", "High-protein breakfast ideas"]
        case .weight:  return ["Am I on track?", "Why did my weight go up?", "How many calories should I eat?", "Tips for a plateau"]
        case .health:  return ["How did I sleep last night?", "Why do I feel tired?", "How's my HRV?", "When is my next period?", "How can I sleep better?"]
        case .training: return ["Should I rest today?", "Plan my week", "Am I training too much?", "Best workouts for weight loss"]
        case .money:   return ["Is my portfolio diversified?", "Where did my money go this month?", "How are my stocks doing today?", "When do my CDs mature?"]
        case .news:    return ["Anything worrying?", "Which stock has the most news?", "Explain the biggest story simply", "Any earnings coming up?"]
        case .chat:    return ["How am I doing today?", "Why am I so tired?", "What can I cook with my fridge?",
                               "When is my next period?", "What's on tomorrow?", "What should I focus on this week?",
                               "Any overdue to-dos?", "How are my stocks today?"]
        }
    }
    var disclaimer: String {
        switch self {
        case .health, .weight, .training: return "General wellness ideas, not medical advice. Talk to a doctor about health concerns, and stop if exercise hurts."
        case .money: return "General information only, not financial advice. Prices come from Yahoo Finance and may be delayed."
        case .news: return "Headlines from Yahoo Finance. The AI reads only the headlines, not the full articles, and can misread them. Not financial advice."
        default: return "Suggestions come from Apple Intelligence on your iPhone and can be wrong."
        }
    }
}

struct AIMessage: Identifiable, Equatable {
    enum Role { case user, assistant, notice }
    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - Stock news (Yahoo Finance headlines)

struct StockHeadline: Identifiable, Hashable {
    let id: String          // article link
    let symbol: String
    let title: String
    let publisher: String
    let date: Date
    var url: URL? { URL(string: id) }
}

enum StockNews {
    private struct SearchResponse: Decodable { let news: [Item]? }
    private struct Item: Decodable {
        let title: String
        let publisher: String?
        let link: String
        let providerPublishTime: Double?
        let relatedTickers: [String]?
    }

    /// Recent headlines for each symbol (last 10 days, up to 4 per stock, 30 in total).
    static func fetch(symbols: [String]) async -> [StockHeadline] {
        let cutoff = Date().addingTimeInterval(-10 * 86_400)
        var seen = Set<String>()
        var result: [StockHeadline] = []
        await withTaskGroup(of: [StockHeadline].self) { group in
            for symbol in symbols.prefix(10) {
                group.addTask { await headlines(for: symbol, since: cutoff) }
            }
            for await list in group { result += list }
        }
        return result
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.id).inserted }
            .prefix(30)
            .map { $0 }
    }

    private static func headlines(for symbol: String, since cutoff: Date) async -> [StockHeadline] {
        var c = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        c.queryItems = [.init(name: "q", value: symbol), .init(name: "quotesCount", value: "0"),
                        .init(name: "newsCount", value: "8")]
        guard let url = c.url else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return [] }
        return (decoded.news ?? []).compactMap { item -> StockHeadline? in
            let date = item.providerPublishTime.map { Date(timeIntervalSince1970: $0) } ?? Date()
            guard date >= cutoff else { return nil }
            // Keep stories that are about this stock (when Yahoo says which tickers a story covers)
            if let tickers = item.relatedTickers, !tickers.isEmpty,
               !tickers.contains(where: { $0.uppercased() == symbol.uppercased() }) { return nil }
            return StockHeadline(id: item.link, symbol: symbol, title: item.title,
                                 publisher: item.publisher ?? "", date: date)
        }
        .prefix(4).map { $0 }
    }
}

// MARK: - Data summaries (kept short so they fit the on-device model)

@MainActor
enum AIContext {
    private static let d = UserDefaults.standard

    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func profile() -> String {
        let name = d.string(forKey: "userName") ?? "Kelly"
        let height = d.double(forKey: "userHeight")
        let age = d.integer(forKey: "userAge")
        let goal = d.integer(forKey: "dailyCalorieGoal")
        let weekly = d.double(forKey: "weeklyWeightGoal")
        let latest = WeightLog.loadAll().max { $0.date < $1.date }?.weight ?? d.double(forKey: "userWeight")
        var s = "User: \(name), female"
        if age > 0 { s += ", \(age) years old" }
        if height > 0 { s += ", \(Int(height)) cm" }
        if latest > 0 {
            s += ", \(String(format: "%.1f", latest)) kg"
            if height > 0 { s += String(format: " (BMI %.1f)", latest / pow(height / 100, 2)) }
        }
        s += ". Goal: lose weight"
        if weekly > 0 { s += String(format: " about %.1f kg per week", weekly) }
        if goal > 0 { s += "; daily calorie goal \(goal) kcal" }
        return s + "."
    }

    static func meals(days: Int = 7) -> String {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date())) ?? Date()
        let recent = ManualMeal.loadAll().filter { $0.date >= start }.sorted { $0.date < $1.date }
        guard !recent.isEmpty else { return "Meals logged in the last \(days) days: none." }
        let byDay = Dictionary(grouping: recent) { cal.startOfDay(for: $0.date) }
        var lines = ["Meals logged (last \(days) days):"]
        for dayDate in byDay.keys.sorted() {
            let items = byDay[dayDate] ?? []
            let total = items.reduce(0) { $0 + $1.calories }
            let names = items.prefix(5).map { "\($0.name) \($0.calories)" }.joined(separator: ", ")
            lines.append("- \(day(dayDate)): \(total) kcal (\(names))")
        }
        return lines.joined(separator: "\n")
    }

    static func recipes() -> String {
        let all = RecipeStore().recipes
        guard !all.isEmpty else { return "Saved recipes: none yet." }
        let list = all.prefix(20).map { r -> String in
            var s = "- \(r.displayTitle)"
            if !r.tags.isEmpty { s += " [\(r.tags.prefix(3).joined(separator: ", "))]" }
            if r.isFavorite { s += " ♥" }
            let p = r.parsed
            if !p.ingredients.isEmpty { s += ": " + p.ingredients.prefix(3).joined(separator: "; ") }
            return String(s.prefix(120))
        }
        return "Saved recipes (title [tags]: main ingredients):\n" + list.joined(separator: "\n")
    }

    static func weight() -> String {
        let logs = WeightLog.loadAll().sorted { $0.date < $1.date }
        guard !logs.isEmpty else { return "Weight logs: none yet." }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let recent = logs.filter { $0.date >= cutoff }
        let use = recent.isEmpty ? Array(logs.suffix(10)) : recent
        // Weekly averages keep this short
        let byWeek = Dictionary(grouping: use) { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        var lines = ["Weight (weekly averages, last 60 days):"]
        for w in byWeek.keys.sorted() {
            let vals = byWeek[w]!.map(\.weight)
            lines.append(String(format: "- week of %@: %.1f kg (%d logs)", day(w), vals.reduce(0, +) / Double(vals.count), vals.count))
        }
        if let first = use.first, let last = use.last {
            lines.append(String(format: "Change: %.1f kg → %.1f kg (%+.1f kg) from %@ to %@.",
                                first.weight, last.weight, last.weight - first.weight, day(first.date), day(last.date)))
        }
        if let lo = use.map(\.weight).min(), let hi = use.map(\.weight).max() {
            lines.append(String(format: "Range: %.1f–%.1f kg.", lo, hi))
        }
        return lines.joined(separator: "\n")
    }

    static func health(_ energy: EnergyStore) -> String {
        let days = energy.lastDays(14).filter { $0.hasSleep || $0.hrv != nil || $0.steps != nil }
        guard !days.isEmpty else { return "Sleep and health data: none available." }
        var lines = ["Sleep & body (last 14 days; energy and readiness are 0–100):"]
        for dd in days {
            let sc = energy.scores[dd.date]
            var parts: [String] = []
            if dd.hasSleep { parts.append(String(format: "sleep %.1fh (deep %.1f, REM %.1f)", dd.sleepHours, dd.deep, dd.rem)) }
            if let h = dd.hrv { parts.append("HRV \(Int(h))ms") }
            if let r = dd.rhr { parts.append("RHR \(Int(r))") }
            if let st = dd.steps { parts.append("steps \(Int(st))") }
            if let a = dd.activeMinutes { parts.append("active \(Int(a))min") }
            if let rd = sc?.readiness { parts.append("readiness \(rd)\(sc?.readinessFromOura == true ? " (Oura)" : "")") }
            if let e = sc?.energy { parts.append("energy \(e)") }
            lines.append("- \(day(dd.date)): " + parts.joined(separator: ", "))
        }
        if let t = energy.ouraReadiness[Calendar.current.startOfDay(for: Date())]?.temperatureDeviation {
            lines.append(String(format: "Today's body temperature vs normal: %+.1f°C.", t))
        }
        return lines.joined(separator: "\n")
    }

    static func headlines(_ items: [StockHeadline]) -> String {
        guard !items.isEmpty else { return "Recent headlines: none found (or no internet connection)." }
        let lines = items.map { "- [\($0.symbol)] \(day($0.date)), \($0.publisher): \($0.title)" }
        return "Recent headlines (newest first, headline text only):\n" + lines.joined(separator: "\n")
    }

    static func stockList(_ finance: FinanceStore) -> String {
        let holdings = finance.stockHoldings.filter { $0.shares > 0.0001 }
        let total = holdings.reduce(0) { $0 + $1.totalValue }
        guard !holdings.isEmpty else { return "Stocks owned: none." }
        let list = holdings.sorted { $0.totalValue > $1.totalValue }.map {
            String(format: "%@ (%.0f%% of stocks, %+.1f%% since bought)", $0.symbol,
                   total > 0 ? $0.totalValue / total * 100 : 0, $0.gainLossPercent)
        }
        return "Stocks owned: " + list.joined(separator: "; ") + "."
    }

    static func workouts(_ energy: EnergyStore, days: Int = 14) -> String {
        let list = energy.recentWorkouts(days: days)
        guard !list.isEmpty else { return "Workouts (last \(days) days): none recorded." }
        let week = energy.recentWorkouts(days: 7)
        var lines = [String(format: "Workouts (last %d days): %d workouts. Last 7 days: %d workouts, %.0f minutes.",
                            days, list.count, week.count, week.reduce(0) { $0 + $1.minutes })]
        for w in list.prefix(14) {
            var s = "- \(day(w.start)): \(w.name) \(Int(w.minutes.rounded())) min"
            if let k = w.kcal { s += ", \(Int(k)) kcal" }
            if let hr = w.avgHeartRate { s += ", avg HR \(Int(hr))" }
            lines.append(s)
        }
        return lines.joined(separator: "\n")
    }

    /// Short "how recovered am I today" line for training advice.
    static func recoveryToday(_ energy: EnergyStore) -> String {
        guard let latest = energy.latestScored else { return "Today's recovery: unknown (not enough data yet)." }
        let sc = latest.score, d = latest.day
        var parts: [String] = []
        if let r = sc.readiness { parts.append("readiness \(r)/100\(sc.readinessFromOura ? " (Oura)" : "")") }
        if let e = sc.energy { parts.append("energy \(e)/100") }
        if let h = sc.hrv { parts.append("HRV score \(h)/100 (80 = normal for her)") }
        if d.hasSleep { parts.append(String(format: "slept %.1fh last night", d.sleepHours)) }
        if let rhr = d.rhr { parts.append("resting HR \(Int(rhr))") }
        return "Today's recovery (\(day(d.date))): " + parts.joined(separator: ", ") + "."
    }

    static func money(_ finance: FinanceStore) -> String {
        MoneyFacts(finance).factLines.joined(separator: "\n")
    }
}

// MARK: - Money facts (all numbers worked out by the app, never by the AI)

struct MoneyFacts {
    struct Holding { let symbol: String; let value: Double; let share: Double; let gainPct: Double; let group: String }

    let holdings: [Holding]          // largest first
    let stocksTotal: Double
    let stocksCost: Double
    let cdsTotal: Double
    let groups: [(name: String, share: Double, symbols: [String])]
    let cds: [CDAccount]
    let spent: Double
    let income: Double
    let budget: Double
    let topCategories: [(String, Double)]
    let hasTransactions: Bool

    init(_ finance: FinanceStore) {
        let raw = finance.stockHoldings.filter { $0.shares > 0.0001 }
        let total = raw.reduce(0) { $0 + $1.totalValue }
        stocksTotal = total
        stocksCost = raw.reduce(0) { $0 + $1.totalCost }
        holdings = raw.sorted { $0.totalValue > $1.totalValue }.map {
            Holding(symbol: $0.symbol, value: $0.totalValue,
                    share: total > 0 ? $0.totalValue / total * 100 : 0,
                    gainPct: $0.gainLossPercent, group: MoneyFacts.group(for: $0.symbol))
        }
        let byGroup = Dictionary(grouping: holdings, by: \.group)
        groups = byGroup.map { (name: $0.key, share: $0.value.reduce(0) { $0 + $1.share }, symbols: $0.value.map(\.symbol)) }
            .sorted { $0.share > $1.share }
        cds = finance.cdAccounts.sorted { $0.maturityDate < $1.maturityDate }
        cdsTotal = cds.reduce(0) { $0 + $1.principal }

        let cal = Calendar.current
        let monthStart = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        let month = finance.transactions.filter { $0.date >= monthStart }
        hasTransactions = !month.isEmpty
        let expenses = month.filter { $0.type == .expense }
        spent = expenses.reduce(0) { $0 + $1.amount }
        income = month.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        budget = finance.overallMonthlyBudget
        topCategories = Dictionary(grouping: expenses, by: \.category)
            .map { ($0.key.rawValue, $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
    }

    /// Rough grouping for common tickers. Unknown ones go to "Other".
    static func group(for symbol: String) -> String {
        let s = symbol.uppercased().replacingOccurrences(of: ".TO", with: "").replacingOccurrences(of: ".NE", with: "")
        let table: [String: [String]] = [
            "Tech & growth stocks": ["AAPL", "MSFT", "NVDA", "GOOGL", "GOOG", "META", "AMZN", "TSLA", "AMD", "INTC", "AVGO",
                                     "TSM", "ORCL", "CRM", "ADBE", "NFLX", "PLTR", "SHOP", "UBER", "QCOM", "MU", "ARM", "SMCI",
                                     "IBM", "CSCO", "SNOW", "COIN", "SQ", "PYPL", "SPOT", "ABNB", "RBLX", "BABA", "PDD", "JD"],
            "Tech funds": ["QQQ", "QQQM", "XLK", "VGT", "SMH", "SOXX", "ARKK", "XIT"],
            "Broad-market funds": ["SPY", "VOO", "IVV", "VTI", "VT", "VXUS", "SCHB", "ITOT", "SPLG", "RSP", "DIA", "IWM",
                                   "VEA", "VWO", "XEQT", "VEQT", "VFV", "XUU", "ZSP", "VGRO", "XGRO", "XIC", "VCN", "ZCN", "XIU"],
            "Gold & commodities": ["GLD", "IAU", "SLV", "GDX", "PHYS", "CGL", "SGOL"],
            "Bonds": ["BND", "AGG", "TLT", "SHY", "IEF", "ZAG", "XBB", "VAB", "BNDX"],
            "Healthcare": ["JNJ", "PFE", "LLY", "NVO", "UNH", "MRK", "ABBV", "AMGN", "MRNA"],
            "Banks & finance": ["JPM", "BAC", "WFC", "C", "GS", "MS", "V", "MA", "AXP", "BRK.B", "BRK-B", "RY", "TD", "BNS", "BMO", "CM"],
            "Consumer brands": ["KO", "PEP", "COST", "WMT", "MCD", "NKE", "SBUX", "PG", "DIS", "LULU", "TGT", "HD"],
            "Energy": ["XOM", "CVX", "SHEL", "BP", "ENB", "SU", "CNQ"],
        ]
        for (name, list) in table where list.contains(s) { return name }
        return "Other"
    }

    private static func usd(_ v: Double) -> String { "$" + Int(v.rounded()).formatted() }
    private static func pct(_ v: Double) -> String { String(format: "%.0f%%", v) }
    private static func day(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day().year()) }

    /// Plain facts for the AI (no conclusions for it to get wrong).
    var factLines: [String] {
        var out: [String] = []
        let all = stocksTotal + cdsTotal
        if all > 0 {
            out.append("Total investments \(Self.usd(all)): stocks \(Self.usd(stocksTotal)) (\(Self.pct(stocksTotal / all * 100))), CDs \(Self.usd(cdsTotal)) (\(Self.pct(cdsTotal / all * 100))).")
        }
        if holdings.isEmpty {
            out.append("Stocks: none.")
        } else {
            let gain = stocksTotal - stocksCost
            out.append("Stocks: \(holdings.count) holdings, worth \(Self.usd(stocksTotal)), cost \(Self.usd(stocksCost)), overall \(gain >= 0 ? "up" : "down") \(Self.usd(abs(gain))) (\(String(format: "%+.1f%%", stocksCost > 0 ? gain / stocksCost * 100 : 0))).")
            out.append("Holdings, largest first (share of stocks): " + holdings.prefix(12).map { "\($0.symbol) \(Self.pct($0.share)) (\(String(format: "%+.0f%%", $0.gainPct)))" }.joined(separator: ", ") + ".")
            let top3 = holdings.prefix(3).reduce(0) { $0 + $1.share }
            out.append("Largest holding: \(holdings[0].symbol) at \(Self.pct(holdings[0].share)) of stocks. Top 3 together: \(Self.pct(top3)).")
            out.append("By type: " + groups.map { "\($0.name) \(Self.pct($0.share)) (\($0.symbols.joined(separator: ", ")))" }.joined(separator: "; ") + ".")
            if let best = holdings.max(by: { $0.gainPct < $1.gainPct }), let worst = holdings.min(by: { $0.gainPct < $1.gainPct }) {
                out.append("Best: \(best.symbol) \(String(format: "%+.0f%%", best.gainPct)). Worst: \(worst.symbol) \(String(format: "%+.0f%%", worst.gainPct)).")
            }
        }
        if cds.isEmpty {
            out.append("CDs: none.")
        } else {
            let avg = cdsTotal > 0 ? cds.reduce(0) { $0 + $1.annualRate * $1.principal } / cdsTotal : 0
            out.append("CDs: \(cds.count), total \(Self.usd(cdsTotal)), average rate \(String(format: "%.2f%%", avg)). Maturities: " +
                       cds.map { "\(Self.usd($0.principal)) at \(String(format: "%.2f%%", $0.annualRate)) on \(Self.day($0.maturityDate))" }.joined(separator: "; ") + ".")
        }
        if !hasTransactions {
            out.append("Spending this month: nothing recorded in the app, so there is no spending data to comment on.")
        } else {
            var line = "Spending this month: \(Self.usd(spent))"
            if income > 0 { line += ", income \(Self.usd(income))" }
            if budget > 0 { line += ", budget \(Self.usd(budget)) (\(Self.pct(spent / budget * 100)) used)" }
            if !topCategories.isEmpty { line += ". Top: " + topCategories.prefix(5).map { "\($0.0) \(Self.usd($0.1))" }.joined(separator: ", ") }
            out.append(line + ".")
        }
        return out
    }

    /// The overview shown to the user, built by the app.
    var overview: String {
        var out: [String] = []
        let all = stocksTotal + cdsTotal
        out.append("**Your money snapshot**")
        if all > 0 {
            out.append("- Total invested: **\(Self.usd(all))**: stocks \(Self.usd(stocksTotal)) (\(Self.pct(stocksTotal / all * 100))), CDs \(Self.usd(cdsTotal)) (\(Self.pct(cdsTotal / all * 100)))")
        }
        if !holdings.isEmpty {
            let gain = stocksTotal - stocksCost
            out.append("- Stocks: \(holdings.count) holdings, \(gain >= 0 ? "up" : "down") \(Self.usd(abs(gain))) (\(String(format: "%+.1f%%", stocksCost > 0 ? gain / stocksCost * 100 : 0))) overall")
            let top3 = holdings.prefix(3).reduce(0) { $0 + $1.share }
            out.append("- Largest: \(holdings.prefix(3).map { "\($0.symbol) \(Self.pct($0.share))" }.joined(separator: ", ")) (top 3 = \(Self.pct(top3)) of stocks)")
            out.append("- By type: " + groups.map { "\($0.name) \(Self.pct($0.share))" }.joined(separator: " · "))
        }
        if !cds.isEmpty, let next = cds.first {
            let avg = cdsTotal > 0 ? cds.reduce(0) { $0 + $1.annualRate * $1.principal } / cdsTotal : 0
            out.append("- CDs: \(cds.count) totalling \(Self.usd(cdsTotal)), average \(String(format: "%.2f%%", avg)); next one matures \(Self.day(next.maturityDate)) (\(Self.usd(next.principal)))")
        }
        if hasTransactions {
            var line = "- Spending this month: \(Self.usd(spent))"
            if budget > 0 { line += " of \(Self.usd(budget)) budget" }
            if let top = topCategories.first { line += "; most on \(top.0) (\(Self.usd(top.1)))" }
            out.append(line)
        } else {
            out.append("- Spending this month: none recorded yet")
        }
        return out.joined(separator: "\n")
    }
}

// MARK: - Live market check (all numbers come from Yahoo and are worked out by the app)

struct LiveQuote {
    let symbol: String
    let price: Double
    let prevClose: Double
    let time: Date?
    var change: Double { price - prevClose }
    var changePct: Double { prevClose > 0 ? change / prevClose * 100 : 0 }
}

enum MarketData {
    static let indexes: [(symbol: String, name: String)] = [
        ("^GSPC", "S&P 500"), ("^IXIC", "Nasdaq"), ("^DJI", "Dow"), ("^GSPTSE", "TSX"),
    ]

    static func quote(_ symbol: String) async -> LiveQuote? {
        let sym = symbol.uppercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: ".-"))) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(sym)?interval=5m&range=1d") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = json["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double,
              let prev = (meta["chartPreviousClose"] as? Double) ?? (meta["previousClose"] as? Double)
        else { return nil }
        let time = (meta["regularMarketTime"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return LiveQuote(symbol: symbol, price: price, prevClose: prev, time: time)
    }

    static func quotes(_ symbols: [String]) async -> [String: LiveQuote] {
        var out: [String: LiveQuote] = [:]
        await withTaskGroup(of: LiveQuote?.self) { group in
            for s in Set(symbols) { group.addTask { await quote(s) } }
            for await q in group { if let q { out[q.symbol] = q } }
        }
        return out
    }
}

enum MoneyFormat {
    static func usd(_ v: Double, cents: Bool = false) -> String {
        let n = abs(v)
        return "$" + (cents ? n.formatted(.number.precision(.fractionLength(2))) : Int(n.rounded()).formatted())
    }
    static func signedUSD(_ v: Double) -> String { (v >= 0 ? "+" : "−") + usd(v, cents: abs(v) < 100) }
    static func signedPct(_ v: Double) -> String { (v >= 0 ? "+" : "−") + String(format: "%.2f%%", abs(v)) }
    static func arrow(_ v: Double) -> String { v > 0.005 ? "▲" : (v < -0.005 ? "▼" : "•") }
}

// MARK: - Structured meal plan (forces breakfast, lunch, dinner and snack every day)

@Generable
struct PlannedMeal {
    @Guide(description: "Name of a common, healthy home-cooked dish")
    var name: String
    @Guide(description: "Approximate calories for one portion", .range(50...900))
    var calories: Int
}

@Generable
struct PlannedDay {
    var breakfast: PlannedMeal
    var lunch: PlannedMeal
    var dinner: PlannedMeal
    var snack: PlannedMeal
}

@Generable
struct MealPlan {
    @Guide(description: "One entry per day, in order")
    var days: [PlannedDay]
    @Guide(description: "One short, practical tip for following this plan")
    var tip: String
}

// MARK: - Structured training plan

@Generable
struct TrainingDay {
    @Guide(description: "Activity, e.g. Rest, Walk, Yoga, Stretching, Strength training, Running, Cycling, Swimming, HIIT, Pilates")
    var activity: String
    @Guide(description: "How hard the day is", .anyOf(["rest", "easy", "moderate", "hard"]))
    var intensity: String
    @Guide(description: "Minutes of exercise; 0 for a full rest day", .range(0...120))
    var minutes: Int
    @Guide(description: "A few words on why, based on her recovery and recent workouts")
    var why: String
}

@Generable
struct TrainingPlan {
    @Guide(description: "One or two sentences: should she train hard, go easy or rest today, and why")
    var today: String
    @Guide(description: "One entry per day starting today, in order")
    var days: [TrainingDay]
    @Guide(description: "One short practical tip for the week")
    var tip: String
}

// MARK: - Assistant

@MainActor
final class KellyAI: ObservableObject {
    @Published private(set) var messages: [AIMessage] = []
    @Published private(set) var isThinking = false
    @Published private(set) var isPreparing = false
    @Published private(set) var topic: AITopic = .chat
    @Published private(set) var headlines: [StockHeadline] = []

    private var session: LanguageModelSession?
    private var instructions = ""
    private let finance: FinanceStore
    private let energy = EnergyStore()
    private var energyLoaded = false
    private var lastTurn: KellyBrain.Turn?

    init(finance: FinanceStore) { self.finance = finance }

    /// nil when ready; otherwise a message explaining what to do.
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri, then come back."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading its model. Keep your iPhone on Wi-Fi and charging, and try again later."
        case .unavailable(.deviceNotEligible):
            return "This iPhone doesn't support Apple Intelligence."
        default:
            return "Apple Intelligence isn't available right now."
        }
    }

    func open(_ topic: AITopic) async {
        self.topic = topic
        messages = []
        lastTurn = nil
        guard unavailableReason == nil else { return }
        isPreparing = true
        instructions = await buildInstructions(for: topic)
        isPreparing = false
        startSession()
        if let opener = topic.opener { await ask(opener, showQuestion: false) }
    }

    func ask(_ question: String, showQuestion: Bool = true) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isThinking else { return }
        if session == nil { startSession() }
        if showQuestion { messages.append(AIMessage(role: .user, text: q)) }
        isThinking = true
        defer { isThinking = false }
        do {
            let reply = try await respond(q)
            messages.append(AIMessage(role: .assistant, text: reply))
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                // The conversation got too long: start fresh with the same data and try once more.
                startSession()
                if let reply = try? await respond(q) {
                    messages.append(AIMessage(role: .notice, text: "Started a fresh conversation (the last one got too long)."))
                    messages.append(AIMessage(role: .assistant, text: reply))
                } else {
                    messages.append(AIMessage(role: .notice, text: "That was too much for the on-device AI. Try a shorter question."))
                }
            case .guardrailViolation, .refusal:
                // Apple's safety filter said no: ask again in a gentler, general-wellness way.
                if let reply = try? await gentleRetry(q), !reply.isEmpty {
                    messages.append(AIMessage(role: .assistant, text: reply))
                } else {
                    messages.append(AIMessage(role: .notice, text: "Apple Intelligence couldn't answer that one. Try asking in a different way, for example \"How can I lose weight in a healthy way?\""))
                }
            default:
                messages.append(AIMessage(role: .notice, text: "Something went wrong: \(error.localizedDescription)"))
            }
        } catch {
            messages.append(AIMessage(role: .notice, text: "Something went wrong: \(error.localizedDescription)"))
        }
    }

    private func respond(_ q: String) async throws -> String {
        guard let session else { return "" }
        let intents = AskIntent.detect(q)
        if topic != .money && topic != .news, let target = Self.goalWeight(in: q) {
            if let plan = await goalPlan(target: target, question: q) { return plan }
        }
        if let days = Self.planDays(in: q),
           topic == .recipes || intents.contains(.food) || intents.contains(.recipes) {
            return try await mealPlan(days: days, request: q, session: session)
        }
        if topic == .money, Self.wantsMoneyOverview(q) {
            return try await moneyOverview(request: q, session: session)
        }
        if topic == .money || topic == .news || topic == .chat || intents.contains(.stocks) {
            if let answer = await moneyAnswer(q) { return answer }
        }
        if Self.wantsTrainingPlan(q), topic == .training || intents.contains(.workouts) {
            await loadEnergyIfNeeded()
            return try await trainingPlan(request: q, session: session)
        }

        // Everything else: the app's numbers for what was asked + advice from the AI
        await loadEnergyIfNeeded()
        if (intents.contains(.news) || (intents.isEmpty && topic == .news)) && headlines.isEmpty {
            let symbols = finance.stockHoldings.filter { $0.shares > 0.0001 }.map(\.symbol)
            headlines = await StockNews.fetch(symbols: symbols)
        }
        let result = await KellyBrain.answer(q, topic: topic, previous: lastTurn, energy: energy,
                                             finance: finance, headlines: headlines)
        lastTurn = KellyBrain.Turn(question: q, answer: result.text, intents: result.intents)
        return result.text
    }

    /// Number of days if the question asks for a meal plan, otherwise nil.
    private static func planDays(in q: String) -> Int? {
        let lower = q.lowercased()
        let wantsPlan = ["plan", "menu", "what should i eat", "计划", "菜单", "吃什么"].contains { lower.contains($0) }
        guard wantsPlan else { return nil }
        if let digit = lower.first(where: { $0.isNumber }), let n = Int(String(digit)), (1...7).contains(n) { return n }
        if lower.contains("week") || lower.contains("周") { return 7 }
        if lower.contains("today") || lower.contains("tomorrow") || lower.contains("今天") || lower.contains("明天") { return 1 }
        return 3
    }

    /// Same question, reworded for Apple's safety filter, as plain text (no structured format).
    private func gentleRetry(_ q: String) async throws -> String {
        startSession()
        guard let session else { return "" }
        let prompt = """
        Please answer as a supportive general-wellness coach for a healthy adult. Keep advice safe and gradual: \
        balanced meals, regular activity, sleep and rest days; no extreme diets or very low calories. Question: \(q)
        """
        return try await session.respond(to: prompt).content
    }

    // MARK: Weight-goal plan (worked out by the app, tips from the AI)

    /// A target weight in kg mentioned in the question ("55kg", "55 公斤"), if any.
    private static func goalWeight(in q: String) -> Double? {
        let re = try! NSRegularExpression(pattern: #"(\d{2,3}(?:[.,]\d{1,2})?)\s*(?:kg|kgs|kilo|公斤|千克)"#, options: .caseInsensitive)
        let ns = q as NSString
        guard let m = re.firstMatch(in: q, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let value = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "."))
        guard let v = value, (30...200).contains(v) else { return nil }
        return v
    }

    private func goalPlan(target: Double, question: String) async -> String? {
        let d = UserDefaults.standard
        let current = WeightLog.loadAll().max { $0.date < $1.date }?.weight ?? d.double(forKey: "userWeight")
        guard current > 0, target < current - 0.2 else { return nil }      // not a weight-loss goal → normal answer
        let heightM = d.double(forKey: "userHeight") / 100
        let goalKcal = d.integer(forKey: "dailyCalorieGoal")
        let savedPace = d.double(forKey: "weeklyWeightGoal")
        let pace = min(max(savedPace > 0 ? savedPace : 0.5, 0.25), 1.0)      // healthy range: 0.25–1 kg a week
        let toLose = current - target
        let weeks = Int((toLose / pace).rounded(.up))
        let cal = Calendar.current
        let finish = cal.date(byAdding: .weekOfYear, value: weeks, to: Date()) ?? Date()
        func dateText(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day().year()) }

        var out: [String] = []
        out.append(String(format: "**Goal: %.1f kg** (now %.1f kg, %.1f kg to lose)", target, current, toLose))

        if heightM > 0 {
            let bmi = target / (heightM * heightM)
            let lowest = 18.5 * heightM * heightM
            if bmi < 18.5 {
                out.append(String(format: "⚠️ %.1f kg would be a BMI of %.1f, below the healthy range for your height (lowest healthy is about %.1f kg). Please talk to a doctor before aiming that low. The plan below stops at a healthy weight.", target, bmi, lowest))
            } else {
                out.append(String(format: "At %.1f kg your BMI would be %.1f, in the healthy range ✓", target, bmi))
            }
        }

        out.append("")
        out.append(String(format: "**Timeline:** about %.2g kg a week → about %d weeks, around **%@**.", pace, weeks, dateText(finish)))
        // Milestones every 4 weeks
        var milestones: [String] = []
        var w = 4
        while w < weeks {
            let kg = current - pace * Double(w)
            if let date = cal.date(byAdding: .weekOfYear, value: w, to: Date()) {
                milestones.append(String(format: "%.1f kg by %@", kg, date.formatted(.dateTime.month(.abbreviated).day())))
            }
            w += 4
        }
        milestones.append(String(format: "%.1f kg by %@", target, finish.formatted(.dateTime.month(.abbreviated).day())))
        out.append("**Milestones:** " + milestones.joined(separator: " · "))

        out.append("")
        let deficit = Int(pace * 7700 / 7)
        if goalKcal > 0 {
            out.append("**Food:** about \(goalKcal.formatted()) kcal a day (your goal), roughly \(deficit) kcal under what you burn. Protein at every meal, plenty of vegetables, fewer sugary drinks and snacks.")
        } else {
            out.append("**Food:** eat about \(deficit) kcal a day less than you burn. Set a daily calorie goal in Profile so I can be exact.")
        }

        await loadEnergyIfNeeded()
        let week = energy.recentWorkouts(days: 7)
        let mins = Int(week.reduce(0) { $0 + $1.minutes }.rounded())
        out.append("**Move each week:** 2–3 strength sessions (30–45 min), 150+ minutes of brisk walking or cardio, about 8,000+ steps a day, and 1–2 rest days. Last 7 days: \(week.count) workout\(week.count == 1 ? "" : "s"), \(mins) min.")
        out.append("**Recover:** 7+ hours of sleep. Weigh yourself at the same time each morning and watch the weekly average, not single days.")

        // Ask the AI only for encouragement and tips around these numbers; skip quietly if it declines.
        if let session {
            let prompt = """
            The user wants to reach \(String(format: "%.1f", target)) kg gradually and healthily over about \(weeks) weeks \
            with balanced meals, regular exercise and good sleep. Using her recent data, give 3 short, practical, \
            encouraging tips to help her stick with it. No extreme diets. Her words: "\(question)"
            """
            if let tips = try? await session.respond(to: prompt).content, !tips.isEmpty {
                out.append("")
                out.append("**Tips for you**")
                out.append(tips)
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: Money questions answered by the app (no AI guessing)

    /// Answers market / "how are my stocks" / one-stock / CD / spending questions with real numbers.
    /// Returns nil when the question is something else.
    private func moneyAnswer(_ q: String) async -> String? {
        let lower = " " + q.lowercased()
        let holdings = finance.stockHoldings.filter { $0.shares > 0.0001 }
        let mySymbols = holdings.map { $0.symbol.uppercased() }
        let isMoneyTopic = topic == .money || topic == .news
        let mentionsStocks = ["stock", "market", "portfolio", "share", "nasdaq", "s&p", "dow", "股", "大盘", "行情", "基金"]
            .contains { lower.contains($0) }
        guard isMoneyTopic || mentionsStocks else { return nil }

        // One of her stocks named in the question
        let words = Set(q.uppercased().split(whereSeparator: { !$0.isLetter && $0 != "." }).map(String.init))
        let named = mySymbols.filter { words.contains($0) || words.contains($0.replacingOccurrences(of: ".TO", with: "")) }
        if let sym = named.first, let h = holdings.first(where: { $0.symbol.uppercased() == sym }) {
            return await stockAnswer(h)
        }
        let todayWords = ["today", "market", "how are my", "how's my", "hows my", "how my", "how is my", "doing", "perform",
                          "moving", "up or down", "price", "right now", "今天", "今日", "行情", "大盘", "涨", "跌", "表现", "怎么样"]
        if todayWords.contains(where: { lower.contains($0) }) && !Self.wantsMoneyOverview(q) {
            return await marketToday()
        }
        guard isMoneyTopic else { return nil }
        let facts = MoneyFacts(finance)
        if [" cd", "cds", "certificate", "matur", "interest", "定期", "存款", "利息", "到期"].contains(where: { lower.contains($0) }) {
            return cdAnswer(facts)
        }
        if ["spend", "spent", "budget", "expense", "花", "支出", "预算", "消费"].contains(where: { lower.contains($0) }) {
            return spendingAnswer(facts)
        }
        return nil
    }

    private func marketToday() async -> String {
        let holdings = finance.stockHoldings.filter { $0.shares > 0.0001 }
        let quotes = await MarketData.quotes(MarketData.indexes.map(\.symbol) + holdings.map(\.symbol))
        guard !quotes.isEmpty else {
            return "I couldn't get prices right now (no internet connection, or Yahoo Finance didn't answer). Try again in a minute."
        }
        var out: [String] = []
        let asOf = MarketData.indexes.compactMap { quotes[$0.symbol]?.time }.max()
        var header = "**Market today**"
        if let asOf {
            header += " (as of \(asOf.formatted(.dateTime.weekday(.abbreviated).hour().minute())))"
            if Date().timeIntervalSince(asOf) > 30 * 60 { header += ". Markets are closed, so these are the last session's moves" }
        }
        out.append(header)
        let idx = MarketData.indexes.compactMap { i -> String? in
            guard let q = quotes[i.symbol] else { return nil }
            return "\(MoneyFormat.arrow(q.changePct)) \(i.name) \(MoneyFormat.signedPct(q.changePct))"
        }
        if !idx.isEmpty { out.append("- " + idx.joined(separator: " · ")) }

        guard !holdings.isEmpty else {
            out.append("")
            out.append("You don't have any stocks in the app yet.")
            return out.joined(separator: "\n")
        }

        struct Move { let symbol: String; let pct: Double; let dollars: Double; let value: Double }
        let moves: [Move] = holdings.compactMap { h in
            guard let q = quotes[h.symbol] else { return nil }
            return Move(symbol: h.symbol, pct: q.changePct, dollars: q.change * h.shares, value: q.price * h.shares)
        }
        out.append("")
        out.append("**Your stocks today**")
        if moves.isEmpty {
            out.append("- Couldn't load prices for your stocks.")
        } else {
            let dayDollars = moves.reduce(0) { $0 + $1.dollars }
            let nowValue = moves.reduce(0) { $0 + $1.value }
            let startValue = nowValue - dayDollars
            let dayPct = startValue > 0 ? dayDollars / startValue * 100 : 0
            out.append("- \(MoneyFormat.arrow(dayDollars)) \(dayDollars >= 0 ? "Up" : "Down") \(MoneyFormat.usd(dayDollars, cents: abs(dayDollars) < 100)) (\(MoneyFormat.signedPct(dayPct))) today · worth \(MoneyFormat.usd(nowValue))")
            if let sp = quotes["^GSPC"] {
                let diff = dayPct - sp.changePct
                if abs(diff) >= 0.1 {
                    out.append("- \(diff > 0 ? "Doing better" : "Doing worse") than the S&P 500 by \(String(format: "%.2f", abs(diff))) points")
                } else {
                    out.append("- About the same as the S&P 500")
                }
            }
            for m in moves.sorted(by: { abs($0.pct) > abs($1.pct) }).prefix(8) {
                out.append("- \(MoneyFormat.arrow(m.pct)) \(m.symbol) \(MoneyFormat.signedPct(m.pct)) (\(MoneyFormat.signedUSD(m.dollars)))")
            }
            if moves.count < holdings.count { out.append("- \(holdings.count - moves.count) more couldn't be loaded") }

            // Headlines for the biggest movers
            let movers = moves.sorted { abs($0.pct) > abs($1.pct) }.prefix(3).map(\.symbol)
            let news = await StockNews.fetch(symbols: Array(movers))
            if !news.isEmpty {
                out.append("")
                out.append("**In the news**")
                for h in news.prefix(4) {
                    let title = h.title.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
                    out.append(h.url != nil ? "- \(h.symbol): [\(title)](\(h.id))" : "- \(h.symbol): \(title)")
                }
            }
        }
        out.append("")
        out.append("_Prices from Yahoo Finance, may be delayed. Not financial advice._")
        return out.joined(separator: "\n")
    }

    private func stockAnswer(_ h: StockHolding) async -> String {
        async let quoteTask = MarketData.quote(h.symbol)
        async let newsTask = StockNews.fetch(symbols: [h.symbol])
        let (q, news) = await (quoteTask, newsTask)
        let facts = MoneyFacts(finance)
        let price = q?.price ?? h.currentPrice
        let value = price * h.shares
        let gain = value - h.totalCost
        let gainPct = h.totalCost > 0 ? gain / h.totalCost * 100 : 0
        let share = facts.stocksTotal > 0 ? value / facts.stocksTotal * 100 : 0
        var out = ["**\(h.symbol)**\(h.name.isEmpty || h.name == h.symbol ? "" : " · \(h.name)")"]
        if let q {
            out.append("- Today: \(MoneyFormat.arrow(q.changePct)) \(MoneyFormat.signedPct(q.changePct)) at \(MoneyFormat.usd(q.price, cents: true)) (\(MoneyFormat.signedUSD(q.change * h.shares)) for your shares)")
        }
        out.append("- You own \(h.shares.formatted(.number.precision(.fractionLength(0...4)))) shares worth \(MoneyFormat.usd(value)), \(String(format: "%.0f%%", share)) of your stocks")
        out.append("- Since you bought (avg \(MoneyFormat.usd(h.avgBuyPrice, cents: true))): \(gain >= 0 ? "up" : "down") \(MoneyFormat.usd(gain, cents: abs(gain) < 100)) (\(MoneyFormat.signedPct(gainPct)))")
        if !news.isEmpty {
            out.append("")
            out.append("**Recent news**")
            for n in news.prefix(4) {
                let title = n.title.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
                out.append("- [\(title)](\(n.id)) · \(n.publisher), \(n.date.formatted(.dateTime.month(.abbreviated).day()))")
            }
        }
        out.append("")
        out.append("_Prices from Yahoo Finance, may be delayed. Not financial advice._")
        return out.joined(separator: "\n")
    }

    private func cdAnswer(_ f: MoneyFacts) -> String {
        guard !f.cds.isEmpty else { return "You don't have any CDs in the app yet." }
        let avg = f.cdsTotal > 0 ? f.cds.reduce(0) { $0 + $1.annualRate * $1.principal } / f.cdsTotal : 0
        var out = ["**Your CDs**: \(f.cds.count) totalling \(MoneyFormat.usd(f.cdsTotal)), average \(String(format: "%.2f%%", avg))"]
        let cal = Calendar.current
        for cd in f.cds {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: cd.maturityDate)).day ?? 0
            let when = days > 0 ? "in \(days) days" : (days == 0 ? "today" : "matured")
            out.append("- \(cd.bankName.isEmpty ? "CD" : cd.bankName): \(MoneyFormat.usd(cd.principal)) at \(String(format: "%.2f%%", cd.annualRate)), matures \(cd.maturityDate.formatted(.dateTime.month(.abbreviated).day().year())) (\(when)), interest about \(MoneyFormat.usd(cd.estimatedInterest))")
        }
        return out.joined(separator: "\n")
    }

    private func spendingAnswer(_ f: MoneyFacts) -> String {
        guard f.hasTransactions else {
            return "You haven't recorded any spending this month yet, so there's nothing to look at. Add transactions in the Finance tab and ask again."
        }
        var out = ["**This month**: spent \(MoneyFormat.usd(f.spent))"
                   + (f.budget > 0 ? " of your \(MoneyFormat.usd(f.budget)) budget (\(String(format: "%.0f%%", f.spent / f.budget * 100)))" : "")
                   + (f.income > 0 ? ", income \(MoneyFormat.usd(f.income))" : "")]
        for (cat, amount) in f.topCategories.prefix(6) {
            out.append("- \(cat): \(MoneyFormat.usd(amount))")
        }
        return out.joined(separator: "\n")
    }

    private static func wantsMoneyOverview(_ q: String) -> Bool {
        let lower = q.lowercased()
        return (AITopic.money.opener.map { q == $0 } ?? false)
            || ["overview", "snapshot", "diversif", "balanced", "summary", "分散", "总结", "概况"].contains { lower.contains($0) }
    }

    /// The app writes the numbers; the AI adds a few observations based only on those facts.
    private func moneyOverview(request: String, session: LanguageModelSession) async throws -> String {
        let facts = MoneyFacts(finance)
        var out = [facts.overview]
        let prompt = """
        Using ONLY these facts, write 3 short bullet-point observations about how her money is spread out \
        (concentration, mix of stocks and CDs, CD timing, spending if recorded). Quote the percentages exactly as given; \
        don't add or calculate numbers. No buy or sell advice. Facts:
        \(facts.factLines.joined(separator: "\n"))
        Her question: "\(request)"
        """
        if let notes = try? await session.respond(to: prompt).content, !notes.isEmpty {
            out.append("")
            out.append("**Things to think about**")
            out.append(notes)
        }
        return out.joined(separator: "\n")
    }

    private static func wantsTrainingPlan(_ q: String) -> Bool {
        let lower = q.lowercased()
        return ["plan", "week", "schedule", "计划", "这周", "一周", "安排"].contains { lower.contains($0) }
    }

    private func trainingPlan(request: String, session: LanguageModelSession) async throws -> String {
        let prompt = """
        Make a 7-day exercise and rest plan starting today, one entry per day (exactly 7). \
        Decide today's intensity from her recovery data first. Include 1–2 rest days, no more than two hard days \
        in a row, and 2–3 strength sessions. Consider the workouts she already did in the last few days. \
        The user asked: "\(request)"
        """
        let plan = try await session.respond(to: prompt, generating: TrainingPlan.self).content

        let cal = Calendar.current
        var out = ["**Today:** \(plan.today)", ""]
        var total = 0
        for (i, day) in plan.days.prefix(7).enumerated() {
            let date = cal.date(byAdding: .day, value: i, to: Date()) ?? Date()
            let label = i == 0 ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).day())
            let level = day.intensity.lowercased()
            let mark: String
            switch level {
            case "rest": mark = "💤"
            case "easy": mark = "🟢"
            case "moderate": mark = "🟡"
            default: mark = "🔴"
            }
            let mins = level == "rest" ? "" : " · \(day.minutes) min"
            total += level == "rest" ? 0 : day.minutes
            out.append("\(mark) **\(label)**: \(day.activity)\(mins) (\(level)). \(day.why)")
        }
        out.append("")
        out.append("About \(total) minutes of exercise this week.")
        if !plan.tip.isEmpty { out.append("Tip: \(plan.tip)") }
        out.append("💤 rest · 🟢 easy · 🟡 moderate · 🔴 hard")
        return out.joined(separator: "\n")
    }

    private func mealPlan(days: Int, request: String, session: LanguageModelSession) async throws -> String {
        let goal = max(UserDefaults.standard.integer(forKey: "dailyCalorieGoal"), 1200)
        let b = goal * 25 / 100, l = goal * 35 / 100, d = goal * 30 / 100, s = goal - b - l - d
        let prompt = """
        Make a meal plan for exactly \(days) day\(days == 1 ? "" : "s") for weight loss. \
        Each day: breakfast about \(b) kcal, lunch about \(l) kcal, dinner about \(d) kcal, snack about \(s) kcal \
        (about \(goal) kcal in total). Use varied, common healthy dishes; Chinese, Asian and Western home cooking are all good. \
        Lunch and dinner should include lean protein and vegetables. Never repeat a dish anywhere in the plan. \
        Use at most one of the user's saved recipes in the whole plan, and only if it fits the calories. \
        The user asked: "\(request)"
        """
        let plan = try await session.respond(to: prompt, generating: MealPlan.self).content

        // Build the text ourselves so totals are always added up correctly.
        let cal = Calendar.current
        var out: [String] = []
        for (i, day) in plan.days.prefix(days).enumerated() {
            let date = cal.date(byAdding: .day, value: i, to: Date()) ?? Date()
            let label = days == 1 && i == 0 ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let meals: [(String, PlannedMeal)] = [("Breakfast", day.breakfast), ("Lunch", day.lunch),
                                                   ("Dinner", day.dinner), ("Snack", day.snack)]
            let total = meals.reduce(0) { $0 + $1.1.calories }
            out.append("**\(label)** · about \(total.formatted()) kcal")
            for (name, meal) in meals { out.append("- \(name): \(meal.name) (\(meal.calories) kcal)") }
            out.append("")
        }
        if !plan.tip.isEmpty { out.append("Tip: \(plan.tip)") }
        out.append("Daily goal: \(goal.formatted()) kcal.")
        return out.joined(separator: "\n")
    }

    private func startSession() {
        let text = instructions
        let s = LanguageModelSession { text }
        s.prewarm()
        session = s
    }

    private func loadEnergyIfNeeded() async {
        guard !energyLoaded else { return }
        await energy.load()
        energyLoaded = true
    }

    private func buildInstructions(for topic: AITopic) async -> String {
        var data: [String] = (topic == .money || topic == .news) ? [] : [AIContext.profile()]
        var role = ""
        switch topic {
        case .recipes:
            role = """
            You help with healthy, practical meals for weight loss. Suggest a wide variety of common home-cooked dishes \
            (Chinese, Asian and Western are all good) with lean protein, vegetables and whole grains. \
            The user's saved recipes are optional inspiration only: mention one when it really fits, but never build \
            everything around them and never repeat the same dish. A full day should reach the daily calorie goal, \
            not fall far below it. Estimate calories roughly and suggest simple swaps to make dishes lighter.
            """
            data += [AIContext.recipes(), AIContext.meals()]
        case .weight:
            role = """
            You are a supportive weight-loss coach. Look at the trend, not single days (water and salt cause daily swings). \
            Healthy loss is about 0.25–1 kg per week. Connect weight with calories eaten when the data allows. \
            Never recommend eating below 1,200 kcal a day or extreme diets.
            """
            data += [AIContext.weight(), AIContext.meals()]
        case .health:
            await loadEnergyIfNeeded()
            role = """
            You are a sleep and recovery coach. Explain patterns in sleep, HRV (higher is better for recovery), \
            resting heart rate (lower is better) and energy. Give practical habits (bedtime, light, caffeine, exercise timing). \
            Don't diagnose; suggest seeing a doctor if something looks unusual for a long time.
            """
            data += [AIContext.health(energy), AIContext.workouts(energy, days: 7)]
        case .training:
            await loadEnergyIfNeeded()
            role = """
            You are a friendly fitness coach focused on weight loss and recovery. Base advice on her readiness, \
            HRV, sleep, resting heart rate and recent workouts. Rules: if readiness or energy is under 60, sleep was \
            under 6 hours, or HRV is well below normal, recommend rest or easy movement today. Never plan more than \
            two hard days in a row; include 1–2 rest days a week; after a hard day, go easy. For weight loss, mix \
            2–3 strength sessions with walking or cardio. Keep it realistic for a busy person.
            """
            data += [AIContext.recoveryToday(energy), AIContext.workouts(energy), AIContext.health(energy)]
        case .money:
            role = """
            You explain personal finance in plain language: diversification, concentration risk, emergency savings, \
            CDs, budgeting and long-term investing. Only talk about money. Use ONLY the facts and percentages below; \
            never calculate new numbers and never guess. If something isn't in the facts (like spending), say it isn't \
            recorded. Never tell the user to buy or sell a specific stock and never predict prices. You don't know market news.
            """
            data += [AIContext.money(finance)]
        case .news:
            let symbols = finance.stockHoldings.filter { $0.shares > 0.0001 }.map(\.symbol)
            headlines = await StockNews.fetch(symbols: symbols)
            role = """
            You summarise recent news headlines about the stocks the user owns, grouped by stock, in plain language. \
            Use only the headlines provided; don't invent details, numbers or events that aren't in them. \
            Point out which stories may matter most (earnings, lawsuits, product launches, big price moves, analyst changes) \
            and suggest reading the full article for those. Never tell the user to buy or sell, and never predict prices.
            """
            data += [AIContext.stockList(finance), AIContext.headlines(headlines)]
        case .chat:
            await loadEnergyIfNeeded()
            role = "You are a friendly life assistant for health, food, habits and money. Use the user's data when it helps."
            data += [AIContext.weight(), AIContext.health(energy), AIContext.workouts(energy, days: 7), AIContext.money(finance)]
        }
        return """
        You are Kelly AI, a warm, encouraging assistant inside the user's personal app. \(role)
        Rules: Be specific and use the numbers below. Keep answers under 180 words. Use short bullet points. \
        If data is missing, say so briefly and still help. Reply in the same language the user writes in (English or Chinese).
        Today is \(Date().formatted(date: .complete, time: .omitted)).

        \(data.joined(separator: "\n\n"))
        """
    }
}

// MARK: - Today card

struct AIAssistantCard: View {
    @ObservedObject var financeStore: FinanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.pink)
                Text("Ask Kelly AI").font(.headline)
                Spacer()
                Text("On-device").font(.caption2).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach([AITopic.recipes, .weight, .health, .training, .money, .news]) { topic in
                    NavigationLink {
                        AIAssistantView(financeStore: financeStore, startTopic: topic)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: topic.icon).foregroundStyle(topic.color)
                            Text(topic.title).font(.subheadline).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(topic.color.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            NavigationLink {
                AIAssistantView(financeStore: financeStore, startTopic: .chat)
            } label: {
                HStack {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                    Text("Ask anything…").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .padding(12)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Chat screen

struct AIAssistantView: View {
    @StateObject private var ai: KellyAI
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    private let startTopic: AITopic

    init(financeStore: FinanceStore, startTopic: AITopic) {
        _ai = StateObject(wrappedValue: KellyAI(finance: financeStore))
        self.startTopic = startTopic
    }

    var body: some View {
        VStack(spacing: 0) {
            topicBar
            Divider()
            if let reason = ai.unavailableReason {
                ContentUnavailableView("Apple Intelligence needed", systemImage: "sparkles", description: Text(reason))
            } else {
                conversation
                inputBar
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Kelly AI")
        .navigationBarTitleDisplayMode(.inline)
        .task { await ai.open(startTopic) }
    }

    private var topicBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AITopic.allCases) { t in
                    Button {
                        Task { await ai.open(t) }
                    } label: {
                        Label(t.shortTitle, systemImage: t.icon)
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(ai.topic == t ? t.color : Color(.tertiarySystemFill))
                            .foregroundStyle(ai.topic == t ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(ai.isThinking || ai.isPreparing)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ai.topic.disclaimer)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    if ai.isPreparing {
                        HStack(spacing: 8) { ProgressView(); Text("Reading your data…").foregroundStyle(.secondary) }
                    }

                    ForEach(ai.messages) { m in bubble(m).id(m.id) }

                    if ai.topic == .news && !ai.headlines.isEmpty && !ai.isPreparing {
                        headlineList
                    }

                    if ai.isThinking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }

                    if !ai.isThinking && !ai.isPreparing {
                        FlowLayout(spacing: 8) {
                            ForEach(ai.topic.suggestions, id: \.self) { s in
                                Button { Task { await ai.ask(s) } } label: {
                                    Text(s).font(.footnote)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(ai.topic.color.opacity(0.12))
                                        .foregroundStyle(ai.topic.color)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .onChange(of: ai.messages) { _, msgs in
                if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: ai.isThinking) { _, thinking in
                if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private var headlineList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Headlines").font(.subheadline).fontWeight(.semibold)
            ForEach(ai.headlines) { h in
                if let url = h.url {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(h.symbol)
                                    .font(.caption2).fontWeight(.bold)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.teal.opacity(0.15))
                                    .foregroundStyle(.teal)
                                    .clipShape(Capsule())
                                Text("\(h.publisher) · \(h.date.formatted(.relative(presentation: .named)))")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(h.title).font(.footnote).foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func bubble(_ m: AIMessage) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(m.text)
                    .padding(12)
                    .background(ai.topic.color)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(ai.topic.color).padding(.top, 4)
                Text(markdown(m.text))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        case .notice:
            Text(m.text).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about \(ai.topic.shortTitle.lowercased())…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                    .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty || ai.isThinking ? Color.secondary : ai.topic.color)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || ai.isThinking)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let q = input
        input = ""
        Task { await ai.ask(q) }
    }

    /// Shows **bold**, *italic* and keeps line breaks / bullet points.
    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
