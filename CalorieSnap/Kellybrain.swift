import SwiftUI
import FoundationModels
import HealthKit
import EventKit

// ─────────────────────────────────────────────────────────────────────────────
// Kelly AI "brain": works out what a question is about, gathers ONLY the data
// that question needs (with every number calculated by the app), shows those
// numbers, and then asks the on-device AI for advice based on them.
//
// Covers: sleep, energy & readiness, heart (HRV, resting HR), steps, workouts,
// weight, food & calories, recipes, fridge, period, calendar, countdowns,
// to-dos, wishes, stocks, CDs, spending, stock news and the Oura ring battery.
// Main app target only. Used by AIAssistantView.swift.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - What a question is about

enum AskIntent: String, CaseIterable {
    case sleep, energy, heart, activity, workouts, weight, food, recipes, fridge, period
    case schedule, countdowns, todos, wishes, stocks, news, cds, spending, ring, overview

    var keywords: [String] {
        switch self {
        case .sleep: return ["sleep", "slept", "bedtime", "insomnia", " nap", " rem ", "wake up", "woke", "睡", "失眠", "熬夜", "起床", "作息"]
        case .energy: return ["energy", "readiness", "tired", "fatigue", "recover", "exhausted", " ready", "burnout", "sluggish",
                              "精力", "累", "疲", "恢复", "状态", "准备度", "没劲"]
        case .heart: return ["hrv", "heart rate", "resting hr", "rhr", "pulse", "stress", "temperature", "心率", "心跳", "压力", "体温"]
        case .activity: return ["step", "walk", "active", "sedentary", "move more", "步数", "走路", "活动", "久坐"]
        case .workouts: return ["workout", "work out", "working out", "exercise", "train", "gym", " run ", " ran ", " run?", "jog", "yoga", "pilates", "cardio", "strength", "rest day",
                                "运动", "锻炼", "训练", "健身", "跑步", "休息日", "瑜伽", "普拉提"]
        case .weight: return ["weight", " kg", " lose", "losing", " fat ", "body fat", "slim", "bmi", "scale", "plateau", "体重", "减肥", "减重", "瘦", "胖", "斤"]
        case .food: return [" eat", " ate ", "calorie", "kcal", "meal", "breakfast", "lunch", "dinner", "snack", "protein", "carb",
                            "diet", "hungry", "sugar", "吃", "卡路里", "热量", "早餐", "午餐", "晚餐", "零食", "蛋白", "饮食", "碳水", "饿"]
        case .recipes: return ["recipe", "cook", "dish", "bake", "ingredient", "食谱", "菜谱", "做菜", "做饭", "烘焙", "做什么", "怎么做"]
        case .fridge: return ["fridge", "freezer", "expire", "expiring", "leftover", "grocer", "pantry", "storage", "shopping list",
                              "run out", "running low", "in stock", "what to buy", "what should i buy", "need to get", "要买", "冰箱", "过期", "冷冻", "买菜", "库存", "剩菜", "购物"]
        case .period: return ["period", " cycle", "pms", "menstru", "ovulat", "月经", "经期", "姨妈", "生理期", "排卵", "大姨妈"]
        case .schedule: return ["calendar", "schedule", "meeting", " event", "appointment", "what's on", "whats on", "what do i have",
                                "日程", "安排", "会议", "约会"]
        case .countdowns: return ["countdown", "anniversary", "birthday", "days until", "how many days", " trip", "holiday",
                                  "倒数", "纪念日", "生日", "还有几天", "旅行", "假期"]
        case .todos: return ["todo", "to-do", "to do", "task", "deadline", "overdue", "chores", "待办", "任务", "截止", "要做"]
        case .wishes: return ["wish", "resolution", "bucket list", "achievement", "dream", "this year's goal", "yearly goal",
                              "愿望", "心愿", "目标清单", "年度目标", "成就"]
        case .stocks: return ["stock", " market", "portfolio", "invest", "nasdaq", "s&p", " dow ", "etf", "holding", "diversif",
                              "股", "投资", "基金", "大盘", "持仓"]
        case .news: return ["news", "headline", "article", " story", "earnings", "announce", "新闻", "消息", "财报", "公告"]
        case .cds: return [" cd ", " cd?", " cds", "certificate", "matur", "interest rate", "deposit", "定期", "存款", "利息", "到期"]
        case .spending: return ["spend", "spent", "budget", "expense", "where did my money", "save money", "saving", "afford",
                                "花了", "花钱", "支出", "预算", "消费", "省钱", "开销"]
        case .ring: return ["ring battery", "oura battery", "charge my ring", "ring charge", "戒指电", "戒指充电"]
        case .overview: return ["how am i doing", "how's my day", "how is my day", "summary", "summarise", "summarize", "overall",
                                "focus on today", "what should i do today", "check in", "总结", "今天怎么样", "整体", "概况", "今天要做"]
        }
    }

    var header: String {
        switch self {
        case .sleep: return "😴 Sleep"
        case .energy: return "⚡️ Energy & readiness"
        case .heart: return "❤️ Heart & stress"
        case .activity: return "👟 Steps & activity"
        case .workouts: return "🏃‍♀️ Workouts"
        case .weight: return "⚖️ Weight"
        case .food: return "🍽️ Food"
        case .recipes: return "📖 Recipes"
        case .fridge: return "🧊 Fridge"
        case .period: return "🌸 Cycle"
        case .schedule: return "📅 Calendar"
        case .countdowns: return "⏳ Countdowns"
        case .todos: return "✅ To-dos"
        case .wishes: return "🌟 Wishes"
        case .stocks: return "📈 Stocks"
        case .news: return "📰 News"
        case .cds: return "🏦 CDs"
        case .spending: return "💳 Spending"
        case .ring: return "💍 Oura ring"
        case .overview: return "🌤️ Today"
        }
    }

    /// Short role hint for the AI when this subject comes up.
    var coaching: String {
        switch self {
        case .sleep, .energy, .heart:
            return "For sleep and recovery: HRV higher than her normal and resting HR lower than normal mean better recovery. Suggest practical habits (bedtime, light, caffeine, screens, exercise timing). Don't diagnose."
        case .activity, .workouts:
            return "For training: if readiness or energy is under 60 or sleep was under 6 hours, suggest rest or easy movement. Include 1–2 rest days a week; no more than two hard days in a row."
        case .weight, .food:
            return "For weight and food: she wants to lose weight. Healthy loss is 0.25–1 kg a week; look at trends, not single days. Never suggest under 1,200 kcal a day or extreme diets."
        case .recipes, .fridge:
            return "For cooking: prefer her saved recipes and what's in her fridge when they fit; suggest lighter swaps."
        case .period:
            return "For her cycle: give general wellness tips (energy, food, training around the cycle). Predictions are estimates. Don't diagnose."
        case .schedule, .countdowns, .todos, .wishes, .overview:
            return "For planning: help her prioritise and fit things in realistically."
        case .stocks, .cds, .spending, .news:
            return "For money: explain plainly. Never tell her to buy or sell a specific stock and never predict prices."
        case .ring:
            return ""
        }
    }

    /// Lowercased question with spaces around it, so " cd " style keywords work at the start and end.
    static func normalized(_ q: String) -> String { " " + q.lowercased() + " " }

    /// Words that only mean "calendar" when nothing more specific was asked ("what about tomorrow?").
    static let weakScheduleWords = ["tomorrow", "this week", "weekend", "busy", "free time", "plans",
                                    "明天", "本周", "这周", "周末", "有空", "忙"]

    static func detect(_ q: String) -> [AskIntent] {
        let text = normalized(q)
        var found: [AskIntent] = AskIntent.allCases.compactMap { intent -> (AskIntent, String.Index)? in
            let hits = intent.keywords.compactMap { text.range(of: $0)?.lowerBound }
            return hits.min().map { (intent, $0) }
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
        if found.contains(.fridge) && text.contains("in stock") { found.removeAll { $0 == .stocks } }
        if found.isEmpty && weakScheduleWords.contains(where: { text.contains($0) }) { found = [.schedule] }
        // "Overview" only when nothing more specific was asked
        if found.count > 1 { found.removeAll { $0 == .overview } }
        // Ring battery is about the ring, not about energy
        if found.contains(.ring) { found.removeAll { $0 == .energy } }
        // Related data that usually explains the answer
        if found.first == .energy && !found.contains(.sleep) { found.append(.sleep) }
        if found.first == .weight && !found.contains(.food) && isAdvice(q) { found.append(.food) }
        return Array(found.prefix(3))
    }

    static func isAdvice(_ q: String) -> Bool {
        let text = normalized(q)
        let words = ["why", "should", "how can", "how do i", "how to", "how could", "tip", "advice", "advise", "suggest",
                     "recommend", "improve", "better", "help me", "plan", "idea", "what can i", "what should", "is it ok",
                     "is it okay", "good for", "good idea", "worried", "worry", "normal?", "explain", "what does", "mean",
                     "compare", "focus", "fix", "boost", "reduce", "increase", "avoid",
                     "为什么", "怎么", "如何", "建议", "应该", "推荐", "可以吗", "好吗", "改善", "计划", "提高", "降低", "正常吗", "意思"]
        return words.contains { text.contains($0) }
    }
}

// MARK: - Facts the app works out

struct IntentFacts {
    let intent: AskIntent
    var lines: [String]
    var hasData: Bool
}

@MainActor
enum KellyFacts {
    private static let d = UserDefaults.standard
    private static let cal = Calendar.current

    static func day(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    static func h(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        return "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }
    private static func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
    private static func usd(_ v: Double) -> String { "$" + Int(v.rounded()).formatted() }

    static func build(_ intent: AskIntent, question: String, energy: EnergyStore, finance: FinanceStore,
                      headlines: [StockHeadline]) async -> IntentFacts {
        switch intent {
        case .sleep: return sleep(energy)
        case .energy: return energyFacts(energy)
        case .heart: return heart(energy)
        case .activity: return activity(energy)
        case .workouts: return workouts(energy)
        case .weight: return weight()
        case .food: return food()
        case .recipes: return recipes(question)
        case .fridge: return fridge()
        case .period: return await period()
        case .schedule: return schedule(question)
        case .countdowns: return countdowns()
        case .todos: return todos()
        case .wishes: return wishes()
        case .stocks: return stocks(finance)
        case .news: return news(headlines)
        case .cds: return cds(finance)
        case .spending: return spending(finance)
        case .ring: return ring(energy)
        case .overview: return await overview(energy: energy)
        }
    }

    // MARK: Body

    static func sleep(_ e: EnergyStore) -> IntentFacts {
        let nights = e.lastDays(14).filter(\.hasSleep)
        guard let last = nights.last else {
            return IntentFacts(intent: .sleep, lines: ["No sleep data in Apple Health yet."], hasData: false)
        }
        var lines: [String] = []
        var l = "\(cal.isDateInToday(last.date) ? "Last night" : day(last.date)): \(h(last.sleepHours))"
        if last.hasStages { l += " (deep \(h(last.deep)), REM \(h(last.rem)))" }
        if let s = e.ouraSleep[last.date]?.score { l += " · Oura sleep score \(s)" }
        lines.append(l)
        let week = nights.suffix(7).map(\.sleepHours)
        if let a = avg(week) { lines.append("Average last \(week.count) nights: \(h(a))") }
        let before = nights.dropLast(7).map(\.sleepHours)
        if let a = avg(week), let b = avg(Array(before)), before.count >= 3 {
            let diff = (a - b) * 60
            lines.append(abs(diff) < 10 ? "About the same as the week before" :
                            "\(Int(abs(diff))) min \(diff > 0 ? "more" : "less") per night than the week before")
        }
        let short = nights.suffix(7).filter { $0.sleepHours < 6 }.count
        if short > 0 { lines.append("\(short) of the last \(min(7, nights.count)) nights were under 6 hours") }
        if let best = nights.max(by: { $0.sleepHours < $1.sleepHours }), let worst = nights.min(by: { $0.sleepHours < $1.sleepHours }) {
            lines.append("Longest \(h(best.sleepHours)) (\(day(best.date))), shortest \(h(worst.sleepHours)) (\(day(worst.date)))")
        }
        return IntentFacts(intent: .sleep, lines: lines, hasData: true)
    }

    static func energyFacts(_ e: EnergyStore) -> IntentFacts {
        guard let latest = e.latestScored else {
            return IntentFacts(intent: .energy, lines: ["Not enough health data yet to score energy."], hasData: false)
        }
        var lines: [String] = []
        let s = latest.score
        var l = "\(cal.isDateInToday(latest.day.date) ? "Today" : day(latest.day.date)):"
        if let en = s.energy { l += " energy \(en)/100" }
        if let r = s.readiness { l += ", readiness \(r)/100\(s.readinessFromOura ? " (Oura)" : "")" }
        lines.append(l + " · \(e.mood(for: latest.day, score: s).label)")
        if let c = e.ouraReadiness[latest.day.date]?.contributors {
            let parts: [(String, Int?)] = [("HRV balance", c.hrvBalance), ("resting HR", c.restingHeartRate),
                                           ("recovery", c.recoveryIndex), ("sleep balance", c.sleepBalance),
                                           ("previous night", c.previousNight), ("activity balance", c.activityBalance)]
            let low = parts.compactMap { p in p.1.flatMap { $0 < 70 ? "\(p.0) \($0)" : nil } }
            if !low.isEmpty { lines.append("Oura says these are holding you back: " + low.joined(separator: ", ")) }
        }
        let recent = e.lastDays(14).compactMap { e.scores[$0.date]?.energy }.map(Double.init)
        if let a = avg(Array(recent.suffix(7))) { lines.append("7-day average energy: \(Int(a.rounded()))/100") }
        if recent.count >= 10, let a = avg(Array(recent.suffix(7))), let b = avg(Array(recent.dropLast(7))) {
            let diff = a - b
            if abs(diff) >= 3 { lines.append("\(diff > 0 ? "Up" : "Down") \(Int(abs(diff).rounded())) points from the week before") }
        }
        return IntentFacts(intent: .energy, lines: lines, hasData: true)
    }

    static func heart(_ e: EnergyStore) -> IntentFacts {
        let days = e.lastDays(14)
        var lines: [String] = []
        let hrvs = days.compactMap(\.hrv)
        if let last = days.last(where: { $0.hrv != nil }), let v = last.hrv, let a = avg(hrvs) {
            let pct = (v - a) / a * 100
            let sign = pct >= 0 ? "+" : ""
            lines.append("HRV \(day(last.date)): \(Int(v)) ms (\(sign)\(Int(pct.rounded()))% vs your 14-day average of \(Int(a)) ms)")
        }
        let rhrs = days.compactMap(\.rhr)
        if let last = days.last(where: { $0.rhr != nil }), let v = last.rhr, let a = avg(rhrs) {
            lines.append("Resting heart rate: \(Int(v)) bpm (average \(Int(a.rounded())) bpm)")
        }
        if let latest = e.latestScored, let c = e.ouraReadiness[latest.day.date] {
            if let t = c.temperatureDeviation { lines.append(String(format: "Body temperature vs normal: %+.1f°C (Oura)", t)) }
            if let hb = c.contributors?.hrvBalance { lines.append("Oura HRV balance: \(hb)/100") }
        }
        return IntentFacts(intent: .heart, lines: lines.isEmpty ? ["No HRV or heart-rate data in the last 2 weeks."] : lines,
                           hasData: !lines.isEmpty)
    }

    static func activity(_ e: EnergyStore) -> IntentFacts {
        let days = e.lastDays(8)
        var lines: [String] = []
        if let t = days.last, let s = t.steps { lines.append("Steps today: \(Int(s).formatted())") }
        if days.count >= 2, let s = days[days.count - 2].steps { lines.append("Yesterday: \(Int(s).formatted()) steps") }
        let week = days.dropLast().compactMap(\.steps)
        if let a = avg(week) { lines.append("Daily average (last 7 days): \(Int(a).formatted()) steps") }
        let mins = days.dropLast().compactMap(\.activeMinutes)
        if let a = avg(mins) { lines.append("Exercise minutes: about \(Int(a.rounded())) a day") }
        return IntentFacts(intent: .activity, lines: lines.isEmpty ? ["No step data yet."] : lines, hasData: !lines.isEmpty)
    }

    static func workouts(_ e: EnergyStore) -> IntentFacts {
        let week = e.recentWorkouts(days: 7)
        let month = e.recentWorkouts(days: 30)
        guard !month.isEmpty else {
            return IntentFacts(intent: .workouts, lines: ["No workouts in Apple Health in the last 30 days."], hasData: false)
        }
        let weekMinutes: Double = week.reduce(0.0) { $0 + $1.minutes }
        let plural = week.count == 1 ? "" : "s"
        var lines: [String] = ["Last 7 days: \(week.count) workout\(plural), \(Int(weekMinutes.rounded())) min"]
        if let last = month.first {
            let ago = cal.dateComponents([.day], from: cal.startOfDay(for: last.start), to: cal.startOfDay(for: Date())).day ?? 0
            let agoText: String = ago == 0 ? "today" : (ago == 1 ? "yesterday" : "\(ago) days ago")
            lines.append("Last workout: \(last.name), \(Int(last.minutes.rounded())) min, \(agoText)")
        }
        for w in week.prefix(5) {
            var s = "\(day(w.start)): \(w.name) \(Int(w.minutes.rounded())) min"
            if let k = w.kcal { s += ", \(Int(k)) kcal" }
            lines.append(s)
        }
        let types = Dictionary(grouping: month, by: \.name).mapValues(\.count).sorted { $0.value > $1.value }
        lines.append("Last 30 days: \(month.count) workouts; most often " + types.prefix(3).map { "\($0.key) (\($0.value))" }.joined(separator: ", "))
        if let r = e.latestScored?.score.readiness { lines.append("Readiness now: \(r)/100") }
        return IntentFacts(intent: .workouts, lines: lines, hasData: true)
    }

    static func weight() -> IntentFacts {
        let logs = WeightLog.loadAll().sorted { $0.date < $1.date }
        guard let last = logs.last else {
            return IntentFacts(intent: .weight, lines: ["No weight logged yet."], hasData: false)
        }
        var lines = [String(format: "Latest: %.1f kg (%@)", last.weight, day(last.date))]
        func avgWeight(from: Int, to: Int) -> Double? {
            let start = cal.date(byAdding: .day, value: -from, to: Date())!, end = cal.date(byAdding: .day, value: -to, to: Date())!
            return avg(logs.filter { $0.date > start && $0.date <= end }.map(\.weight))
        }
        if let a = avgWeight(from: 7, to: 0), let b = avgWeight(from: 14, to: 7) {
            lines.append(String(format: "7-day average %.1f kg, %@ %.1f kg from the week before", a, a <= b ? "down" : "up", abs(a - b)))
        }
        if let a = avgWeight(from: 7, to: 0), let b = avgWeight(from: 37, to: 23) {
            lines.append(String(format: "Over about a month: %@ %.1f kg", a <= b ? "down" : "up", abs(a - b)))
        }
        let recent = logs.filter { $0.date > cal.date(byAdding: .day, value: -60, to: Date())! }.map(\.weight)
        if let lo = recent.min(), let hi = recent.max() { lines.append(String(format: "Last 60 days: lowest %.1f, highest %.1f kg", lo, hi)) }
        let height = d.double(forKey: "userHeight")
        if height > 0 { lines.append(String(format: "BMI %.1f (height %.0f cm)", last.weight / pow(height / 100, 2), height)) }
        let weekly = d.double(forKey: "weeklyWeightGoal")
        if weekly > 0 { lines.append(String(format: "Your goal pace: %.1f kg a week", weekly)) }
        return IntentFacts(intent: .weight, lines: lines, hasData: true)
    }

    static func food() -> IntentFacts {
        let meals = ManualMeal.loadAll()
        let goal = d.integer(forKey: "dailyCalorieGoal")
        let today = meals.filter { cal.isDateInToday($0.date) }
        var lines: [String] = []
        let eaten = today.reduce(0) { $0 + $1.calories }
        var l = "Today: \(eaten.formatted()) kcal eaten"
        if goal > 0 {
            let rest: String = eaten <= goal ? "\((goal - eaten).formatted()) left" : "\((eaten - goal).formatted()) over"
            l += " of \(goal.formatted()) (\(rest))"
        }
        lines.append(l)
        if !today.isEmpty {
            let p = today.reduce(0) { $0 + $1.protein }, c = today.reduce(0) { $0 + $1.carbs }, f = today.reduce(0) { $0 + $1.fat }
            lines.append("Protein \(Int(p))g · carbs \(Int(c))g · fat \(Int(f))g")
            lines.append("Logged: " + today.sorted { $0.date < $1.date }.map { "\($0.name) \($0.calories)" }.joined(separator: ", "))
        }
        let start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date()))!
        let week = meals.filter { $0.date >= start && !cal.isDateInToday($0.date) }
        let byDay = Dictionary(grouping: week) { cal.startOfDay(for: $0.date) }
        if !byDay.isEmpty {
            let totals = byDay.values.map { Double($0.reduce(0) { $0 + $1.calories }) }
            let protein = byDay.values.map { $0.reduce(0) { $0 + $1.protein } }
            lines.append("Last 7 days: \(byDay.count) days logged, average \(Int(avg(totals) ?? 0).formatted()) kcal and \(Int(avg(protein) ?? 0))g protein a day")
        }
        return IntentFacts(intent: .food, lines: lines, hasData: !today.isEmpty || !byDay.isEmpty)
    }

    // MARK: Kitchen

    private static let stopBigrams: Set<String> = ["什么", "可以", "食谱", "菜谱", "今天", "怎么", "晚餐", "午餐", "早餐", "我的",
                                                   "做饭", "做菜", "一下", "有没", "没有", "推荐", "哪个", "一个"]
    private static let stopWords: Set<String> = ["what", "with", "recipe", "recipes", "cook", "make", "have", "that", "this",
                                                 "tonight", "today", "dinner", "lunch", "breakfast", "which", "saved", "should",
                                                 "can", "the", "for", "and", "some", "any", "ideas", "easy", "quick"]

    /// Saved recipes that match words in the question, best first.
    static func matchingRecipes(_ question: String, in all: [SavedRecipe]) -> [SavedRecipe] {
        let lower = question.lowercased()
        let english = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) && $0.unicodeScalars.allSatisfy { $0.isASCII } }
        let chars = Array(question)
        var bigrams: [String] = []
        if chars.count >= 2 {
            for i in 0..<(chars.count - 1) {
                let pair = String(chars[i...i + 1])
                let isChinese = pair.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
                if isChinese && !stopBigrams.contains(pair) { bigrams.append(pair) }
            }
        }
        guard !english.isEmpty || !bigrams.isEmpty else { return [] }
        let scored = all.map { r -> (SavedRecipe, Int) in
            let text: String = [r.displayTitle, r.tags.joined(separator: " "), r.keptText].joined(separator: " ").lowercased()
            let wordHits: Int = english.filter { text.contains($0) }.count
            let pairHits: Int = bigrams.filter { text.contains($0) }.count
            return (r, wordHits * 2 + pairHits)
        }
        return scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    static func recipes(_ question: String) -> IntentFacts {
        let all = RecipeStore().recipes
        guard !all.isEmpty else {
            return IntentFacts(intent: .recipes, lines: ["No saved recipes yet."], hasData: false)
        }
        var lines = ["\(all.count) saved recipes, \(all.filter(\.isFavorite).count) favourites"]
        func describe(_ r: SavedRecipe) -> String {
            let p = r.parsed
            var s = r.displayTitle
            if !r.tags.isEmpty { s += " [\(r.tags.prefix(2).joined(separator: ", "))]" }
            let ing = p.ingredients.filter { !$0.hasPrefix("【") }.prefix(4)
            if !ing.isEmpty { s += ": " + ing.joined(separator: ", ") }
            return String(s.prefix(110))
        }
        let matches = matchingRecipes(question, in: all)
        if !matches.isEmpty {
            lines.append("Matching your question:")
            lines += matches.prefix(5).map { "  • " + describe($0) }
        }
        let fridgeNames = FridgeReader.items().filter { $0.status != "Empty" }.map { $0.name.lowercased() }.filter { $0.count >= 2 }
        if !fridgeNames.isEmpty {
            let canCook = all.map { r -> (SavedRecipe, [String]) in
                let text = r.parsed.ingredients.joined(separator: " ").lowercased()
                return (r, fridgeNames.filter { text.contains($0) })
            }.filter { !$0.1.isEmpty }.sorted { $0.1.count > $1.1.count }
            if !canCook.isEmpty {
                lines.append("Uses what's in your fridge:")
                lines += canCook.prefix(4).map { "  • \($0.0.displayTitle) (has \($0.1.prefix(3).joined(separator: ", ")))" }
            }
        }
        if matches.isEmpty {
            let favs = all.filter(\.isFavorite).prefix(4)
            if !favs.isEmpty { lines.append("Favourites: " + favs.map(\.displayTitle).joined(separator: ", ")) }
            let tags = Dictionary(grouping: all.flatMap(\.tags), by: { $0 }).mapValues(\.count).sorted { $0.value > $1.value }
            if !tags.isEmpty { lines.append("Most used tags: " + tags.prefix(5).map { "\($0.key) (\($0.value))" }.joined(separator: ", ")) }
        }
        return IntentFacts(intent: .recipes, lines: lines, hasData: true)
    }

    static func fridge() -> IntentFacts {
        let items = FridgeReader.items()
        guard !items.isEmpty else {
            return IntentFacts(intent: .fridge, lines: ["Your fridge list is empty. Add items in Kitchen → Fridge."], hasData: false)
        }
        var byLoc: [String: Int] = [:]
        for i in items { byLoc[i.location ?? "Fridge", default: 0] += 1 }
        let locText = byLoc.keys.sorted().map { key -> String in "\(key) \(byLoc[key] ?? 0)" }.joined(separator: ", ")
        var lines: [String] = ["\(items.count) items: \(locText)"]
        let today = cal.startOfDay(for: Date())
        func daysLeft(_ i: FridgeItemInfo) -> Int? {
            i.expiry.map { cal.dateComponents([.day], from: today, to: cal.startOfDay(for: $0)).day ?? 0 }
        }
        let expired = items.filter { (daysLeft($0) ?? 1) < 0 }
        if !expired.isEmpty {
            lines.append("Expired: " + expired.prefix(6).map { "\($0.emoji) \($0.name) (\(-(daysLeft($0) ?? 0))d ago)" }.joined(separator: ", "))
        }
        let soon = items.filter { (0...3).contains(daysLeft($0) ?? -1) }.sorted { (daysLeft($0) ?? 0) < (daysLeft($1) ?? 0) }
        if !soon.isEmpty {
            lines.append("Use soon: " + soon.prefix(8).map { i in
                let n = daysLeft(i) ?? 0
                return "\(i.emoji) \(i.name) (\(n == 0 ? "today" : n == 1 ? "tomorrow" : "\(n) days"))"
            }.joined(separator: ", "))
        }
        let low = items.filter(\.isLow)
        if !low.isEmpty {
            lines.append("Need to buy: " + low.prefix(10).map { "\($0.emoji) \($0.name) (\($0.status.lowercased()), \($0.amount))" }.joined(separator: ", "))
        }
        let good = items.filter { !$0.isLow && (daysLeft($0) ?? 1) >= 0 }
        if !good.isEmpty {
            lines.append("Have plenty: " + good.prefix(15).map { "\($0.emoji) \($0.name)" }.joined(separator: ", "))
        }
        return IntentFacts(intent: .fridge, lines: lines, hasData: true)
    }

    // MARK: Cycle (read straight from Apple Health)

    static func period() async -> IntentFacts {
        guard HKHealthStore.isHealthDataAvailable() else {
            return IntentFacts(intent: .period, lines: ["Apple Health isn't available."], hasData: false)
        }
        let store = HKHealthStore()
        let type = HKCategoryType(.menstrualFlow)
        let start = cal.date(byAdding: .day, value: -400, to: Date())!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
        let samples = ((try? await descriptor.result(for: store)) ?? [])
            .filter { $0.value != HKCategoryValueVaginalBleeding.none.rawValue }
        guard !samples.isEmpty else {
            return IntentFacts(intent: .period, lines: ["No period data in Apple Health. Log it in the Health app (or let Oura add it) to see predictions."], hasData: false)
        }
        // A new period starts when there's a gap of more than 2 days
        var starts: [Date] = []
        var lastDay: Date?
        for s in samples {
            let dday = cal.startOfDay(for: s.startDate)
            if let l = lastDay, (cal.dateComponents([.day], from: l, to: dday).day ?? 0) <= 2 { lastDay = dday; continue }
            starts.append(dday); lastDay = dday
        }
        let lengths = zip(starts, starts.dropFirst()).compactMap { a, b -> Double? in
            let n = Double(cal.dateComponents([.day], from: a, to: b).day ?? 0)
            return (15...60).contains(n) ? n : nil
        }
        let cycle = avg(Array(lengths.suffix(6))) ?? 28
        let lastStart = starts.last!
        let today = cal.startOfDay(for: Date())
        let cycleDay = (cal.dateComponents([.day], from: lastStart, to: today).day ?? 0) + 1
        let next = cal.date(byAdding: .day, value: Int(cycle.rounded()), to: lastStart)!
        let untilNext = cal.dateComponents([.day], from: today, to: next).day ?? 0
        var lines = ["Last period started \(day(lastStart)); today is cycle day \(cycleDay)"]
        if let l = lastDay, (cal.dateComponents([.day], from: l, to: today).day ?? 9) <= 1 { lines.append("Period logged in the last day") }
        let basis: String = lengths.isEmpty ? " (estimate)" : " (from \(min(lengths.count, 6)) cycles)"
        lines.append("Average cycle: \(Int(cycle.rounded())) days\(basis)")
        lines.append(untilNext >= 0 ? "Next period expected around \(day(next)) (in \(untilNext) days)"
                                    : "Next period was expected around \(day(next)), \(-untilNext) days ago")
        let ovulation = cal.date(byAdding: .day, value: -14, to: next)!
        let toOv = cal.dateComponents([.day], from: today, to: ovulation).day ?? 0
        if toOv >= -1 && toOv <= 10 { lines.append("Estimated ovulation around \(day(ovulation))") }
        if untilNext >= 0 && untilNext <= 7 { lines.append("You're probably in the premenstrual (luteal) phase") }
        return IntentFacts(intent: .period, lines: lines, hasData: true)
    }

    // MARK: Plans

    static func schedule(_ question: String) -> IntentFacts {
        let text = AskIntent.normalized(question)
        let today = cal.startOfDay(for: Date())
        var from = today
        var days = 7
        if text.contains("tomorrow") || text.contains("明天") { from = cal.date(byAdding: .day, value: 1, to: today)!; days = 1 }
        else if text.contains("today") || text.contains("今天") { days = 1 }
        let to = cal.date(byAdding: .day, value: days, to: from)!
        var items: [(Date, String, Bool)] = []   // date, title, all-day
        let status = EKEventStore.authorizationStatus(for: .event)
        var calendarNote: String?
        if status == .fullAccess {
            let ek = EKEventStore()
            let pred = ek.predicateForEvents(withStart: from, end: to, calendars: nil)
            for ev in ek.events(matching: pred) {
                let start: Date = ev.startDate ?? from
                let title: String = ev.title ?? "Event"
                items.append((start, title, ev.isAllDay))
            }
        } else {
            calendarNote = "Apple Calendar access is off, so only events added in Kelly Life are shown."
        }
        if let data = d.data(forKey: "calendarEvents_v2"), let own = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
            items += own.filter { $0.date >= from && $0.date < to }.map { ($0.date, "\($0.emoji) \($0.title)", false) }
        }
        items.sort { $0.0 < $1.0 }
        let label = days == 1 ? (cal.isDateInToday(from) ? "Today" : "Tomorrow") : "Next 7 days"
        var lines: [String] = []
        if items.isEmpty {
            lines.append("\(label): nothing on the calendar")
        } else {
            lines.append("\(label): \(items.count) event\(items.count == 1 ? "" : "s")")
            for (date, title, allDay) in items.prefix(12) {
                let time: String = allDay ? "all day" : date.formatted(date: .omitted, time: .shortened)
                let when: String = days == 1 ? time : "\(day(date)) \(time)"
                lines.append("  • \(when): \(title)")
            }
        }
        if let calendarNote { lines.append(calendarNote) }
        return IntentFacts(intent: .schedule, lines: lines, hasData: true)
    }

    static func countdowns() -> IntentFacts {
        guard let data = d.data(forKey: "calendarEvents_v2"),
              let all = try? JSONDecoder().decode([CalendarEvent].self, from: data) else {
            return IntentFacts(intent: .countdowns, lines: ["No countdowns saved."], hasData: false)
        }
        let today = cal.startOfDay(for: Date())
        var upcoming: [(days: Int, date: Date, event: CalendarEvent)] = []
        for e in all where e.isCountdown || e.isAnniversary {
            var date = cal.startOfDay(for: e.date)
            if e.isAnniversary {
                // Next time this date comes round
                var comps = cal.dateComponents([.month, .day], from: e.date)
                comps.year = cal.component(.year, from: today)
                if let thisYear = cal.date(from: comps) {
                    date = thisYear < today ? (cal.date(byAdding: .year, value: 1, to: thisYear) ?? thisYear) : thisYear
                }
            }
            let days = cal.dateComponents([.day], from: today, to: date).day ?? 0
            if days >= 0 { upcoming.append((days, date, e)) }
        }
        upcoming.sort { $0.days < $1.days }
        var lines: [String] = []
        for item in upcoming.prefix(6) {
            let when: String
            if item.days == 0 { when = "today!" }
            else if item.days == 1 { when = "tomorrow" }
            else { when = "in \(item.days) days" }
            let yearly = item.event.isAnniversary ? " (every year)" : ""
            lines.append("\(item.event.emoji) \(item.event.title): \(when)\(yearly) · \(day(item.date))")
        }
        if lines.isEmpty {
            return IntentFacts(intent: .countdowns, lines: ["No upcoming countdowns."], hasData: false)
        }
        return IntentFacts(intent: .countdowns, lines: lines, hasData: true)
    }

    static func todos() -> IntentFacts {
        guard let data = d.data(forKey: "todoItems_v2"),
              let all = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            return IntentFacts(intent: .todos, lines: ["No to-dos saved."], hasData: false)
        }
        let open = all.filter { !$0.isDone }
        let doneToday = all.filter { $0.isDone && ($0.completedAt.map { cal.isDateInToday($0) } ?? false) }
        var lines = ["\(open.count) open, \(doneToday.count) done today"]
        let overdue = open.filter(\.isOverdue)
        if !overdue.isEmpty { lines.append("Overdue: " + overdue.prefix(5).map { "\($0.emoji) \($0.title)" }.joined(separator: ", ")) }
        let dueSoon = open.filter { t in !t.isOverdue && t.hasDueDate && (t.dueDate.map { $0 < cal.date(byAdding: .day, value: 3, to: Date())! } ?? false) }
        if !dueSoon.isEmpty { lines.append("Due soon: " + dueSoon.prefix(5).map { "\($0.title) (\($0.dueDateLabel.lowercased()))" }.joined(separator: ", ")) }
        let high = open.filter { $0.priority == .high && !$0.isOverdue }
        if !high.isEmpty { lines.append("High priority: " + high.prefix(5).map(\.title).joined(separator: ", ")) }
        let rest = open.filter { $0.priority != .high && !$0.isOverdue && !dueSoon.map(\.id).contains($0.id) }
        if !rest.isEmpty { lines.append("Others: " + rest.prefix(6).map(\.title).joined(separator: ", ")) }
        return IntentFacts(intent: .todos, lines: lines, hasData: !all.isEmpty)
    }

    static func wishes() -> IntentFacts {
        guard let data = d.data(forKey: "wishItems_v2"),
              let all = try? JSONDecoder().decode([WishItem].self, from: data), !all.isEmpty else {
            return IntentFacts(intent: .wishes, lines: ["No wishes saved yet."], hasData: false)
        }
        let year = cal.component(.year, from: Date())
        let thisYear = all.filter { $0.targetYear == year }
        let done = thisYear.filter(\.isDone)
        var lines = ["\(year): \(done.count) of \(thisYear.count) wishes done"]
        let open = thisYear.filter { !$0.isDone }
        let byCat = Dictionary(grouping: open, by: \.category)
        for (cat, items) in byCat.sorted(by: { $0.value.count > $1.value.count }).prefix(5) {
            lines.append("\(cat.emoji) \(cat.rawValue): " + items.prefix(4).map { w in
                w.progressCount > 0 ? "\(w.title) (\(w.progressCount) updates)" : w.title
            }.joined(separator: ", "))
        }
        if !done.isEmpty { lines.append("Done: " + done.prefix(5).map(\.title).joined(separator: ", ")) }
        let monthsLeft = 12 - cal.component(.month, from: Date())
        lines.append("\(monthsLeft) month\(monthsLeft == 1 ? "" : "s") left this year")
        return IntentFacts(intent: .wishes, lines: lines, hasData: true)
    }

    // MARK: Money

    static func stocks(_ finance: FinanceStore) -> IntentFacts {
        let f = MoneyFacts(finance)
        guard !f.holdings.isEmpty else { return IntentFacts(intent: .stocks, lines: ["No stocks in the app."], hasData: false) }
        let gain = f.stocksTotal - f.stocksCost
        let gainPct: Double = f.stocksCost > 0 ? gain / f.stocksCost * 100 : 0
        let direction = gain >= 0 ? "up" : "down"
        let pctText = String(format: "%+.1f%%", gainPct)
        var lines: [String] = ["\(f.holdings.count) holdings worth \(usd(f.stocksTotal)), \(direction) \(usd(abs(gain))) (\(pctText)) since bought"]
        if finance.hasPreviousCloseData {
            let todayGain = finance.todayStockGainLoss
            let sign = todayGain >= 0 ? "+" : "−"
            let todayPct = String(format: "%+.2f%%", finance.todayStockGainLossPercent)
            lines.append("Today: \(sign)\(usd(abs(todayGain))) (\(todayPct))")
        }
        lines.append("Largest: " + f.holdings.prefix(4).map { "\($0.symbol) \(Int($0.share.rounded()))%" }.joined(separator: ", "))
        lines.append("By type: " + f.groups.prefix(5).map { "\($0.name) \(Int($0.share.rounded()))%" }.joined(separator: ", "))
        if let best = f.holdings.max(by: { $0.gainPct < $1.gainPct }), let worst = f.holdings.min(by: { $0.gainPct < $1.gainPct }) {
            lines.append(String(format: "Best %@ %+.0f%%, worst %@ %+.0f%% since bought", best.symbol, best.gainPct, worst.symbol, worst.gainPct))
        }
        let all = f.stocksTotal + f.cdsTotal
        if all > 0 && f.cdsTotal > 0 {
            lines.append("Stocks are \(Int((f.stocksTotal / all * 100).rounded()))% of your investments; CDs \(Int((f.cdsTotal / all * 100).rounded()))%")
        }
        return IntentFacts(intent: .stocks, lines: lines, hasData: true)
    }

    static func news(_ headlines: [StockHeadline]) -> IntentFacts {
        guard !headlines.isEmpty else {
            return IntentFacts(intent: .news, lines: ["No recent headlines found (or no internet connection)."], hasData: false)
        }
        let lines = headlines.prefix(18).map { "[\($0.symbol)] \(day($0.date)): \($0.title)" }
        return IntentFacts(intent: .news, lines: Array(lines), hasData: true)
    }

    static func cds(_ finance: FinanceStore) -> IntentFacts {
        let f = MoneyFacts(finance)
        guard !f.cds.isEmpty else { return IntentFacts(intent: .cds, lines: ["No CDs in the app."], hasData: false) }
        let avgRate = f.cdsTotal > 0 ? f.cds.reduce(0) { $0 + $1.annualRate * $1.principal } / f.cdsTotal : 0
        var lines = ["\(f.cds.count) CDs, \(usd(f.cdsTotal)) total, average \(String(format: "%.2f%%", avgRate))"]
        for cd in f.cds {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: cd.maturityDate)).day ?? 0
            let name = cd.bankName.isEmpty ? "CD" : cd.bankName
            let rate = String(format: "%.2f%%", cd.annualRate)
            let date = cd.maturityDate.formatted(.dateTime.month(.abbreviated).day().year())
            let left: String = days > 0 ? "in \(days) days" : (days == 0 ? "today" : "matured")
            lines.append("\(name): \(usd(cd.principal)) at \(rate), matures \(date) (\(left)), interest about \(usd(cd.estimatedInterest))")
        }
        return IntentFacts(intent: .cds, lines: lines, hasData: true)
    }

    static func spending(_ finance: FinanceStore) -> IntentFacts {
        let f = MoneyFacts(finance)
        guard f.hasTransactions else {
            return IntentFacts(intent: .spending, lines: ["No spending recorded this month. Add transactions in the Finance tab to see it here."], hasData: false)
        }
        var first = "This month: spent \(usd(f.spent))"
        if f.budget > 0 {
            let used = Int((f.spent / f.budget * 100).rounded())
            first += " of \(usd(f.budget)) budget (\(used)%)"
        }
        if f.income > 0 { first += ", income \(usd(f.income))" }
        var lines: [String] = [first]
        let dayOfMonth = cal.component(.day, from: Date())
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        if f.budget > 0 {
            let pace = f.spent / Double(dayOfMonth) * Double(daysInMonth)
            lines.append("At this pace: about \(usd(pace)) by month end (\(pace <= f.budget ? "within" : "over") budget)")
        }
        if !f.topCategories.isEmpty { lines.append("Top: " + f.topCategories.prefix(5).map { "\($0.0) \(usd($0.1))" }.joined(separator: ", ")) }
        return IntentFacts(intent: .spending, lines: lines, hasData: true)
    }

    static func ring(_ e: EnergyStore) -> IntentFacts {
        guard let b = e.ringBattery else {
            return IntentFacts(intent: .ring, lines: ["Ring battery unknown. Connect Oura in the Energy screen."], hasData: false)
        }
        return IntentFacts(intent: .ring, lines: ["Oura ring battery: \(b.level)%\(b.charging == true ? ", charging" : "")"], hasData: true)
    }

    static func overview(energy e: EnergyStore) async -> IntentFacts {
        var lines: [String] = []
        if let first = energyFacts(e).lines.first, e.latestScored != nil { lines.append(first) }
        if let s = sleep(e).lines.first, sleep(e).hasData { lines.append("Sleep " + s.lowercased()) }
        if let a = activity(e).lines.first, activity(e).hasData { lines.append(a) }
        lines.append(food().lines[0])
        let t = todos(); if t.hasData { lines += t.lines.prefix(2) }
        let sched = schedule("today").lines.first ?? ""
        if !sched.isEmpty { lines.append(sched) }
        if let c = countdowns().lines.first, countdowns().hasData { lines.append("Next: " + c) }
        return IntentFacts(intent: .overview, lines: lines, hasData: true)
    }
}

// MARK: - Fridge (same data as the Fridge screen)

struct FridgeItemInfo {
    let name: String
    let emoji: String
    let location: String?
    let expiry: Date?
    let isLow: Bool          // Empty, almost gone or running low
    let status: String       // "Running low", "Good", …
    let amount: String       // "25%" or "2/6"
}

enum FridgeReader {
    static func items() -> [FridgeItemInfo] {
        let d = UserDefaults.standard
        let data = d.data(forKey: "fridgeItems_v2") ?? d.data(forKey: "fridgeItems")
        guard let data, let items = try? JSONDecoder().decode([FridgeItem].self, from: data) else { return [] }
        return items.map { i in
            let low = [FridgeItem.StockStatus.empty, .critical, .low].contains(i.status)
            return FridgeItemInfo(name: i.name, emoji: i.emoji, location: i.location.rawValue,
                                  expiry: i.hasExpiry ? i.expiryDate : nil, isLow: low,
                                  status: i.status.label, amount: i.displayAmount)
        }
    }
}

// MARK: - The answer

@MainActor
enum KellyBrain {
    struct Turn { let question: String; let answer: String; let intents: [AskIntent] }

    static func defaultIntents(for topic: AITopic) -> [AskIntent] {
        switch topic {
        case .recipes: return [.food, .recipes]
        case .weight: return [.weight, .food]
        case .health: return [.sleep, .energy, .heart]
        case .training: return [.workouts, .energy]
        case .money: return [.stocks, .cds, .spending]
        case .news: return [.news]
        case .chat: return [.overview]
        }
    }

    /// Answers any question: the app's numbers for what was asked, then advice from the on-device AI.
    static func answer(_ question: String, topic: AITopic, previous: Turn?, energy: EnergyStore,
                       finance: FinanceStore, headlines: [StockHeadline]) async -> (text: String, intents: [AskIntent]) {
        var intents = AskIntent.detect(question)
        var guessed = false
        if intents.isEmpty {
            if let p = previous, !p.intents.isEmpty { intents = p.intents }          // follow-up question
            else { intents = defaultIntents(for: topic); guessed = true }
        }
        var facts: [IntentFacts] = []
        for i in intents { facts.append(await KellyFacts.build(i, question: question, energy: energy, finance: finance, headlines: headlines)) }

        let advice = AskIntent.isAdvice(question) || intents.contains(.news) || guessed
        var out: [String] = []
        if !guessed {
            for f in facts where f.intent != .news {
                out.append("**\(f.intent.header)**")
                out += f.lines.map { $0.hasPrefix("  •") ? $0 : "- " + $0 }
                out.append("")
            }
        }
        guard advice else {
            return (out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), intents)
        }
        if let tips = await aiAdvice(question: question, facts: facts, previous: previous, guessed: guessed) {
            if !out.isEmpty { out.append(guessed ? "" : "**💡 Kelly AI**") }
            out.append(tips)
        } else if out.isEmpty {
            out.append("Apple Intelligence couldn't answer that one. Try asking a little differently.")
        }
        return (out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), intents)
    }

    private static func aiAdvice(question: String, facts: [IntentFacts], previous: Turn?, guessed: Bool) async -> String? {
        let coaching = Array(Set(facts.map(\.intent.coaching))).filter { !$0.isEmpty }.joined(separator: " ")
        let profile = facts.contains { [AskIntent.weight, .food, .workouts, .energy, .sleep, .recipes].contains($0.intent) }
            ? AIContext.profile() : ""
        let dataNote: String = guessed
            ? "Her data is below; use it only if it's relevant to the question."
            : "She can already see her numbers above your reply, so don't list them again; refer to them only to explain your advice."
        let instructions = """
        You are Kelly AI, a warm, practical assistant inside Kelly's personal app. \
        Answer exactly what she asked, directly, in 3–6 short bullet points (under 150 words). \
        \(dataNote) \
        Never invent numbers or facts that aren't given. If the data doesn't cover something, say so in one line and give general guidance. \
        \(coaching) General wellness and general information only, not medical or financial advice. \
        Reply in the same language she writes in (English or Chinese). Today is \(Date().formatted(date: .complete, time: .omitted)).
        """
        var prompt = ""
        if !profile.isEmpty { prompt += profile + "\n" }
        for f in facts { prompt += "\(f.intent.header):\n" + f.lines.joined(separator: "\n") + "\n\n" }
        if let p = previous {
            prompt += "Previous question: \(p.question.prefix(200))\nYour previous answer (short): \(p.answer.prefix(300))\n\n"
        }
        prompt += "Her question: \(question)"

        let session = LanguageModelSession { instructions }
        do {
            return try await session.respond(to: prompt).content
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                // Try again with fewer facts
                let short = facts.map { "\($0.intent.header): " + $0.lines.prefix(3).joined(separator: "; ") }.joined(separator: "\n")
                return try? await LanguageModelSession { instructions }.respond(to: short + "\n\nHer question: \(question)").content
            case .guardrailViolation, .refusal:
                let gentle = "Please answer as a supportive general-wellness and life coach for a healthy adult, with safe, gradual suggestions. Question: \(question)"
                return try? await LanguageModelSession { instructions }.respond(to: gentle).content
            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}
