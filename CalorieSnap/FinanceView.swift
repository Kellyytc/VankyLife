import SwiftUI
import Combine
import UserNotifications

// MARK: - Models

struct Transaction: Identifiable, Codable {
    var id = UUID()
    var title: String
    var amount: Double
    var type: TransactionType
    var category: TransactionCategory
    var date: Date
    var note: String
    var emoji: String
}

enum TransactionType: String, Codable, CaseIterable {
    case income = "Income"
    case expense = "Expense"
}

enum TransactionCategory: String, Codable, CaseIterable {
    case food = "Food"
    case grocery = "Grocery"
    case transport = "Transport"
    case shopping = "Shopping"
    case health = "Health"
    case entertainment = "Entertainment"
    case bills = "Bills"
    case salary = "Salary"
    case investment = "Investment"
    case rent = "Rent"
    case education = "Education"
    case travel = "Travel"
    case other = "Other"

    var emoji: String {
        switch self {
        case .food: return "🍜"
        case .grocery: return "🛒"
        case .transport: return "🚇"
        case .shopping: return "🛍️"
        case .health: return "💊"
        case .entertainment: return "🎮"
        case .bills: return "📱"
        case .salary: return "💰"
        case .investment: return "📈"
        case .rent: return "🏠"
        case .education: return "📚"
        case .travel: return "✈️"
        case .other: return "📦"
        }
    }
    var isIncomeType: Bool {
        switch self {
        case .salary, .investment: return true
        default: return false
        }
    }
}

struct BudgetGoal: Codable {
    var category: TransactionCategory
    var monthlyLimit: Double
}

// MARK: - Stock Models

struct PricePoint: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var price: Double
}

struct StockHolding: Identifiable, Codable {
    var id = UUID()
    var symbol: String
    var name: String
    var shares: Double
    var avgBuyPrice: Double
    var currentPrice: Double
    var priceHistory: [PricePoint]
    var lastUpdated: Date

    init(
        id: UUID = UUID(), symbol: String, name: String,
        shares: Double, avgBuyPrice: Double, currentPrice: Double,
        priceHistory: [PricePoint] = [], lastUpdated: Date = Date()
    ) {
        self.id = id; self.symbol = symbol; self.name = name
        self.shares = shares; self.avgBuyPrice = avgBuyPrice
        self.currentPrice = currentPrice
        self.priceHistory = priceHistory; self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        symbol = try c.decode(String.self, forKey: .symbol)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? symbol
        shares = try c.decode(Double.self, forKey: .shares)
        avgBuyPrice = try c.decode(Double.self, forKey: .avgBuyPrice)
        currentPrice = try c.decode(Double.self, forKey: .currentPrice)
        priceHistory = try c.decodeIfPresent([PricePoint].self, forKey: .priceHistory) ?? []
        lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, symbol, name, shares, avgBuyPrice, currentPrice, priceHistory, lastUpdated
    }

    var totalCost: Double { shares * avgBuyPrice }
    var totalValue: Double { shares * currentPrice }
    var gainLoss: Double { totalValue - totalCost }
    var gainLossPercent: Double {
        totalCost > 0 ? (gainLoss / totalCost) * 100 : 0
    }
}

struct StockTransaction: Identifiable, Codable {
    var id = UUID()
    var symbol: String
    var type: StockTransactionType
    var shares: Double
    var price: Double
    var amountInvested: Double
    var date: Date
    var note: String
    var total: Double { shares * price }

    init(
        id: UUID = UUID(), symbol: String, type: StockTransactionType,
        shares: Double, price: Double, amountInvested: Double, date: Date, note: String
    ) {
        self.id = id; self.symbol = symbol; self.type = type
        self.shares = shares; self.price = price
        self.amountInvested = amountInvested; self.date = date; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        symbol = try c.decode(String.self, forKey: .symbol)
        type = try c.decode(StockTransactionType.self, forKey: .type)
        shares = try c.decode(Double.self, forKey: .shares)
        price = try c.decode(Double.self, forKey: .price)
        amountInvested = try c.decodeIfPresent(Double.self, forKey: .amountInvested) ?? (shares * price)
        date = try c.decode(Date.self, forKey: .date)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, symbol, type, shares, price, amountInvested, date, note
    }
}

enum StockTransactionType: String, Codable, CaseIterable {
    case buy = "Buy"; case sell = "Sell"
}

// MARK: - CD Model

struct CDAccount: Identifiable, Codable {
    var id = UUID()
    var bankName: String
    var principal: Double
    var annualRate: Double
    var startDate: Date
    var maturityDate: Date
    var notificationID: String

    init(
        id: UUID = UUID(), bankName: String, principal: Double,
        annualRate: Double, startDate: Date, maturityDate: Date
    ) {
        self.id = id; self.bankName = bankName; self.principal = principal
        self.annualRate = annualRate; self.startDate = startDate
        self.maturityDate = maturityDate; self.notificationID = id.uuidString
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bankName = try c.decode(String.self, forKey: .bankName)
        principal = try c.decode(Double.self, forKey: .principal)
        annualRate = try c.decode(Double.self, forKey: .annualRate)
        startDate = try c.decode(Date.self, forKey: .startDate)
        maturityDate = try c.decode(Date.self, forKey: .maturityDate)
        notificationID = try c.decodeIfPresent(String.self, forKey: .notificationID) ?? id.uuidString
    }

    enum CodingKeys: String, CodingKey {
        case id, bankName, principal, annualRate, startDate, maturityDate, notificationID
    }

    var termDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: maturityDate).day ?? 0
    }
    var estimatedInterest: Double {
        principal * (annualRate / 100) * (Double(termDays) / 365)
    }
    var estimatedTotal: Double { principal + estimatedInterest }
    var daysUntilMaturity: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: maturityDate).day ?? 0
    }
    var isMatured: Bool { daysUntilMaturity <= 0 }
    var statusColor: Color {
        if isMatured { return .green }
        if daysUntilMaturity <= 7 { return .orange }
        if daysUntilMaturity <= 30 { return .yellow }
        return .blue
    }
    var statusText: String {
        if isMatured { return "Matured — removing shortly" }
        if daysUntilMaturity <= 1 { return "Matures tomorrow!" }
        return "\(daysUntilMaturity) days left"
    }
}

// MARK: - Yahoo Finance Fetcher

class StockPriceFetcher: ObservableObject {
    @Published var fetchingSymbols: Set<String> = []
    @Published var lastFetchTime: Date? = nil
    @Published var fetchErrors: [String: String] = [:]

    // Fetch price for a single symbol from Yahoo Finance (no API key needed)
    func fetchPrice(symbol: String, completion: @escaping (Double?) -> Void) {
        let sym = symbol.uppercased()
        let urlString = "https://query1.finance.yahoo.com/v8/finance/chart/\(sym)?interval=1m&range=1d"
        guard let url = URL(string: urlString) else { completion(nil); return }

        DispatchQueue.main.async { self.fetchingSymbols.insert(sym) }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { self.fetchingSymbols.remove(sym) }

            guard let data = data, error == nil else {
                DispatchQueue.main.async { self.fetchErrors[sym] = "Network error" }
                completion(nil); return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let chart = json["chart"] as? [String: Any],
                   let result = (chart["result"] as? [[String: Any]])?.first,
                   let meta = result["meta"] as? [String: Any] {

                    // Try regularMarketPrice first, then previousClose
                    let price = meta["regularMarketPrice"] as? Double
                        ?? meta["chartPreviousClose"] as? Double

                    DispatchQueue.main.async {
                        self.lastFetchTime = Date()
                        self.fetchErrors.removeValue(forKey: sym)
                    }
                    completion(price)
                } else {
                    DispatchQueue.main.async {
                        self.fetchErrors[sym] = "Invalid response"
                    }
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async { self.fetchErrors[sym] = "Parse error" }
                completion(nil)
            }
        }.resume()
    }

    // Fetch prices for all symbols
    func fetchAllPrices(symbols: [String], completion: @escaping ([String: Double]) -> Void) {
        var results: [String: Double] = [:]
        let group = DispatchGroup()

        for symbol in symbols {
            group.enter()
            fetchPrice(symbol: symbol) { price in
                if let p = price { results[symbol.uppercased()] = p }
                group.leave()
            }
        }

        group.notify(queue: .main) { completion(results) }
    }
}

// MARK: - Finance Store

class FinanceStore: ObservableObject {
    @Published var transactions: [Transaction] = [] { didSet { save() } }
    @Published var budgetGoals: [TransactionCategory: Double] = [:] { didSet { saveBudgets() } }
    @Published var overallMonthlyBudget: Double = 0 { didSet { saveOverallBudget() } }
    @Published var stockTransactions: [StockTransaction] = [] {
        didSet { saveStockTx(); rebuildHoldings() }
    }
    @Published var stockHoldings: [StockHolding] = []
    @Published var cdAccounts: [CDAccount] = [] { didSet { saveCDs() } }
    @Published var previousDayStockValue: Double = 0
    @Published var isRefreshing = false
    @Published var isFetchingPrices = false
    @Published var lastPriceFetchTime: Date? = nil
    @Published var manualPrices: [String: Double] = [:] {
        didSet { savePrices(); rebuildHoldings() }
    }
    @Published var priceHistories: [String: [PricePoint]] = [:] {
        didSet { savePriceHistory() }
    }
    @Published var fridayClosePrices: [String: Double] = [:] {
        didSet { saveFridayPrices() }
    }

    let fetcher = StockPriceFetcher()
    private var priceTimer: Timer?
    private var autoFetchTimer: Timer?

    init() {
        load(); loadBudgets(); loadOverallBudget()
        loadStockTx(); loadPrices(); loadPriceHistory()
        loadFridayPrices(); loadCDs()
        rebuildHoldings()
        loadStockSnapshot()
        schedulePriceTimer()
        scheduleAutoFetch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.removeMaturedCDs()
            // Auto-fetch on launch
            self.fetchAllPricesFromYahoo()
        }
    }

    deinit { priceTimer?.invalidate(); autoFetchTimer?.invalidate() }

    // MARK: - Yahoo Finance auto-fetch

    func scheduleAutoFetch() {
        autoFetchTimer?.invalidate()
        // Fetch every 5 minutes during market hours
        autoFetchTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.fetchAllPricesFromYahoo()
        }
    }

    func fetchAllPricesFromYahoo() {
        let symbols = Array(Set(stockTransactions.map { $0.symbol.uppercased() }))
        guard !symbols.isEmpty else { return }
        isFetchingPrices = true

        fetcher.fetchAllPrices(symbols: symbols) { [weak self] results in
            guard let self = self else { return }
            self.isFetchingPrices = false
            self.lastPriceFetchTime = Date()

            for (sym, price) in results {
                var prices = self.manualPrices
                prices[sym] = price
                self.manualPrices = prices

                var histories = self.priceHistories
                var history = histories[sym] ?? []
                history.append(PricePoint(date: Date(), price: price))
                if history.count > 500 { history.removeFirst(history.count - 500) }
                histories[sym] = history
                self.priceHistories = histories

                self.saveFridayCloseIfNeeded(symbol: sym, price: price)
            }
            self.rebuildHoldings()
        }
    }

    func fetchSinglePrice(symbol: String) {
        let sym = symbol.uppercased()
        fetcher.fetchPrice(symbol: sym) { [weak self] price in
            guard let self = self, let price = price else { return }
            self.updatePrice(symbol: sym, price: price)
        }
    }

    // MARK: - Rebuild holdings

    func rebuildHoldings() {
        var symbolData: [String: (shares: Double, totalCost: Double)] = [:]
        let sorted = stockTransactions.sorted { $0.date < $1.date }
        for tx in sorted {
            let sym = tx.symbol.uppercased()
            switch tx.type {
            case .buy:
                let newShares = tx.amountInvested / tx.price
                if var d = symbolData[sym] {
                    d.totalCost += tx.amountInvested; d.shares += newShares
                    symbolData[sym] = d
                } else {
                    symbolData[sym] = (shares: newShares, totalCost: tx.amountInvested)
                }
            case .sell:
                if var d = symbolData[sym] {
                    let sharesToSell = tx.amountInvested / tx.price
                    let ratio = sharesToSell / d.shares
                    d.totalCost -= d.totalCost * min(ratio, 1.0)
                    d.shares -= sharesToSell
                    if d.shares < 0.0001 { symbolData.removeValue(forKey: sym) }
                    else { symbolData[sym] = d }
                }
            }
        }
        var newHoldings: [StockHolding] = []
        for (sym, data) in symbolData {
            let avgBuy = data.shares > 0 ? data.totalCost / data.shares : 0
            let currentPrice = manualPrices[sym] ?? avgBuy
            let history = priceHistories[sym] ?? []
            newHoldings.append(StockHolding(
                symbol: sym, name: sym, shares: data.shares,
                avgBuyPrice: avgBuy, currentPrice: currentPrice, priceHistory: history
            ))
        }
        stockHoldings = newHoldings.sorted { $0.symbol < $1.symbol }
    }

    // MARK: - Price management

    func updatePrice(symbol: String, price: Double) {
        let sym = symbol.uppercased()
        var prices = manualPrices; prices[sym] = price; manualPrices = prices
        var histories = priceHistories
        var history = histories[sym] ?? []
        history.append(PricePoint(date: Date(), price: price))
        if history.count > 500 { history.removeFirst(history.count - 500) }
        histories[sym] = history; priceHistories = histories
        saveFridayCloseIfNeeded(symbol: sym, price: price)
    }

    func saveFridayCloseIfNeeded(symbol: String, price: Double) {
        let weekday = Calendar.current.component(.weekday, from: Date())
        if weekday == 6 {
            var friday = fridayClosePrices
            friday[symbol] = price
            fridayClosePrices = friday
        }
    }

    func setFridayClose(symbol: String, price: Double) {
        var friday = fridayClosePrices
        friday[symbol.uppercased()] = price
        fridayClosePrices = friday
    }

    func addStockTransaction(_ tx: StockTransaction) {
        stockTransactions.append(tx)
        let sym = tx.symbol.uppercased()
        var histories = priceHistories
        var history = histories[sym] ?? []
        history.append(PricePoint(date: tx.date, price: tx.price))
        histories[sym] = history; priceHistories = histories
        if manualPrices[sym] == nil {
            var prices = manualPrices; prices[sym] = tx.price; manualPrices = prices
        }
        // Immediately fetch live price for new symbol
        fetchSinglePrice(symbol: sym)
    }

    func deleteSymbol(_ symbol: String) {
        let sym = symbol.uppercased()
        stockTransactions.removeAll { $0.symbol == sym }
        var prices = manualPrices; prices.removeValue(forKey: sym); manualPrices = prices
        var histories = priceHistories; histories.removeValue(forKey: sym); priceHistories = histories
        var friday = fridayClosePrices; friday.removeValue(forKey: sym); fridayClosePrices = friday
    }

    func renameSymbol(from oldSym: String, to newSym: String) {
        let old = oldSym.uppercased()
        let new = newSym.uppercased().trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != old else { return }
        for i in stockTransactions.indices {
            if stockTransactions[i].symbol == old { stockTransactions[i].symbol = new }
        }
        var histories = priceHistories
        if let h = histories[old] { histories[new] = h; histories.removeValue(forKey: old) }
        priceHistories = histories
        var prices = manualPrices
        if let p = prices[old] { prices[new] = p; prices.removeValue(forKey: old) }
        manualPrices = prices
        var friday = fridayClosePrices
        if let p = friday[old] { friday[new] = p; friday.removeValue(forKey: old) }
        fridayClosePrices = friday
        // Fetch live price for new symbol
        fetchSinglePrice(symbol: new)
    }

    // MARK: - Price timer (snapshot every 60s)

    func schedulePriceTimer() {
        priceTimer?.invalidate()
        priceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.recordPriceSnapshot()
        }
    }

    func recordPriceSnapshot() {
        var histories = priceHistories
        for holding in stockHoldings {
            var history = histories[holding.symbol] ?? []
            history.append(PricePoint(date: Date(), price: holding.currentPrice))
            if history.count > 500 { history.removeFirst(history.count - 500) }
            histories[holding.symbol] = history
        }
        priceHistories = histories
        let weekday = Calendar.current.component(.weekday, from: Date())
        if weekday == 6 {
            var friday = fridayClosePrices
            for holding in stockHoldings { friday[holding.symbol] = holding.currentPrice }
            fridayClosePrices = friday
        }
    }

    func refreshAll() {
        isRefreshing = true
        recordPriceSnapshot()
        fetchAllPricesFromYahoo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.rebuildHoldings()
            self.isRefreshing = false
        }
    }

    func removeMaturedCDs() { cdAccounts.removeAll { $0.isMatured } }

    // MARK: - Market status

    var isWeekend: Bool {
        let w = Calendar.current.component(.weekday, from: Date())
        return w == 1 || w == 7
    }
    var isMarketOpen: Bool {
        if isWeekend { return false }
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 9 && h < 16
    }
    var marketStatusText: String {
        if isWeekend { return "Weekend — vs last Friday close" }
        return isMarketOpen ? "Market open — live prices" : "After hours"
    }
    var marketStatusColor: Color {
        if isWeekend { return .orange }
        return isMarketOpen ? .green : .orange
    }

    // MARK: - Friday portfolio value

    var lastFridayPortfolioValue: Double {
        var total: Double = 0
        for holding in stockHoldings {
            if let fp = fridayClosePrices[holding.symbol] {
                total += fp * holding.shares
            } else {
                let cal = Calendar.current; let today = Date()
                var fridayDate: Date? = nil
                for i in 1...7 {
                    if let d = cal.date(byAdding: .day, value: -i, to: today),
                       cal.component(.weekday, from: d) == 6 {
                        fridayDate = d; break
                    }
                }
                if let friday = fridayDate,
                   let fridayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: friday) {
                    let history = priceHistories[holding.symbol] ?? []
                    let pts = history.filter { $0.date <= fridayEnd }
                    if let last = pts.sorted(by: { $0.date < $1.date }).last {
                        total += last.price * holding.shares
                    } else { total += holding.totalCost }
                } else { total += holding.totalCost }
            }
        }
        return total
    }

    var hasFridayCloseData: Bool {
        guard !stockHoldings.isEmpty else { return false }
        return stockHoldings.allSatisfy { fridayClosePrices[$0.symbol] != nil }
    }

    var todayStockGainLoss: Double {
        isWeekend ? totalStockValue - lastFridayPortfolioValue
                  : totalStockValue - previousDayStockValue
    }
    var todayStockGainLossPercent: Double {
        let base = isWeekend ? lastFridayPortfolioValue : previousDayStockValue
        return base > 0 ? (todayStockGainLoss / base) * 100 : 0
    }

    // MARK: - Persistence

    func save() {
        if let d = try? JSONEncoder().encode(transactions) {
            UserDefaults.standard.set(d, forKey: "financeTransactions")
        }
    }
    func load() {
        guard let d = UserDefaults.standard.data(forKey: "financeTransactions"),
              let decoded = try? JSONDecoder().decode([Transaction].self, from: d) else { return }
        transactions = decoded
    }
    func saveBudgets() {
        let goals = budgetGoals.map { BudgetGoal(category: $0.key, monthlyLimit: $0.value) }
        if let d = try? JSONEncoder().encode(goals) { UserDefaults.standard.set(d, forKey: "financeBudgets") }
    }
    func loadBudgets() {
        guard let d = UserDefaults.standard.data(forKey: "financeBudgets"),
              let goals = try? JSONDecoder().decode([BudgetGoal].self, from: d) else { return }
        budgetGoals = Dictionary(uniqueKeysWithValues: goals.map { ($0.category, $0.monthlyLimit) })
    }
    func saveOverallBudget() { UserDefaults.standard.set(overallMonthlyBudget, forKey: "overallMonthlyBudget") }
    func loadOverallBudget() { overallMonthlyBudget = UserDefaults.standard.double(forKey: "overallMonthlyBudget") }
    func saveStockTx() {
        if let d = try? JSONEncoder().encode(stockTransactions) { UserDefaults.standard.set(d, forKey: "stockTransactions_v2") }
    }
    func loadStockTx() {
        if let d = UserDefaults.standard.data(forKey: "stockTransactions_v2"),
           let decoded = try? JSONDecoder().decode([StockTransaction].self, from: d) { stockTransactions = decoded; return }
        if let d = UserDefaults.standard.data(forKey: "stockTransactions"),
           let decoded = try? JSONDecoder().decode([StockTransaction].self, from: d) { stockTransactions = decoded; saveStockTx() }
    }
    func savePrices() {
        if let d = try? JSONEncoder().encode(manualPrices) { UserDefaults.standard.set(d, forKey: "manualStockPrices") }
    }
    func loadPrices() {
        guard let d = UserDefaults.standard.data(forKey: "manualStockPrices"),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: d) else { return }
        manualPrices = decoded
    }
    func savePriceHistory() {
        if let d = try? JSONEncoder().encode(priceHistories) { UserDefaults.standard.set(d, forKey: "stockPriceHistories") }
    }
    func loadPriceHistory() {
        guard let d = UserDefaults.standard.data(forKey: "stockPriceHistories"),
              let decoded = try? JSONDecoder().decode([String: [PricePoint]].self, from: d) else { return }
        priceHistories = decoded
    }
    func saveFridayPrices() {
        if let d = try? JSONEncoder().encode(fridayClosePrices) { UserDefaults.standard.set(d, forKey: "fridayClosePrices") }
    }
    func loadFridayPrices() {
        guard let d = UserDefaults.standard.data(forKey: "fridayClosePrices"),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: d) else { return }
        fridayClosePrices = decoded
    }
    func saveCDs() {
        if let d = try? JSONEncoder().encode(cdAccounts) { UserDefaults.standard.set(d, forKey: "cdAccounts") }
    }
    func loadCDs() {
        guard let d = UserDefaults.standard.data(forKey: "cdAccounts"),
              let decoded = try? JSONDecoder().decode([CDAccount].self, from: d) else { return }
        cdAccounts = decoded
    }
    func loadStockSnapshot() {
        let saved = UserDefaults.standard.double(forKey: "previousDayStockValue")
        let lastDate = UserDefaults.standard.object(forKey: "stockSnapshotDate") as? Date
        if let date = lastDate {
            if Calendar.current.isDateInToday(date) { previousDayStockValue = saved }
            else {
                previousDayStockValue = saved
                UserDefaults.standard.set(totalStockValue, forKey: "previousDayStockValue")
                UserDefaults.standard.set(Date(), forKey: "stockSnapshotDate")
            }
        } else {
            previousDayStockValue = totalStockValue
            UserDefaults.standard.set(totalStockValue, forKey: "previousDayStockValue")
            UserDefaults.standard.set(Date(), forKey: "stockSnapshotDate")
        }
        recordPriceSnapshot()
    }

    // MARK: - Finance computed

    func transactions(for period: FinancePeriod) -> [Transaction] {
        transactions.filter { period.contains($0.date) }.sorted { $0.date > $1.date }
    }
    func totalIncome(for period: FinancePeriod) -> Double {
        transactions(for: period).filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }
    func totalExpense(for period: FinancePeriod) -> Double {
        transactions(for: period).filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    func balance(for period: FinancePeriod) -> Double { totalIncome(for: period) - totalExpense(for: period) }
    func expenseByCategory(for period: FinancePeriod) -> [(category: TransactionCategory, amount: Double)] {
        let expenses = transactions(for: period).filter { $0.type == .expense }
        var grouped: [TransactionCategory: Double] = [:]
        for t in expenses { grouped[t.category, default: 0] += t.amount }
        return grouped.map { ($0.key, $0.value) }.sorted { $0.amount > $1.amount }
    }
    func averageMonthlySpend(for category: TransactionCategory) -> Double {
        let amounts = (1...6).map { offset -> Double in
            let period = FinancePeriod.monthOffset(-offset)
            return expenseByCategory(for: period).first(where: { $0.category == category })?.amount ?? 0
        }
        let nonZero = amounts.filter { $0 > 0 }
        return nonZero.isEmpty ? 0 : nonZero.reduce(0, +) / Double(nonZero.count)
    }
    func monthlyAmounts(for category: TransactionCategory, months: Int = 6) -> [(month: String, amount: Double)] {
        (0..<months).map { offset -> (String, Double) in
            let period = FinancePeriod.monthOffset(-offset)
            let f = DateFormatter(); f.dateFormat = "MMM"
            let amount = expenseByCategory(for: period).first(where: { $0.category == category })?.amount ?? 0
            return (f.string(from: period.startDate), amount)
        }.reversed()
    }
    func weeklyTotals(weeks: Int = 8) -> [(week: String, income: Double, expense: Double)] {
        (0..<weeks).map { offset -> (String, Double, Double) in
            let period = FinancePeriod.weekOffset(-offset)
            let f = DateFormatter(); f.dateFormat = "M/d"
            return (f.string(from: period.startDate), totalIncome(for: period), totalExpense(for: period))
        }.reversed()
    }
    func monthlyTotals(months: Int = 6) -> [(month: String, income: Double, expense: Double)] {
        (0..<months).map { offset -> (String, Double, Double) in
            let period = FinancePeriod.monthOffset(-offset)
            let f = DateFormatter(); f.dateFormat = "MMM"
            return (f.string(from: period.startDate), totalIncome(for: period), totalExpense(for: period))
        }.reversed()
    }
    var totalMonthlyBudget: Double { overallMonthlyBudget }
    func monthSpent() -> Double { totalExpense(for: .month) }
    func monthBudgetRemaining() -> Double { totalMonthlyBudget - monthSpent() }
    var totalStockValue: Double { stockHoldings.reduce(0) { $0 + $1.totalValue } }
    var totalStockCost: Double { stockHoldings.reduce(0) { $0 + $1.totalCost } }
    var totalStockGainLoss: Double { totalStockValue - totalStockCost }
    var totalStockGainLossPercent: Double {
        totalStockCost > 0 ? (totalStockGainLoss / totalStockCost) * 100 : 0
    }
    func transactionsFor(symbol: String) -> [StockTransaction] {
        stockTransactions.filter { $0.symbol == symbol }.sorted { $0.date < $1.date }
    }
    func scheduleCDNotification(for cd: CDAccount) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [cd.notificationID])
        let content = UNMutableNotificationContent()
        content.title = "💰 CD Maturing Soon!"
        content.body = "\(cd.bankName) CD matures tomorrow! Total: $\(String(format: "%.2f", cd.estimatedTotal))"
        content.sound = .default
        guard let notifyDate = Calendar.current.date(byAdding: .day, value: -1, to: cd.maturityDate),
              notifyDate > Date() else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notifyDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: cd.notificationID, content: content, trigger: trigger)) { _ in }
    }
}

// MARK: - Period

enum FinancePeriod {
    case week, month, year, weekOffset(Int), monthOffset(Int)

    var startDate: Date {
        let cal = Calendar.current; let now = Date()
        switch self {
        case .week: return cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .month: return cal.dateInterval(of: .month, for: now)?.start ?? now
        case .year: return cal.dateInterval(of: .year, for: now)?.start ?? now
        case .weekOffset(let n):
            let d = cal.date(byAdding: .weekOfYear, value: n, to: now) ?? now
            return cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
        case .monthOffset(let n):
            let d = cal.date(byAdding: .month, value: n, to: now) ?? now
            return cal.dateInterval(of: .month, for: d)?.start ?? d
        }
    }
    var endDate: Date {
        let cal = Calendar.current; let now = Date()
        switch self {
        case .week: return cal.dateInterval(of: .weekOfYear, for: now)?.end ?? now
        case .month: return cal.dateInterval(of: .month, for: now)?.end ?? now
        case .year: return cal.dateInterval(of: .year, for: now)?.end ?? now
        case .weekOffset(let n):
            let d = cal.date(byAdding: .weekOfYear, value: n, to: now) ?? now
            return cal.dateInterval(of: .weekOfYear, for: d)?.end ?? d
        case .monthOffset(let n):
            let d = cal.date(byAdding: .month, value: n, to: now) ?? now
            return cal.dateInterval(of: .month, for: d)?.end ?? d
        }
    }
    func contains(_ date: Date) -> Bool { date >= startDate && date < endDate }
}

// MARK: - Finance View

struct FinanceView: View {
    @ObservedObject var store: FinanceStore   // ← injected, not @StateObject
    @State private var selectedPeriod: PeriodTab = .month
    @State private var showAddTransaction = false
    @State private var showBudgetSettings = false
    @State private var selectedTab: FinanceTab = .overview

    enum PeriodTab: String, CaseIterable {
        case week = "Week"; case month = "Month"; case year = "Year"
    }
    enum FinanceTab {
        case overview, transactions, trends, budget, stocks, cd
    }

    var period: FinancePeriod {
        switch selectedPeriod {
        case .week: return .week; case .month: return .month; case .year: return .year
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(PeriodTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal).padding(.top, 8)

                SummaryBanner(store: store, period: period)
                    .padding(.horizontal).padding(.top, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        TabButton(title: "Overview", icon: "chart.pie",
                                  isSelected: selectedTab == .overview) { selectedTab = .overview }
                        TabButton(title: "Records", icon: "list.bullet",
                                  isSelected: selectedTab == .transactions) { selectedTab = .transactions }
                        TabButton(title: "Trends", icon: "chart.line.uptrend.xyaxis",
                                  isSelected: selectedTab == .trends) { selectedTab = .trends }
                        TabButton(title: "Budget", icon: "target",
                                  isSelected: selectedTab == .budget) { selectedTab = .budget }
                        TabButton(title: "Stocks", icon: "chart.bar.fill",
                                  isSelected: selectedTab == .stocks) { selectedTab = .stocks }
                        TabButton(title: "CD", icon: "banknote",
                                  isSelected: selectedTab == .cd) { selectedTab = .cd }
                    }.padding(.horizontal)
                }.padding(.top, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .overview: OverviewTab(store: store, period: period)
                        case .transactions: TransactionsTab(store: store, period: period)
                        case .trends: TrendsTab(store: store)
                        case .budget: BudgetTab(store: store, period: period)
                        case .stocks: StocksTab(store: store)
                        case .cd: CDTab(store: store)
                        }
                    }.padding(.horizontal).padding(.vertical, 12)
                }.refreshable { store.refreshAll() }
            }
            .navigationTitle("Finance")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showAddTransaction = true }) {
                            Label("Add Transaction", systemImage: "plus")
                        }
                        Button(action: { showBudgetSettings = true }) {
                            Label("Set Budget", systemImage: "target")
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddTransaction) { AddTransactionView(store: store) }
            .sheet(isPresented: $showBudgetSettings) { BudgetSettingsView(store: store) }
        }
    }
}

// MARK: - Summary Banner

struct SummaryBanner: View {
    @ObservedObject var store: FinanceStore
    let period: FinancePeriod
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Income").font(.caption).foregroundColor(.secondary)
                Text(String(format: "$%.2f", store.totalIncome(for: period)))
                    .font(.system(size: 18, weight: .bold)).foregroundColor(.green)
            }.frame(maxWidth: .infinity)
            Divider().frame(height: 40)
            VStack(spacing: 4) {
                Text("Balance").font(.caption).foregroundColor(.secondary)
                Text(String(format: "$%.2f", store.balance(for: period)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(store.balance(for: period) >= 0 ? .primary : .red)
            }.frame(maxWidth: .infinity)
            Divider().frame(height: 40)
            VStack(spacing: 4) {
                Text("Expense").font(.caption).foregroundColor(.secondary)
                Text(String(format: "$%.2f", store.totalExpense(for: period)))
                    .font(.system(size: 18, weight: .bold)).foregroundColor(.red)
            }.frame(maxWidth: .infinity)
        }.padding().background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String; let icon: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16))
                Text(title).font(.system(size: 10))
            }
            .foregroundColor(isSelected ? .green : .secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isSelected ? Color.green.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
    }
}

// MARK: - Overview Tab

struct OverviewTab: View {
    @ObservedObject var store: FinanceStore
    let period: FinancePeriod
    @State private var expandedCategory: TransactionCategory? = nil

    var body: some View {
        VStack(spacing: 16) {
            let categories = store.expenseByCategory(for: period)
            let total = store.totalExpense(for: period)
            if categories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.pie").font(.system(size: 50)).foregroundColor(.secondary.opacity(0.4))
                    Text("No expenses yet").font(.subheadline).foregroundColor(.secondary)
                    Text("Tap + to add a transaction").font(.caption).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Spending by Category").font(.headline)
                    ForEach(categories, id: \.category) { item in
                        VStack(spacing: 0) {
                            CategoryBar(
                                category: item.category, amount: item.amount, total: total,
                                budget: store.budgetGoals[item.category],
                                avgMonthly: store.averageMonthlySpend(for: item.category),
                                isExpanded: expandedCategory == item.category
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    expandedCategory = expandedCategory == item.category ? nil : item.category
                                }
                            }
                            if expandedCategory == item.category {
                                CategoryTrendMini(store: store, category: item.category)
                                    .padding(.top, 8).transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }.padding().background(.regularMaterial).cornerRadius(16)
            }
            let recent = store.transactions(for: period).prefix(5)
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Transactions").font(.headline)
                    ForEach(Array(recent)) { t in EditableTransactionRow(transaction: t, store: store) }
                }.padding().background(.regularMaterial).cornerRadius(16)
            }
        }
    }
}

// MARK: - Category Bar

struct CategoryBar: View {
    let category: TransactionCategory
    let amount: Double; let total: Double; let budget: Double?; let avgMonthly: Double; let isExpanded: Bool
    var progress: Double { total > 0 ? amount / total : 0 }
    var budgetProgress: Double? { guard let b = budget, b > 0 else { return nil }; return amount / b }
    var barColor: Color {
        if let bp = budgetProgress { if bp > 1.0 { return .red }; if bp > 0.8 { return .orange } }
        return .green
    }
    var vsAvgText: String {
        guard avgMonthly > 0 else { return "" }
        let diff = amount - avgMonthly; let pct = (diff / avgMonthly) * 100
        if abs(pct) < 5 { return "≈ avg" }
        return diff > 0 ? String(format: "+$%.2f vs avg", diff) : String(format: "-$%.2f vs avg", abs(diff))
    }
    var vsAvgColor: Color {
        guard avgMonthly > 0 else { return .secondary }
        return amount > avgMonthly * 1.05 ? .red : amount < avgMonthly * 0.95 ? .green : .secondary
    }
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(category.emoji).font(.system(size: 18))
                Text(category.rawValue).font(.subheadline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.2f", amount)).font(.subheadline).fontWeight(.semibold)
                    if !vsAvgText.isEmpty { Text(vsAvgText).font(.caption2).foregroundColor(vsAvgColor) }
                    if let b = budget {
                        Text(String(format: "/ $%.2f budget", b)).font(.caption2)
                            .foregroundColor((budgetProgress ?? 0) > 1.0 ? .red : .secondary)
                    }
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2).foregroundColor(.secondary).padding(.leading, 4)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4).fill(barColor)
                        .frame(width: geo.size.width * CGFloat(min(progress, 1.0)), height: 8)
                    if avgMonthly > 0 && total > 0 {
                        let avgPos = min(avgMonthly / total, 1.0)
                        Rectangle().fill(Color.blue.opacity(0.6)).frame(width: 2, height: 14)
                            .position(x: geo.size.width * CGFloat(avgPos), y: 7)
                    }
                }
            }.frame(height: 8)
            if avgMonthly > 0 {
                HStack {
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.blue.opacity(0.6)).frame(width: 8, height: 2)
                        Text(String(format: "Avg $%.2f/mo", avgMonthly)).font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    if let bp = budgetProgress, bp > 1.0 {
                        Text(String(format: "Over by $%.2f", amount - (budget ?? 0))).font(.caption2).foregroundColor(.red)
                    }
                }
            }
        }.padding(.vertical, 4)
    }
}

// MARK: - Category Trend Mini

struct CategoryTrendMini: View {
    @ObservedObject var store: FinanceStore
    let category: TransactionCategory
    var data: [(month: String, amount: Double)] { store.monthlyAmounts(for: category) }
    var maxAmount: Double { data.map { $0.amount }.max() ?? 1 }
    var avgAmount: Double {
        let nz = data.filter { $0.amount > 0 }
        return nz.isEmpty ? 0 : nz.reduce(0) { $0 + $1.amount } / Double(nz.count)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(category.emoji) \(category.rawValue) — 6 Month Trend").font(.caption).foregroundColor(.secondary)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data, id: \.month) { item in
                    VStack(spacing: 4) {
                        Text(item.amount > 0 ? String(format: "$%.2f", item.amount) : "—").font(.system(size: 8)).foregroundColor(.secondary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.amount > avgAmount * 1.1 ? Color.red.opacity(0.7) : Color.green.opacity(0.7))
                            .frame(width: 28, height: max(4, CGFloat(item.amount / max(maxAmount, 1)) * 60))
                        Text(item.month).font(.system(size: 8)).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 80)
            if avgAmount > 0 {
                HStack(spacing: 4) {
                    Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 12, height: 1)
                    Text(String(format: "6mo avg: $%.2f", avgAmount)).font(.caption2).foregroundColor(.secondary)
                }
            }
        }.padding().background(Color(.systemGray6).opacity(0.5)).cornerRadius(10)
    }
}

// MARK: - Editable Transaction Row

struct EditableTransactionRow: View {
    let transaction: Transaction
    @ObservedObject var store: FinanceStore
    @State private var showEdit = false

    var dateString: String {
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f.string(from: transaction.date)
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(transaction.emoji).font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background(transaction.type == .income ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title).font(.subheadline).fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(transaction.category.emoji + " " + transaction.category.rawValue).font(.caption2).foregroundColor(.secondary)
                    Text("·").foregroundColor(.secondary)
                    Text(dateString).font(.caption2).foregroundColor(.secondary)
                }
                if !transaction.note.isEmpty { Text(transaction.note).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text((transaction.type == .income ? "+" : "-") + String(format: "$%.2f", transaction.amount))
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(transaction.type == .income ? .green : .red)
                Image(systemName: "pencil.circle").font(.caption).foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding().background(.regularMaterial).cornerRadius(12)
        .contentShape(Rectangle()).onTapGesture { showEdit = true }
        .swipeActions(edge: .leading) { Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }.tint(.blue) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.transactions.removeAll { $0.id == transaction.id } } label: { Label("Delete", systemImage: "trash") }
        }
        .sheet(isPresented: $showEdit) { EditTransactionView(transaction: transaction, store: store) }
    }
}

// MARK: - Edit Transaction View

struct EditTransactionView: View {
    let transaction: Transaction
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) var dismiss
    @State private var title: String
    @State private var amount: String
    @State private var additionalAmount = ""
    @State private var type: TransactionType
    @State private var category: TransactionCategory
    @State private var date: Date
    @State private var note: String

    init(transaction: Transaction, store: FinanceStore) {
        self.transaction = transaction; self.store = store
        _title = State(initialValue: transaction.title)
        _amount = State(initialValue: String(format: "%.2f", transaction.amount))
        _type = State(initialValue: transaction.type)
        _category = State(initialValue: transaction.category)
        _date = State(initialValue: transaction.date)
        _note = State(initialValue: transaction.note)
    }

    var filteredCategories: [TransactionCategory] {
        type == .income ? TransactionCategory.allCases.filter { $0.isIncomeType }
                       : TransactionCategory.allCases.filter { !$0.isIncomeType }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(filteredCategories, id: \.self) { Text($0.emoji + " " + $0.rawValue).tag($0) }
                    }.pickerStyle(.wheel).frame(height: 120)
                }
                Section("Title") { TextField("Defaults to category name", text: $title) }
                Section("Amount") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Current").font(.caption).foregroundColor(.secondary); Spacer()
                            HStack { Text("$").foregroundColor(.secondary); TextField("Amount", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120) }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add more").font(.caption).foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                Text("+$").foregroundColor(.green).font(.title3)
                                TextField("Additional", text: $additionalAmount).keyboardType(.decimalPad).font(.title3)
                                Button(action: {
                                    if let extra = Double(additionalAmount), extra > 0 {
                                        amount = String(format: "%.2f", (Double(amount) ?? 0) + extra)
                                        additionalAmount = ""
                                    }
                                }) { Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.green) }
                                .disabled(additionalAmount.isEmpty || Double(additionalAmount) == nil)
                            }
                        }
                        if !additionalAmount.isEmpty, let extra = Double(additionalAmount), extra > 0 {
                            Divider()
                            HStack {
                                Text("New total").font(.caption).foregroundColor(.secondary); Spacer()
                                Text(String(format: "$%.2f", (Double(amount) ?? 0) + extra)).font(.subheadline).fontWeight(.bold).foregroundColor(.green)
                            }
                        }
                    }
                }
                Section("Date & Note") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Edit Transaction").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard let amt = Double(amount), amt > 0 else { return }
                        if let i = store.transactions.firstIndex(where: { $0.id == transaction.id }) {
                            store.transactions[i].title = title.isEmpty ? category.rawValue : title
                            store.transactions[i].amount = amt
                            store.transactions[i].type = type
                            store.transactions[i].category = category
                            store.transactions[i].date = date
                            store.transactions[i].note = note
                            store.transactions[i].emoji = category.emoji
                        }
                        dismiss()
                    }.fontWeight(.bold).disabled(amount.isEmpty)
                }
            }
        }
    }
}

// MARK: - Transactions Tab

struct TransactionsTab: View {
    @ObservedObject var store: FinanceStore
    let period: FinancePeriod
    @State private var filterType: TransactionType? = nil
    @State private var filterCategory: TransactionCategory? = nil

    var filtered: [Transaction] {
        var all = store.transactions(for: period)
        if let type = filterType { all = all.filter { $0.type == type } }
        if let cat = filterCategory { all = all.filter { $0.category == cat } }
        return all
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: filterType == nil) { filterType = nil; filterCategory = nil }
                FilterChip(label: "Income", isSelected: filterType == .income) { filterType = .income; filterCategory = nil }
                FilterChip(label: "Expense", isSelected: filterType == .expense) { filterType = .expense; filterCategory = nil }
                Spacer()
            }
            if filterType == .expense {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All Categories", isSelected: filterCategory == nil) { filterCategory = nil }
                        ForEach(TransactionCategory.allCases.filter { !$0.isIncomeType }, id: \.self) { cat in
                            FilterChip(label: cat.emoji + " " + cat.rawValue, isSelected: filterCategory == cat) {
                                filterCategory = filterCategory == cat ? nil : cat
                            }
                        }
                    }
                }
            }
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.4))
                    Text("No transactions found").font(.subheadline).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    Text("Tap any row to edit · Swipe right to edit · Swipe left to delete")
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.bottom, 8)
                    ForEach(filtered) { t in EditableTransactionRow(transaction: t, store: store).padding(.bottom, 8) }
                }
            }
        }
    }
}

struct FilterChip: View {
    let label: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.caption).fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.green : Color(.systemGray6)).cornerRadius(20)
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction; let onDelete: () -> Void
    var dateString: String { let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f.string(from: transaction.date) }
    var body: some View {
        HStack(spacing: 12) {
            Text(transaction.emoji).font(.system(size: 26)).frame(width: 44, height: 44)
                .background(transaction.type == .income ? Color.green.opacity(0.1) : Color.red.opacity(0.1)).cornerRadius(10)
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title).font(.subheadline).fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(transaction.category.emoji + " " + transaction.category.rawValue).font(.caption2).foregroundColor(.secondary)
                    Text("·").foregroundColor(.secondary)
                    Text(dateString).font(.caption2).foregroundColor(.secondary)
                }
                if !transaction.note.isEmpty { Text(transaction.note).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
            }
            Spacer()
            Text((transaction.type == .income ? "+" : "-") + String(format: "$%.2f", transaction.amount))
                .font(.subheadline).fontWeight(.bold).foregroundColor(transaction.type == .income ? .green : .red)
        }
        .padding().background(.regularMaterial).cornerRadius(12)
        .swipeActions(edge: .trailing) { Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") } }
    }
}

// MARK: - Trends Tab

struct TrendsTab: View {
    @ObservedObject var store: FinanceStore
    @State private var trendPeriod: TrendPeriod = .monthly
    @State private var selectedCategoryForTrend: TransactionCategory? = nil
    enum TrendPeriod: String, CaseIterable { case weekly = "Weekly"; case monthly = "Monthly" }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Trend Period", selection: $trendPeriod) {
                ForEach(TrendPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if trendPeriod == .monthly {
                TrendChart(data: store.monthlyTotals().map { (label: $0.month, income: $0.income, expense: $0.expense) }, title: "Monthly Trend (6 months)")
            } else {
                TrendChart(data: store.weeklyTotals().map { (label: $0.week, income: $0.income, expense: $0.expense) }, title: "Weekly Trend (8 weeks)")
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Category Trend").font(.headline)
                Text("Tap a category to see its 6-month trend").font(.caption).foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TransactionCategory.allCases.filter { !$0.isIncomeType }, id: \.self) { cat in
                            Button(action: { selectedCategoryForTrend = selectedCategoryForTrend == cat ? nil : cat }) {
                                Text(cat.emoji + " " + cat.rawValue).font(.caption)
                                    .foregroundColor(selectedCategoryForTrend == cat ? .white : .secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(selectedCategoryForTrend == cat ? Color.green : Color(.systemGray6)).cornerRadius(20)
                            }
                        }
                    }
                }
                if let cat = selectedCategoryForTrend { CategoryTrendMini(store: store, category: cat) }
            }.padding().background(.regularMaterial).cornerRadius(16)
            MonthVsAverageCard(store: store)
        }
    }
}

struct MonthVsAverageCard: View {
    @ObservedObject var store: FinanceStore
    var comparisons: [(category: TransactionCategory, thisMonth: Double, avg: Double)] {
        store.expenseByCategory(for: .month).compactMap { item in
            let avg = store.averageMonthlySpend(for: item.category)
            guard avg > 0 else { return nil }
            return (item.category, item.amount, avg)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Month vs Average").font(.headline)
            Text("Compared to your 6-month average").font(.caption).foregroundColor(.secondary)
            if comparisons.isEmpty {
                Text("Not enough data yet — keep logging!").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding()
            } else {
                ForEach(comparisons, id: \.category) { item in
                    HStack(spacing: 12) {
                        Text(item.category.emoji).font(.system(size: 20)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.category.rawValue).font(.subheadline)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5)).frame(height: 6)
                                    let avgW = min(CGFloat(item.avg / max(item.thisMonth, item.avg)), 1.0) * geo.size.width
                                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.3)).frame(width: avgW, height: 6)
                                    let thisW = min(CGFloat(item.thisMonth / max(item.thisMonth, item.avg)), 1.0) * geo.size.width
                                    RoundedRectangle(cornerRadius: 3).fill(item.thisMonth > item.avg * 1.05 ? Color.red : Color.green).frame(width: thisW, height: 6)
                                }
                            }.frame(height: 6)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f", item.thisMonth)).font(.caption).fontWeight(.semibold)
                            let diff = item.thisMonth - item.avg
                            Text((diff >= 0 ? "+" : "") + String(format: "$%.2f", diff)).font(.caption2).foregroundColor(diff > 0 ? .red : .green)
                        }
                    }
                }
                HStack(spacing: 16) {
                    HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 12, height: 4); Text("This month").font(.caption2).foregroundColor(.secondary) }
                    HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.3)).frame(width: 12, height: 4); Text("6mo avg").font(.caption2).foregroundColor(.secondary) }
                }.padding(.top, 4)
            }
        }.padding().background(.regularMaterial).cornerRadius(16)
    }
}

struct TrendChart: View {
    let data: [(label: String, income: Double, expense: Double)]; let title: String
    var maxValue: Double { data.flatMap { [$0.income, $0.expense] }.max() ?? 1 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            HStack(spacing: 16) {
                HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 12, height: 4); Text("Income").font(.caption).foregroundColor(.secondary) }
                HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 12, height: 4); Text("Expense").font(.caption).foregroundColor(.secondary) }
            }
            if data.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                Text("No data yet").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 30)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(data, id: \.label) { item in
                        VStack(spacing: 4) {
                            HStack(alignment: .bottom, spacing: 2) {
                                RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.8)).frame(width: 14, height: max(4, CGFloat(item.income / maxValue) * 120))
                                RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.8)).frame(width: 14, height: max(4, CGFloat(item.expense / maxValue) * 120))
                            }
                            Text(item.label).font(.system(size: 8)).foregroundColor(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 140).padding(.vertical, 8)
            }
            Divider()
            HStack {
                Text("Net this period").font(.caption).foregroundColor(.secondary); Spacer()
                let net = data.reduce(0) { $0 + $1.income - $1.expense }
                Text((net >= 0 ? "+" : "") + String(format: "$%.2f", net)).font(.subheadline).fontWeight(.bold).foregroundColor(net >= 0 ? .green : .red)
            }
        }.padding().background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Budget Tab

struct BudgetTab: View {
    @ObservedObject var store: FinanceStore; let period: FinancePeriod
    @State private var showBudgetSettings = false
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Overall Monthly Budget").font(.headline); Spacer()
                    Button(action: { showBudgetSettings = true }) { Image(systemName: "pencil.circle").foregroundColor(.green) }
                }
                if store.overallMonthlyBudget > 0 {
                    let spent = store.monthSpent(); let budget = store.overallMonthlyBudget
                    let remaining = store.monthBudgetRemaining(); let isOver = remaining < 0
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Spent").font(.caption).foregroundColor(.secondary)
                            Text(String(format: "$%.2f", spent)).font(.title2).fontWeight(.bold).foregroundColor(isOver ? .red : .primary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Budget").font(.caption).foregroundColor(.secondary)
                            Text(String(format: "$%.2f", budget)).font(.title2).fontWeight(.bold).foregroundColor(.green)
                        }
                    }
                    ProgressView(value: min(spent / budget, 1.0)).tint(isOver ? .red : spent / budget > 0.8 ? .orange : .green)
                    Label(
                        isOver ? String(format: "Over by $%.2f", abs(remaining)) : String(format: "$%.2f remaining", remaining),
                        systemImage: isOver ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    ).font(.caption).foregroundColor(isOver ? .red : .green)
                } else {
                    Button(action: { showBudgetSettings = true }) {
                        Label("Set Overall Budget (Required)", systemImage: "exclamationmark.circle").font(.subheadline).foregroundColor(.orange)
                    }
                }
            }.padding().background(.regularMaterial).cornerRadius(16)
            if !store.budgetGoals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Category Budgets (Optional)").font(.headline)
                    ForEach(store.budgetGoals.sorted(by: { $0.key.rawValue < $1.key.rawValue }), id: \.key) { category, limit in
                        let spent = store.expenseByCategory(for: .month).first(where: { $0.category == category })?.amount ?? 0
                        BudgetProgressRow(category: category, spent: spent, limit: limit)
                    }
                }.padding().background(.regularMaterial).cornerRadius(16)
            } else {
                VStack(spacing: 8) {
                    Text("Category Budgets (Optional)").font(.headline)
                    Text("Set limits per category for detailed tracking").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button(action: { showBudgetSettings = true }) { Label("Set Category Budgets", systemImage: "plus.circle").font(.subheadline).foregroundColor(.green) }
                }.padding().background(.regularMaterial).cornerRadius(16)
            }
        }.sheet(isPresented: $showBudgetSettings) { BudgetSettingsView(store: store) }
    }
}

struct BudgetProgressRow: View {
    let category: TransactionCategory; let spent: Double; let limit: Double
    var progress: Double { min(spent / max(limit, 1), 1.0) }
    var isOver: Bool { spent > limit }
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(category.emoji + " " + category.rawValue).font(.subheadline); Spacer()
                Text(String(format: "$%.2f / $%.2f", spent, limit)).font(.caption).foregroundColor(isOver ? .red : .secondary)
            }
            ProgressView(value: progress).tint(isOver ? .red : progress > 0.8 ? .orange : .green)
            if isOver {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundColor(.red)
                    Text(String(format: "Over by $%.2f", spent - limit)).font(.caption2).foregroundColor(.red); Spacer()
                }
            }
        }.padding(.vertical, 4)
    }
}

// MARK: - Stocks Tab

struct StocksTab: View {
    @ObservedObject var store: FinanceStore
    @State private var showAddStock = false
    @State private var showingAllHoldings = false
    @State private var showingAllTx = false
    @State private var editingStock: StockHolding? = nil
    @State private var detailStock: StockHolding? = nil

    var displayedHoldings: [StockHolding] {
        showingAllHoldings ? store.stockHoldings : Array(store.stockHoldings.prefix(5))
    }
    var displayedTx: [StockTransaction] {
        let sorted = store.stockTransactions.sorted { $0.date > $1.date }
        return showingAllTx ? sorted : Array(sorted.prefix(5))
    }

    var lastFetchString: String {
        guard let t = store.lastPriceFetchTime else { return "Never fetched" }
        let f = DateFormatter(); f.timeStyle = .short; return "Updated \(f.string(from: t))"
    }

    var body: some View {
        VStack(spacing: 16) {

            // Portfolio summary
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Portfolio Summary").font(.headline)
                    Spacer()
                    // Live fetch button
                    Button(action: { store.fetchAllPricesFromYahoo() }) {
                        HStack(spacing: 4) {
                            if store.isFetchingPrices {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .foregroundColor(.green)
                            }
                            Text(store.isFetchingPrices ? "Fetching..." : "Refresh")
                                .font(.caption).foregroundColor(.green)
                        }
                    }.disabled(store.isFetchingPrices)
                }

                // Market status + last fetch
                HStack(spacing: 6) {
                    Circle().fill(store.marketStatusColor).frame(width: 8, height: 8)
                    Text(store.marketStatusText).font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text(lastFetchString).font(.caption2).foregroundColor(.secondary)
                }

                // Fetch errors
                if !store.fetcher.fetchErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(store.fetcher.fetchErrors), id: \.key) { sym, err in
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2).foregroundColor(.orange)
                                Text("\(sym): \(err)").font(.caption2).foregroundColor(.orange)
                            }
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Value").font(.caption).foregroundColor(.secondary)
                        Text(String(format: "$%.2f", store.totalStockValue)).font(.title2).fontWeight(.bold)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Overall Gain/Loss").font(.caption).foregroundColor(.secondary)
                        Text((store.totalStockGainLoss >= 0 ? "+" : "") + String(format: "$%.2f", store.totalStockGainLoss))
                            .font(.title2).fontWeight(.bold).foregroundColor(store.totalStockGainLoss >= 0 ? .green : .red)
                        Text(String(format: "%.2f%%", store.totalStockGainLossPercent))
                            .font(.caption).foregroundColor(store.totalStockGainLoss >= 0 ? .green : .red)
                    }
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isWeekend ? "vs Last Friday Close" : "Today's Change")
                            .font(.caption).foregroundColor(.secondary)
                        Text((store.todayStockGainLoss >= 0 ? "+" : "") + String(format: "$%.2f", store.todayStockGainLoss))
                            .font(.title3).fontWeight(.bold).foregroundColor(store.todayStockGainLoss >= 0 ? .green : .red)
                    }
                    Spacer()
                    Text((store.todayStockGainLossPercent >= 0 ? "+" : "") + String(format: "%.2f%%", store.todayStockGainLossPercent))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(store.todayStockGainLoss >= 0 ? .green : .red)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(store.todayStockGainLoss >= 0 ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        .cornerRadius(8)
                }

                // Yahoo Finance note
                Text("Prices via Yahoo Finance · Auto-refresh every 5 min · Pull down to refresh now")
                    .font(.caption2).foregroundColor(.secondary)

            }.padding().background(.regularMaterial).cornerRadius(16)

            

            // Holdings
            if !store.stockHoldings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Holdings (\(store.stockHoldings.count))").font(.headline)
                    ForEach(displayedHoldings) { stock in
                        StockHoldingRow(
                            stock: stock,
                            isFetching: store.fetcher.fetchingSymbols.contains(stock.symbol),
                            onTap: { detailStock = stock },
                            onEdit: { editingStock = stock },
                            onDelete: { store.deleteSymbol(stock.symbol) },
                            onRefresh: { store.fetchSinglePrice(symbol: stock.symbol) }
                        )
                    }
                    if store.stockHoldings.count > 5 {
                        Button(action: { withAnimation { showingAllHoldings.toggle() } }) {
                            Text(showingAllHoldings ? "Show less" : "Show \(store.stockHoldings.count - 5) more...")
                                .font(.caption).foregroundColor(.green).frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }.padding().background(.regularMaterial).cornerRadius(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill").font(.system(size: 50)).foregroundColor(.secondary.opacity(0.4))
                    Text("No stock holdings").font(.subheadline).foregroundColor(.secondary)
                    Text("Tap + to record a stock purchase").font(.caption).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 30)
            }

            Button(action: { showAddStock = true }) {
                Label("Record Stock Purchase / Sale", systemImage: "plus.circle.fill")
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding().background(Color.green).cornerRadius(14)
            }

            if !store.stockTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("All Transactions (\(store.stockTransactions.count))").font(.headline)
                    ForEach(displayedTx) { tx in
                        StockTransactionRow(tx: tx, onDelete: { store.stockTransactions.removeAll { $0.id == tx.id } })
                    }
                    if store.stockTransactions.count > 5 {
                        Button(action: { withAnimation { showingAllTx.toggle() } }) {
                            Text(showingAllTx ? "Show less" : "Show \(store.stockTransactions.count - 5) more...")
                                .font(.caption).foregroundColor(.green).frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }.padding().background(.regularMaterial).cornerRadius(16)
            }
        }
        .sheet(isPresented: $showAddStock) { AddStockTransactionView(store: store) }
        .sheet(item: $editingStock) { stock in EditStockView(stock: stock, store: store) }
        .sheet(item: $detailStock) { stock in StockDetailView(stock: stock, store: store) }
    }
}



// MARK: - Stock Holding Row

struct StockHoldingRow: View {
    let stock: StockHolding
    let isFetching: Bool
    let onTap: () -> Void; let onEdit: () -> Void
    let onDelete: () -> Void; let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .center, spacing: 2) {
                if isFetching {
                    ProgressView().scaleEffect(0.7).frame(width: 20, height: 20)
                } else {
                    Text(stock.symbol).font(.headline).fontWeight(.bold)
                }
                Text(String(format: "%.4f sh", stock.shares)).font(.caption2).foregroundColor(.secondary)
            }
            .frame(width: 70).padding(8).background(Color.blue.opacity(0.1)).cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Avg $%.2f → $%.2f", stock.avgBuyPrice, stock.currentPrice))
                    .font(.caption).foregroundColor(.secondary)
                Text(String(format: "Value: $%.2f", stock.totalValue)).font(.subheadline).fontWeight(.medium)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text((stock.gainLoss >= 0 ? "+" : "") + String(format: "$%.2f", stock.gainLoss))
                    .font(.subheadline).fontWeight(.bold).foregroundColor(stock.gainLoss >= 0 ? .green : .red)
                Text(String(format: "%.2f%%", stock.gainLossPercent))
                    .font(.caption2).foregroundColor(stock.gainLoss >= 0 ? .green : .red)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
        }
        .padding().background(.regularMaterial).cornerRadius(12)
        .contentShape(Rectangle()).onTapGesture { onTap() }
        .swipeActions(edge: .leading) {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }.tint(.blue)
            Button(action: onRefresh) { Label("Refresh", systemImage: "arrow.clockwise") }.tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) { Label("Delete All", systemImage: "trash") }
        }
    }
}

// MARK: - Edit Stock View

struct EditStockView: View {
    let stock: StockHolding
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) var dismiss
    @State private var newSymbol: String = ""
    @State private var newPrice: String = ""
    @State private var showSymbolWarning = false

    init(stock: StockHolding, store: FinanceStore) {
        self.stock = stock; self.store = store
        _newSymbol = State(initialValue: stock.symbol)
        _newPrice = State(initialValue: String(format: "%.2f", stock.currentPrice))
    }

    var symbolChanged: Bool {
        newSymbol.uppercased().trimmingCharacters(in: .whitespaces) != stock.symbol
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Ticker Symbol").foregroundColor(.secondary); Spacer()
                        TextField("e.g. AAPL", text: $newSymbol)
                            .textInputAutocapitalization(.characters).multilineTextAlignment(.trailing).fontWeight(.semibold)
                    }
                    if symbolChanged && !newSymbol.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label("Will rename \(stock.symbol) → \(newSymbol.uppercased())", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundColor(.blue)
                    }
                } header: { Text("Fix Ticker Symbol") }

                Section("Position (auto-calculated)") {
                    HStack { Text("Shares").foregroundColor(.secondary); Spacer(); Text(String(format: "%.4f", stock.shares)).fontWeight(.semibold) }
                    HStack { Text("Avg Buy Price").foregroundColor(.secondary); Spacer(); Text(String(format: "$%.2f", stock.avgBuyPrice)).fontWeight(.semibold) }
                    HStack { Text("Total Invested").foregroundColor(.secondary); Spacer(); Text(String(format: "$%.2f", stock.totalCost)).fontWeight(.semibold) }
                }

                Section {
                    HStack {
                        Text("$").foregroundColor(.secondary).font(.title3)
                        TextField("e.g. 213.00", text: $newPrice).keyboardType(.decimalPad).font(.title3)
                        Button(action: { store.fetchSinglePrice(symbol: newSymbol.isEmpty ? stock.symbol : newSymbol) }) {
                            Image(systemName: store.fetcher.fetchingSymbols.contains(stock.symbol) ? "hourglass" : "arrow.clockwise.circle.fill")
                                .foregroundColor(.green).font(.title3)
                        }
                    }
                    if !newPrice.isEmpty, let p = Double(newPrice) {
                        let val = p * stock.shares; let gl = val - stock.totalCost
                        let glPct = stock.totalCost > 0 ? (gl / stock.totalCost) * 100 : 0
                        HStack { Text("New value").foregroundColor(.secondary); Spacer(); Text(String(format: "$%.2f", val)).fontWeight(.semibold) }
                        HStack {
                            Text("Gain/Loss").foregroundColor(.secondary); Spacer()
                            Text((gl >= 0 ? "+" : "") + String(format: "$%.2f (%.2f%%)", gl, glPct))
                                .fontWeight(.semibold).foregroundColor(gl >= 0 ? .green : .red)
                        }
                    }
                    Text("Tap 🔄 to fetch live price from Yahoo Finance").font(.caption).foregroundColor(.secondary)
                } header: { Text("Current Price") }



                Section {
                    Text("ℹ️ To fix shares or buy price, delete the wrong transaction in the detail view and re-add it.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit \(stock.symbol)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { if symbolChanged { showSymbolWarning = true } else { performSave() } }
                        .fontWeight(.bold).disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Rename Ticker?", isPresented: $showSymbolWarning) {
                Button("Rename", role: .destructive) { performSave() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will rename all \(stock.symbol) transactions to \(newSymbol.uppercased()). Cannot be undone.")
            }
        }
    }

    func performSave() {
        let sym = stock.symbol
        let newSym = newSymbol.uppercased().trimmingCharacters(in: .whitespaces)
        if symbolChanged && !newSym.isEmpty { store.renameSymbol(from: sym, to: newSym) }
        let finalSym = symbolChanged ? newSym : sym
        if let price = Double(newPrice), price > 0 { store.updatePrice(symbol: finalSym, price: price) }
        dismiss()
    }
}

// MARK: - Stock Detail View

struct StockDetailView: View {
    let stock: StockHolding
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) var dismiss
    @State private var showEdit = false

    var txHistory: [StockTransaction] { store.transactionsFor(symbol: stock.symbol) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    StockChartView(stock: stock, transactions: txHistory, priceHistory: store.priceHistories[stock.symbol] ?? [])
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Position").font(.headline)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Shares").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "%.4f", stock.shares)).font(.title3).fontWeight(.bold)
                            }
                            Spacer()
                            VStack(alignment: .center, spacing: 4) {
                                Text("Avg Price").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "$%.2f", stock.avgBuyPrice)).font(.title3).fontWeight(.bold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Current").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "$%.2f", stock.currentPrice)).font(.title3).fontWeight(.bold)
                            }
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Invested").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "$%.2f", stock.totalCost)).font(.subheadline).fontWeight(.semibold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Gain/Loss").font(.caption).foregroundColor(.secondary)
                                Text((stock.gainLoss >= 0 ? "+" : "") + String(format: "$%.2f (%.2f%%)", stock.gainLoss, stock.gainLossPercent))
                                    .font(.subheadline).fontWeight(.bold).foregroundColor(stock.gainLoss >= 0 ? .green : .red)
                            }
                        }
                        if let fp = store.fridayClosePrices[stock.symbol] {
                            Divider()
                            HStack {
                                Text("Friday Close").font(.caption).foregroundColor(.secondary); Spacer()
                                Text(String(format: "$%.2f", fp)).font(.subheadline).fontWeight(.semibold)
                                let weekendGL = stock.totalValue - (fp * stock.shares)
                                Text((weekendGL >= 0 ? " +" : " ") + String(format: "$%.2f", weekendGL))
                                    .font(.caption).fontWeight(.medium).foregroundColor(weekendGL >= 0 ? .green : .red)
                            }
                        }
                    }.padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)

                    if !txHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(stock.symbol) Transactions").font(.headline)
                            ForEach(txHistory.reversed()) { tx in
                                StockTransactionRow(tx: tx, onDelete: { store.stockTransactions.removeAll { $0.id == tx.id } })
                            }
                        }.padding().background(.regularMaterial).cornerRadius(16).padding(.horizontal)
                    }
                }.padding(.vertical, 12)
            }
            .navigationTitle(stock.symbol).navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { store.fetchSinglePrice(symbol: stock.symbol) }) {
                            Image(systemName: "arrow.clockwise").foregroundColor(.green)
                        }
                        Button(action: { showEdit = true }) {
                            Image(systemName: "pencil.circle.fill").foregroundColor(.green)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) { EditStockView(stock: stock, store: store) }
        }
    }
}

// MARK: - Stock Chart View

struct StockChartView: View {
    let stock: StockHolding; let transactions: [StockTransaction]; let priceHistory: [PricePoint]
    var chartData: [PricePoint] {
        var pts = priceHistory
        if pts.isEmpty {
            pts = transactions.map { PricePoint(date: $0.date, price: $0.price) }
            pts.append(PricePoint(date: Date(), price: stock.currentPrice))
        }
        return pts.sorted { $0.date < $1.date }
    }
    var minPrice: Double { (chartData.map { $0.price }.min() ?? 0) * 0.995 }
    var maxPrice: Double { (chartData.map { $0.price }.max() ?? 1) * 1.005 }
    var priceRange: Double { max(maxPrice - minPrice, 0.01) }
    func xPos(idx: Int, w: CGFloat) -> CGFloat { guard chartData.count > 1 else { return w / 2 }; return w * CGFloat(idx) / CGFloat(chartData.count - 1) }
    func yPos(price: Double, h: CGFloat) -> CGFloat { h * CGFloat(1 - (price - minPrice) / priceRange) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Price Chart").font(.headline); Spacer()
                VStack(alignment: .trailing) {
                    Text(String(format: "$%.2f", stock.currentPrice)).font(.title3).fontWeight(.bold).foregroundColor(stock.gainLoss >= 0 ? .green : .red)
                    Text(String(format: "%.2f%% overall", stock.gainLossPercent)).font(.caption2).foregroundColor(stock.gainLoss >= 0 ? .green : .red)
                }
            }
            if chartData.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 36)).foregroundColor(.secondary.opacity(0.4))
                    Text("Price will chart after a few auto-refreshes").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width; let h = geo.size.height
                    ZStack {
                        ForEach(0..<5) { i in
                            Path { p in let y = h * CGFloat(i) / 4; p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }.stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                        }
                        Path { p in
                            for (i, pt) in chartData.enumerated() {
                                let x = xPos(idx: i, w: w); let y = yPos(price: pt.price, h: h)
                                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [(stock.gainLoss >= 0 ? Color.green : Color.red).opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
                        Path { p in
                            for (i, pt) in chartData.enumerated() {
                                let x = xPos(idx: i, w: w); let y = yPos(price: pt.price, h: h)
                                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }.stroke(stock.gainLoss >= 0 ? Color.green : Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        ForEach(transactions.filter { $0.type == .buy }) { tx in
                            if let nearest = chartData.enumerated().min(by: { abs($0.element.date.timeIntervalSince(tx.date)) < abs($1.element.date.timeIntervalSince(tx.date)) }) {
                                ZStack { Circle().fill(Color.white).frame(width: 16, height: 16); Circle().fill(Color.green).frame(width: 10, height: 10) }
                                    .position(x: xPos(idx: nearest.offset, w: w), y: yPos(price: tx.price, h: h))
                            }
                        }
                        ForEach(transactions.filter { $0.type == .sell }) { tx in
                            if let nearest = chartData.enumerated().min(by: { abs($0.element.date.timeIntervalSince(tx.date)) < abs($1.element.date.timeIntervalSince(tx.date)) }) {
                                ZStack { Circle().fill(Color.white).frame(width: 16, height: 16); Circle().fill(Color.red).frame(width: 10, height: 10) }
                                    .position(x: xPos(idx: nearest.offset, w: w), y: yPos(price: tx.price, h: h))
                            }
                        }
                        VStack {
                            Text(String(format: "$%.2f", maxPrice)).font(.system(size: 8)).foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", minPrice)).font(.system(size: 8)).foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(height: 180)
                HStack(spacing: 16) {
                    HStack(spacing: 4) { Circle().fill(Color.green).frame(width: 8, height: 8); Text("Buy").font(.caption2).foregroundColor(.secondary) }
                    HStack(spacing: 4) { Circle().fill(Color.red).frame(width: 8, height: 8); Text("Sell").font(.caption2).foregroundColor(.secondary) }
                    Spacer()
                    Text("\(chartData.count) data points").font(.caption2).foregroundColor(.secondary)
                }
            }
        }.padding().background(.regularMaterial).cornerRadius(16)
    }
}

// MARK: - Stock Transaction Row

struct StockTransactionRow: View {
    let tx: StockTransaction; let onDelete: () -> Void
    var dateString: String { let f = DateFormatter(); f.dateFormat = "M/d/yy"; return f.string(from: tx.date) }
    var body: some View {
        HStack(spacing: 12) {
            Text(tx.type == .buy ? "📈" : "📉").font(.system(size: 24))
                .frame(width: 40, height: 40).background(tx.type == .buy ? Color.green.opacity(0.1) : Color.red.opacity(0.1)).cornerRadius(8)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(tx.type.rawValue) \(tx.symbol)").font(.subheadline).fontWeight(.medium)
                Text(String(format: "$%.2f @ $%.2f/sh · %.4f sh · ", tx.amountInvested, tx.price, tx.shares) + dateString).font(.caption2).foregroundColor(.secondary)
                if !tx.note.isEmpty { Text(tx.note).font(.caption2).foregroundColor(.secondary) }
            }
            Spacer()
            Text((tx.type == .buy ? "-" : "+") + String(format: "$%.2f", tx.amountInvested))
                .font(.subheadline).fontWeight(.bold).foregroundColor(tx.type == .buy ? .red : .green)
        }
        .padding().background(.regularMaterial).cornerRadius(12)
        .swipeActions(edge: .trailing) { Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") } }
    }
}

// MARK: - Add Stock Transaction

struct AddStockTransactionView: View {
    @ObservedObject var store: FinanceStore
    @Environment(\.dismiss) var dismiss
    @State private var symbol = ""; @State private var type: StockTransactionType = .buy
    @State private var amountInvested = ""; @State private var pricePerShare = ""
    @State private var date = Date(); @State private var note = ""

    var sharesCalculated: Double {
        guard let amt = Double(amountInvested), let price = Double(pricePerShare), price > 0 else { return 0 }
        return amt / price
    }
    var body: some View {
        NavigationView {
            Form {
                Section("Transaction Type") {
                    Picker("Type", selection: $type) { ForEach(StockTransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                }
                Section("Stock Details") {
                    HStack {
                        TextField("Ticker symbol (e.g. AAPL)", text: $symbol).textInputAutocapitalization(.characters)
                        if !symbol.isEmpty {
                            Button(action: { store.fetchSinglePrice(symbol: symbol) }) {
                                Image(systemName: store.fetcher.fetchingSymbols.contains(symbol.uppercased()) ? "hourglass" : "arrow.clockwise.circle")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    if let livePrice = store.manualPrices[symbol.uppercased()], !symbol.isEmpty {
                        HStack {
                            Text("Live price").foregroundColor(.secondary); Spacer()
                            Text(String(format: "$%.2f", livePrice)).foregroundColor(.green).fontWeight(.semibold)
                            Button("Use") { pricePerShare = String(format: "%.2f", livePrice) }
                                .font(.caption).foregroundColor(.blue)
                        }
                    }
                    HStack {
                        Text(type == .buy ? "Amount to invest" : "Amount to sell").foregroundColor(.secondary); Spacer()
                        Text("$").foregroundColor(.secondary)
                        TextField("e.g. 50.00", text: $amountInvested).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120)
                    }
                    HStack {
                        Text("Price per share").foregroundColor(.secondary); Spacer()
                        Text("$").foregroundColor(.secondary)
                        TextField("e.g. 256.41", text: $pricePerShare).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120)
                    }
                }
                if sharesCalculated > 0 {
                    Section("Summary") {
                        HStack { Text("Shares " + (type == .buy ? "bought" : "sold")).foregroundColor(.secondary); Spacer(); Text(String(format: "%.4f shares", sharesCalculated)).fontWeight(.semibold) }
                        HStack { Text("Total " + (type == .buy ? "invested" : "received")).foregroundColor(.secondary); Spacer(); Text(String(format: "$%.2f", Double(amountInvested) ?? 0)).fontWeight(.bold).foregroundColor(type == .buy ? .red : .green) }
                    }
                }
                Section("Date & Note") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Stock Transaction").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard !symbol.isEmpty, let amt = Double(amountInvested), amt > 0, let price = Double(pricePerShare), price > 0 else { return }
                        let tx = StockTransaction(symbol: symbol.uppercased(), type: type, shares: sharesCalculated, price: price, amountInvested: amt, date: date, note: note)
                        store.addStockTransaction(tx); dismiss()
                    }.fontWeight(.bold).disabled(symbol.isEmpty || amountInvested.isEmpty || pricePerShare.isEmpty || sharesCalculated <= 0)
                }
            }
        }
    }
}

// MARK: - CD Tab

struct CDTab: View {
    @ObservedObject var store: FinanceStore
    @State private var showAddCD = false; @State private var editingCD: CDAccount? = nil
    var totalCDValue: Double { store.cdAccounts.reduce(0) { $0 + $1.estimatedTotal } }
    var totalCDPrincipal: Double { store.cdAccounts.reduce(0) { $0 + $1.principal } }
    var body: some View {
        VStack(spacing: 16) {
            if !store.cdAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("CD Summary").font(.headline)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text("Total Principal").font(.caption).foregroundColor(.secondary); Text(String(format: "$%.2f", totalCDPrincipal)).font(.title2).fontWeight(.bold) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) { Text("Est. at Maturity").font(.caption).foregroundColor(.secondary); Text(String(format: "$%.2f", totalCDValue)).font(.title2).fontWeight(.bold).foregroundColor(.green) }
                    }
                }.padding().background(.regularMaterial).cornerRadius(16)
            }
            if store.cdAccounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "banknote").font(.system(size: 50)).foregroundColor(.secondary.opacity(0.4))
                    Text("No CDs added yet").font(.subheadline).foregroundColor(.secondary)
                    Text("Tap + to add a certificate of deposit").font(.caption).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your CDs").font(.headline)
                    ForEach(store.cdAccounts) { cd in CDRow(cd: cd, onEdit: { editingCD = cd }, onDelete: { store.cdAccounts.removeAll { $0.id == cd.id } }) }
                }.padding().background(.regularMaterial).cornerRadius(16)
            }
            Button(action: { showAddCD = true }) {
                Label("Add CD Account", systemImage: "plus.circle.fill").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.green).cornerRadius(14)
            }
        }
        .sheet(isPresented: $showAddCD) { AddCDView(store: store) }
        .sheet(item: $editingCD) { cd in EditCDView(cd: cd, store: store) }
    }
}

struct CDRow: View {
    let cd: CDAccount; let onEdit: () -> Void; let onDelete: () -> Void
    var maturityString: String { let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: cd.maturityDate) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text(cd.bankName).font(.headline); Text(String(format: "%.2f%% APY · %d days", cd.annualRate, cd.termDays)).font(.caption).foregroundColor(.secondary) }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) { Text(cd.statusText).font(.caption).fontWeight(.semibold).foregroundColor(cd.statusColor); Text("Matures \(maturityString)").font(.caption2).foregroundColor(.secondary) }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) { Text("Principal").font(.caption2).foregroundColor(.secondary); Text(String(format: "$%.2f", cd.principal)).font(.subheadline).fontWeight(.semibold) }
                Spacer()
                VStack(alignment: .center, spacing: 2) { Text("Interest").font(.caption2).foregroundColor(.secondary); Text(String(format: "+$%.2f", cd.estimatedInterest)).font(.subheadline).fontWeight(.semibold).foregroundColor(.green) }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) { Text("At Maturity").font(.caption2).foregroundColor(.secondary); Text(String(format: "$%.2f", cd.estimatedTotal)).font(.subheadline).fontWeight(.bold) }
            }
            if cd.isMatured { Label("Matured — removing shortly", systemImage: "checkmark.seal.fill").font(.caption).foregroundColor(.green) }
            else if cd.daysUntilMaturity <= 7 { Label("Maturing soon — notification scheduled!", systemImage: "bell.fill").font(.caption).foregroundColor(.orange) }
        }
        .padding().background(.regularMaterial).cornerRadius(12)
        .swipeActions(edge: .leading) { Button(action: onEdit) { Label("Edit", systemImage: "pencil") }.tint(.blue) }
        .swipeActions(edge: .trailing) { Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") } }
    }
}

struct EditCDView: View {
    let cd: CDAccount; @ObservedObject var store: FinanceStore; @Environment(\.dismiss) var dismiss
    @State private var bankName: String; @State private var principal: String
    @State private var annualRate: String; @State private var startDate: Date; @State private var maturityDate: Date
    init(cd: CDAccount, store: FinanceStore) {
        self.cd = cd; self.store = store
        _bankName = State(initialValue: cd.bankName); _principal = State(initialValue: String(format: "%.2f", cd.principal))
        _annualRate = State(initialValue: String(format: "%.2f", cd.annualRate))
        _startDate = State(initialValue: cd.startDate); _maturityDate = State(initialValue: cd.maturityDate)
    }
    var estimatedInterest: Double {
        guard let p = Double(principal), let r = Double(annualRate) else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: maturityDate).day ?? 0
        return p * (r / 100) * (Double(days) / 365)
    }
    var body: some View {
        NavigationView {
            Form {
                Section("CD Details") {
                    TextField("Bank name", text: $bankName)
                    HStack { Text("$").foregroundColor(.secondary); TextField("Principal", text: $principal).keyboardType(.decimalPad) }
                    HStack { TextField("Annual rate", text: $annualRate).keyboardType(.decimalPad); Text("% APY").foregroundColor(.secondary) }
                }
                Section("Dates") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker("Maturity Date", selection: $maturityDate, displayedComponents: .date)
                }
                if !principal.isEmpty && !annualRate.isEmpty {
                    Section("Updated Estimate") {
                        HStack { Text("Est. Interest").foregroundColor(.secondary); Spacer(); Text(String(format: "+$%.2f", estimatedInterest)).foregroundColor(.green).fontWeight(.semibold) }
                        HStack { Text("Est. Total").foregroundColor(.secondary); Spacer(); Text(String(format: "$%.2f", (Double(principal) ?? 0) + estimatedInterest)).fontWeight(.bold) }
                    }
                }
            }
            .navigationTitle("Edit CD").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard let p = Double(principal), let r = Double(annualRate) else { return }
                        if let i = store.cdAccounts.firstIndex(where: { $0.id == cd.id }) {
                            store.cdAccounts[i].bankName = bankName; store.cdAccounts[i].principal = p
                            store.cdAccounts[i].annualRate = r; store.cdAccounts[i].startDate = startDate
                            store.cdAccounts[i].maturityDate = maturityDate
                            store.scheduleCDNotification(for: store.cdAccounts[i])
                        }
                        dismiss()
                    }.fontWeight(.bold)
                }
            }
        }
    }
}

struct AddCDView: View {
    @ObservedObject var store: FinanceStore; @Environment(\.dismiss) var dismiss
    @State private var bankName = ""; @State private var principal = ""
    @State private var annualRate = ""; @State private var startDate = Date()
    @State private var maturityDate = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()
    var estimatedInterest: Double {
        guard let p = Double(principal), let r = Double(annualRate) else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: maturityDate).day ?? 0
        return p * (r / 100) * (Double(days) / 365)
    }
    var body: some View {
        NavigationView {
            Form {
                Section("CD Details") {
                    TextField("Bank name (e.g. Chase, Marcus)", text: $bankName)
                    HStack { Text("$").foregroundColor(.secondary); TextField("Principal amount", text: $principal).keyboardType(.decimalPad) }
                    HStack { TextField("Annual rate (e.g. 5.25)", text: $annualRate).keyboardType(.decimalPad); Text("% APY").foregroundColor(.secondary) }
                }
                Section("Dates") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    DatePicker("Maturity Date", selection: $maturityDate, displayedComponents: .date)
                }
                if !principal.isEmpty && !annualRate.isEmpty {
                    Section("Estimate") {
                        HStack { Text("Est. Interest").foregroundColor(.secondary); Spacer(); Text(String(format: "+$%.2f", estimatedInterest)).foregroundColor(.green).fontWeight(.semibold) }
                        HStack { Text("Est. Total").foregroundColor(.secondary); Spacer(); Text(String(format: "$%.2f", (Double(principal) ?? 0) + estimatedInterest)).fontWeight(.bold) }
                    }
                }
                Section { Text("You'll get a notification 1 day before maturity.").font(.caption).foregroundColor(.secondary) }
            }
            .navigationTitle("Add CD Account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard !bankName.isEmpty, let p = Double(principal), let r = Double(annualRate) else { return }
                        let cd = CDAccount(bankName: bankName, principal: p, annualRate: r, startDate: startDate, maturityDate: maturityDate)
                        store.cdAccounts.append(cd); store.scheduleCDNotification(for: cd); dismiss()
                    }.fontWeight(.bold).disabled(bankName.isEmpty || principal.isEmpty || annualRate.isEmpty)
                }
            }
        }
    }
}

// MARK: - Add Transaction View

struct AddTransactionView: View {
    @ObservedObject var store: FinanceStore; @Environment(\.dismiss) var dismiss
    @State private var title = ""; @State private var amount = ""
    @State private var runningTotal: Double = 0; @State private var entries: [Double] = []
    @State private var type: TransactionType = .expense; @State private var category: TransactionCategory = .food
    @State private var date = Date(); @State private var note = ""
    var filteredCategories: [TransactionCategory] {
        type == .income ? TransactionCategory.allCases.filter { $0.isIncomeType } : TransactionCategory.allCases.filter { !$0.isIncomeType }
    }
    var body: some View {
        NavigationView {
            Form {
                Section("Type") {
                    Picker("Type", selection: $type) { ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        .onChange(of: type) { category = filteredCategories.first ?? .other }
                }
                Section("Category") { Picker("Category", selection: $category) { ForEach(filteredCategories, id: \.self) { Text($0.emoji + " " + $0.rawValue).tag($0) } }.pickerStyle(.wheel).frame(height: 120) }
                Section("Title (optional)") { TextField("Defaults to category name", text: $title) }
                Section("Amount") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "$%.2f", runningTotal)).font(.system(size: 32, weight: .bold)).foregroundColor(runningTotal > 0 ? .primary : .secondary)
                            }
                            Spacer()
                            if !entries.isEmpty { Button(action: undoLast) { Label("Undo", systemImage: "arrow.uturn.backward").font(.caption).foregroundColor(.orange) } }
                        }
                        if !entries.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(entries.indices, id: \.self) { i in HStack { Image(systemName: "plus.circle.fill").foregroundColor(.green).font(.caption); Text(String(format: "$%.2f", entries[i])).font(.caption).foregroundColor(.secondary); Spacer() } }
                            }.padding(8).background(Color(.systemGray6)).cornerRadius(8)
                        }
                        HStack(spacing: 8) {
                            Text("$").foregroundColor(.secondary).font(.title3)
                            TextField("Enter amount", text: $amount).keyboardType(.decimalPad).font(.title3)
                            Button(action: addEntry) { Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.green) }.disabled(amount.isEmpty || Double(amount) == nil)
                        }.padding(.vertical, 4)
                        Text("Tap + to combine multiple items").font(.caption2).foregroundColor(.secondary)
                    }
                }
                Section("Date & Note") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Add Transaction").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { saveTransaction() }.fontWeight(.bold).disabled(runningTotal <= 0) }
            }
        }
    }
    func addEntry() { guard let val = Double(amount), val > 0 else { return }; entries.append(val); runningTotal += val; amount = "" }
    func undoLast() { guard let last = entries.last else { return }; runningTotal -= last; entries.removeLast() }
    func saveTransaction() {
        guard runningTotal > 0 else { return }
        store.transactions.append(Transaction(title: title.isEmpty ? category.rawValue : title, amount: runningTotal, type: type, category: category, date: date, note: note, emoji: category.emoji))
        dismiss()
    }
}

// MARK: - Budget Settings View

struct BudgetSettingsView: View {
    @ObservedObject var store: FinanceStore; @Environment(\.dismiss) var dismiss
    @State private var overallBudgetInput = ""; @State private var budgetInputs: [TransactionCategory: String] = [:]
    var expenseCategories: [TransactionCategory] { TransactionCategory.allCases.filter { !$0.isIncomeType } }
    var body: some View {
        NavigationView {
            Form {
                Section { Text("Overall budget is required. Category budgets are optional.").font(.caption).foregroundColor(.secondary) }
                Section("Overall Monthly Budget (Required)") {
                    HStack { Text("$").foregroundColor(.secondary); TextField("e.g. 3000", text: $overallBudgetInput).keyboardType(.decimalPad); Text("/ month").foregroundColor(.secondary) }
                }
                Section("Category Budgets (Optional)") {
                    ForEach(expenseCategories, id: \.self) { category in
                        HStack {
                            Text(category.emoji).font(.system(size: 20)).frame(width: 28)
                            Text(category.rawValue).frame(maxWidth: .infinity, alignment: .leading)
                            Text("$").foregroundColor(.secondary)
                            TextField("No limit", text: Binding(get: { budgetInputs[category] ?? "" }, set: { budgetInputs[category] = $0 })).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        }
                    }
                }
                Section { Button(role: .destructive) { store.budgetGoals = [:]; budgetInputs = [:] } label: { Label("Clear Category Budgets", systemImage: "trash") } }
            }
            .navigationTitle("Set Budget").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let v = Double(overallBudgetInput), v > 0 { store.overallMonthlyBudget = v }
                        for (category, input) in budgetInputs {
                            if let value = Double(input), value > 0 { store.budgetGoals[category] = value }
                            else { store.budgetGoals.removeValue(forKey: category) }
                        }
                        dismiss()
                    }.fontWeight(.bold)
                }
            }
            .onAppear {
                overallBudgetInput = store.overallMonthlyBudget > 0 ? String(format: "%.2f", store.overallMonthlyBudget) : ""
                for (category, limit) in store.budgetGoals { budgetInputs[category] = String(format: "%.2f", limit) }
            }
        }
    }
}
