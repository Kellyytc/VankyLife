import SwiftUI
import HealthKit
import Charts
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// Energy — an Oura-style daily energy score built from Apple Health data
// (works with Apple Watch, Oura, or anything else that syncs to Health).
//
// Today's Energy  = Readiness × 0.5 + Sleep × 0.3 + HRV-vs-baseline × 0.2
// Readiness       = HRV × 0.4 + Resting HR × 0.3 + Sleep × 0.3
// Baselines       = median of the 28 days before each day
// Sleep counts toward the day you wake up.
// If Oura is connected (OuraService.swift), Oura's own Readiness and Sleep
// scores replace the estimates for days where Oura has data.
//
// Main app target only.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Models

struct EnergyDay: Identifiable {
    let date: Date
    var deep: Double = 0       // hours
    var rem: Double = 0
    var light: Double = 0      // core / unspecified sleep
    var hrv: Double?           // ms (SDNN)
    var rhr: Double?           // bpm
    var steps: Double?
    var activeMinutes: Double?

    var id: Date { date }
    var sleepHours: Double { deep + rem + light }
    var hasSleep: Bool { sleepHours >= 0.5 }
    var hasStages: Bool { deep + rem > 0 }
}

/// One workout from Apple Health (Apple Watch, Oura, Strava, gym apps…).
struct WorkoutEntry: Identifiable {
    let id: UUID
    let start: Date
    let minutes: Double
    let activity: HKWorkoutActivityType
    let kcal: Double?
    let avgHeartRate: Double?
    let distanceKm: Double?
    let source: String

    var name: String { WorkoutEntry.name(for: activity) }
    var icon: String { WorkoutEntry.icon(for: activity) }

    static func name(for t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Running"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining: return "Core training"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing, .stairs, .stepTraining: return "Stairs"
        case .dance, .cardioDance, .socialDance: return "Dance"
        case .mixedCardio: return "Cardio"
        case .flexibility, .cooldown, .preparationAndRecovery, .mindAndBody: return "Stretching & recovery"
        case .tennis, .badminton, .tableTennis, .pickleball: return "Racket sports"
        case .kickboxing, .boxing, .martialArts: return "Boxing & martial arts"
        default: return "Workout"
        }
    }

    static func icon(for t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "figure.strengthtraining.traditional"
        case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
        case .coreTraining: return "figure.core.training"
        case .yoga: return "figure.yoga"
        case .pilates: return "figure.pilates"
        case .elliptical: return "figure.elliptical"
        case .rowing: return "figure.rower"
        case .stairClimbing, .stairs, .stepTraining: return "figure.stairs"
        case .dance, .cardioDance, .socialDance: return "figure.dance"
        case .flexibility, .cooldown, .preparationAndRecovery, .mindAndBody: return "figure.flexibility"
        case .tennis, .badminton, .tableTennis, .pickleball: return "figure.tennis"
        case .kickboxing, .boxing, .martialArts: return "figure.boxing"
        default: return "figure.mixed.cardio"
        }
    }
}

struct EnergyScore {
    var sleep: Int?
    var hrv: Int?          // HRV relative to baseline
    var rhr: Int?          // resting HR relative to baseline
    var readiness: Int?
    var energy: Int?
    var readinessFromOura = false
    var sleepFromOura = false
    var hrvFromOura = false
}

enum EnergyLevel {
    case high, mid, low

    init(_ score: Int) {
        switch score {
        case 75...: self = .high
        case 60..<75: self = .mid
        default: self = .low
        }
    }

    var color: Color {
        switch self {
        case .high: return Color(red: 0.30, green: 0.66, blue: 0.40)
        case .mid:  return Color(red: 0.40, green: 0.56, blue: 0.85)
        case .low:  return Color(red: 0.82, green: 0.56, blue: 0.20)
        }
    }
    var title: String {
        switch self {
        case .high: return "High energy"
        case .mid:  return "Steady"
        case .low:  return "Low energy"
        }
    }
    var badge: String {
        switch self {
        case .high: return "HIGH ENERGY"
        case .mid:  return "STEADY"
        case .low:  return "LOW ENERGY"
        }
    }
    var advice: String {
        switch self {
        case .high: return "You're well recovered. A good day for a harder workout or a busy schedule."
        case .mid:  return "Normal energy today. Keep a steady pace and get to bed on time."
        case .low:  return "Your body is asking for recovery: go easier on training today and prioritise an early night."
        }
    }
}

// MARK: - Store

@MainActor
final class EnergyStore: ObservableObject {
    @Published private(set) var days: [EnergyDay] = []          // oldest → today
    @Published private(set) var scores: [Date: EnergyScore] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var message: String?
    @Published private(set) var ouraReadiness: [Date: OuraReadinessDay] = [:]
    @Published private(set) var ouraSleep: [Date: OuraSleepDay] = [:]
    @Published private(set) var ouraError: String?
    @Published private(set) var ringBattery: OuraBattery?
    @Published private(set) var workouts: [WorkoutEntry] = []      // newest first, last 30 days

    private let health = HKHealthStore()
    private let cal = Calendar.current
    private let lookbackDays = 60

    private var readTypes: Set<HKObjectType> {
        [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.appleExerciseTime),
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
    }

    // MARK: Convenience

    var today: EnergyDay? { days.last }
    var todayScore: EnergyScore? { today.flatMap { scores[$0.date] } }

    /// Most recent day that has an energy score (today, or yesterday early in the morning).
    var latestScored: (day: EnergyDay, score: EnergyScore)? {
        for d in days.reversed() {
            if let s = scores[d.date], s.energy != nil { return (d, s) }
        }
        return nil
    }

    func lastDays(_ n: Int) -> [EnergyDay] { Array(days.suffix(n)) }

    // MARK: Loading

    func load() async {
        guard !isLoading else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Health data isn't available on this device."
            return
        }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }

        do {
            try await health.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            message = "Couldn't get Health permission: \(error.localizedDescription)"
            return
        }

        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -(lookbackDays - 1), to: cal.startOfDay(for: end))
        else { return }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        async let sleep = fetchSleep(start: start, end: end)
        async let hrv   = dailyStats(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), sum: false, start: start, end: end)
        async let rhr   = dailyStats(.restingHeartRate, unit: bpm, sum: false, start: start, end: end)
        async let steps = dailyStats(.stepCount, unit: .count(), sum: true, start: start, end: end)
        async let ex    = dailyStats(.appleExerciseTime, unit: .minute(), sum: true, start: start, end: end)
        let (s, h, r, st, e) = await (sleep, hrv, rhr, steps, ex)

        var built: [EnergyDay] = []
        var day = start
        while day <= end {
            var d = EnergyDay(date: day)
            if let parts = s[day] { d.deep = parts.deep; d.rem = parts.rem; d.light = parts.light }
            d.hrv = h[day]; d.rhr = r[day]; d.steps = st[day]; d.activeMinutes = e[day]
            built.append(d)
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        await loadOura(start: start, end: end)
        workouts = await fetchWorkouts(days: 30)

        days = built
        scores = Self.computeScores(
            for: built,
            ouraReadiness: ouraReadiness.compactMapValues(\.score),
            ouraSleep: ouraSleep.compactMapValues(\.score),
            ouraHRV: ouraReadiness.compactMapValues { $0.contributors?.hrvBalance }
        )

        let anything = built.contains { $0.hasSleep || $0.hrv != nil || $0.steps != nil }
        message = anything ? nil :
            "No Health data found yet. Check Settings → Health → Data Access & Devices → CalorieSnap and turn everything on."
    }

    // MARK: Oura

    private func loadOura(start: Date, end: Date) async {
        let oura = OuraService.shared
        guard oura.isConnected else {
            ouraReadiness = [:]; ouraSleep = [:]; ouraError = nil; ringBattery = nil
            return
        }
        let through = cal.date(byAdding: .day, value: 1, to: end) ?? end
        do {
            // One after the other, so a token refresh never happens twice at once.
            let readiness = try await oura.fetchReadiness(from: start, to: through)
            let sleep = try await oura.fetchSleep(from: start, to: through)
            var r: [Date: OuraReadinessDay] = [:]
            for item in readiness { if let d = OuraService.date(fromDay: item.day) { r[d] = item } }
            var s: [Date: OuraSleepDay] = [:]
            for item in sleep { if let d = OuraService.date(fromDay: item.day) { s[d] = item } }
            ouraReadiness = r; ouraSleep = s; ouraError = nil
        } catch {
            ouraError = error.localizedDescription
        }
        // Battery is a nice extra; if it fails, keep the scores.
        ringBattery = (try? await oura.fetchLatestBattery()) ?? ringBattery
    }

    /// Picks the buddy's mood from the day's data. The most important signal wins.
    func mood(for day: EnergyDay, score: EnergyScore) -> BuddyMood {
        if let temp = ouraReadiness[day.date]?.temperatureDeviation, temp >= 0.5 { return .warm }
        guard let energy = score.energy else { return .steady }
        if energy < 45 { return .exhausted }
        if day.hasSleep && day.sleepHours < 6 { return .shortSleep }
        if let hrv = score.hrv, hrv < 50 { return .stressed }
        let activeDay = (day.activeMinutes ?? 0) >= 45 || (day.steps ?? 0) >= 10_000
        if energy >= 85 { return .energized }
        if energy >= 60 && activeDay { return .active }
        if energy >= 75 { return .happy }
        if energy >= 60 { return .steady }
        return .tired
    }

    /// Oura's readiness details for the given day, if any.
    func ouraDetails(for day: Date) -> OuraReadinessDay? { ouraReadiness[day] }

    // MARK: Workouts

    private func fetchWorkouts(days: Int) async -> [WorkoutEntry] {
        let start = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: Date()))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let results = try? await descriptor.result(for: health) else { return [] }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return results.map { w in
            WorkoutEntry(
                id: w.uuid,
                start: w.startDate,
                minutes: w.duration / 60,
                activity: w.workoutActivityType,
                kcal: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                avgHeartRate: w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm),
                distanceKm: w.totalDistance.map { $0.doubleValue(for: .meterUnit(with: .kilo)) },
                source: w.sourceRevision.source.name
            )
        }
    }

    /// Workouts in the last `days` days (newest first).
    func recentWorkouts(days: Int) -> [WorkoutEntry] {
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date())) ?? Date()
        return workouts.filter { $0.start >= start }
    }

    // MARK: HealthKit queries

    private struct SleepParts { var deep = 0.0, rem = 0.0, light = 0.0 }

    /// Sleep stages per wake-up day. When several devices recorded the same night
    /// (e.g. iPhone + Watch + Oura), only the source with the most detailed data is used,
    /// so nothing is counted twice.
    private func fetchSleep(start: Date, end: Date) async -> [Date: SleepParts] {
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-12 * 3600), end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: health) else { return [:] }

        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let stageValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                     HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                                     HKCategoryValueSleepAnalysis.asleepCore.rawValue]

        let asleep = samples.filter { asleepValues.contains($0.value) }
        let byDay = Dictionary(grouping: asleep) { cal.startOfDay(for: $0.endDate) }

        var out: [Date: SleepParts] = [:]
        for (day, daySamples) in byDay where day >= start {
            let bySource = Dictionary(grouping: daySamples) { $0.sourceRevision.source.bundleIdentifier }
            func rank(_ list: [HKCategorySample]) -> (Double, Double) {
                let staged = list.filter { stageValues.contains($0.value) }
                    .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let total = list.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                return (staged, total)
            }
            guard let best = bySource.values.max(by: { rank($0) < rank($1) }) else { continue }

            var parts = SleepParts()
            for sample in best {
                let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .asleepDeep: parts.deep += hours
                case .asleepREM:  parts.rem += hours
                default:          parts.light += hours
                }
            }
            out[day] = parts
        }
        return out
    }

    /// One value per day: the daily average (HRV, resting HR) or daily total (steps, exercise).
    private func dailyStats(_ id: HKQuantityTypeIdentifier, unit: HKUnit, sum: Bool,
                            start: Date, end: Date) async -> [Date: Double] {
        let type = HKQuantityType(id)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: sum ? .cumulativeSum : .discreteAverage,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: health) else { return [:] }
        var out: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            let q = sum ? stats.sumQuantity() : stats.averageQuantity()
            if let q { out[self.cal.startOfDay(for: stats.startDate)] = q.doubleValue(for: unit) }
        }
        return out
    }

    // MARK: Scoring

    static func sleepScore(_ d: EnergyDay) -> Int? {
        guard d.hasSleep else { return nil }
        let hours = d.sleepHours
        let durationRatio = min(max((hours - 4) / 4, 0), 1)       // 4h = 0, 8h+ = full
        if !d.hasStages {
            return clamp(Int((durationRatio * 100).rounded()))
        }
        let duration = durationRatio * 60
        let deep = min((d.deep / hours) / 0.15, 1) * 20     // 15%+ deep sleep = full marks
        let rem  = min((d.rem / hours) / 0.20, 1) * 20      // 20%+ REM = full marks
        return clamp(Int((duration + deep + rem).rounded()))
    }

    static func median(_ values: [Double]) -> Double? {
        guard values.count >= 5 else { return nil }          // need a few days to trust it
        let s = values.sorted()
        return s.count.isMultiple(of: 2) ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
    }

    static func clamp(_ v: Int) -> Int { min(max(v, 0), 100) }

    static func weighted(_ parts: [(Int?, Double)]) -> Int? {
        let available = parts.compactMap { p in p.0.map { (Double($0), p.1) } }
        let w = available.reduce(0) { $0 + $1.1 }
        guard w > 0 else { return nil }
        return Int((available.reduce(0) { $0 + $1.0 * $1.1 } / w).rounded())
    }

    static func computeScores(for days: [EnergyDay],
                              ouraReadiness: [Date: Int] = [:],
                              ouraSleep: [Date: Int] = [:],
                              ouraHRV: [Date: Int] = [:]) -> [Date: EnergyScore] {
        var out: [Date: EnergyScore] = [:]
        for (i, d) in days.enumerated() {
            let prior = days[max(0, i - 28)..<i]
            let hrvBase = median(prior.compactMap(\.hrv))
            let rhrBase = median(prior.compactMap(\.rhr))

            var s = EnergyScore()
            s.sleep = sleepScore(d)
            if let v = d.hrv, let b = hrvBase, b > 0 {
                s.hrv = clamp(Int((80 + (v / b - 1) * 200).rounded()))   // at baseline = 80, ±10% = ±20
            }
            if let v = d.rhr, let b = rhrBase {
                s.rhr = clamp(Int((80 - (v - b) * 5).rounded()))     // each bpm above baseline −5
            }
            if let o = ouraSleep[d.date] { s.sleep = o; s.sleepFromOura = true }
            // Oura's HRV balance is measured by the ring that also makes the readiness score,
            // so prefer it over the Apple Health HRV estimate when it's available.
            if let o = ouraHRV[d.date] { s.hrv = o; s.hrvFromOura = true }
            if let o = ouraReadiness[d.date] {
                s.readiness = o; s.readinessFromOura = true
            } else {
                s.readiness = weighted([(s.hrv, 0.4), (s.rhr, 0.3), (s.sleep, 0.3)])
            }
            s.energy = weighted([(s.readiness, 0.5), (s.sleep, 0.3), (s.hrv, 0.2)])
            out[d.date] = s
        }
        return out
    }
}

// MARK: - Today card

struct EnergyCard: View {
    @StateObject private var store = EnergyStore()

    var body: some View {
        NavigationLink {
            EnergyDetailView(store: store)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                if let latest = store.latestScored, let energy = latest.score.energy {
                    let level = EnergyLevel(energy)
                    HStack(alignment: .center, spacing: 14) {
                        let mood = store.mood(for: latest.day, score: latest.score)
                        VStack(spacing: 4) {
                            MushroomView(mood: mood)
                                .frame(width: 84, height: 84)
                            Text(mood.label)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(mood.accent)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(width: 84)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isToday(latest.day.date) ? "TODAY'S ENERGY" : "LATEST ENERGY")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(energy)")
                                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                                Text("/ 100")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(level.color).frame(width: 9, height: 9)
                                Text(level.title).font(.subheadline).fontWeight(.semibold)
                            }
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 8) {
                            if let battery = store.ringBattery { RingBatteryBadge(battery: battery) }
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                    Text(level.advice)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    EnergyStrip(store: store, count: 14)
                } else if store.isLoading || !store.hasLoaded {
                    HStack { ProgressView(); Text("Reading Apple Health…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Energy score", systemImage: "bolt.heart").font(.headline)
                        Text(store.message ?? "Wear your watch or ring to bed tonight. Your first energy score appears tomorrow morning.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .task { await store.load() }
    }

    private func isToday(_ d: Date) -> Bool { Calendar.current.isDateInToday(d) }
}

// MARK: - 14-day strip

struct EnergyStrip: View {
    @ObservedObject var store: EnergyStore
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last \(count) days").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                ForEach([EnergyLevel.high, .mid, .low], id: \.title) { l in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1.5).fill(l.color).frame(width: 7, height: 7)
                        Text(l == .high ? "High" : l == .mid ? "Mid" : "Low")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 3) {
                ForEach(store.lastDays(count)) { d in
                    let e = store.scores[d.date]?.energy
                    RoundedRectangle(cornerRadius: 3)
                        .fill(e.map { EnergyLevel($0).color } ?? Color(.tertiarySystemFill))
                        .frame(height: 18)
                        .overlay {
                            if Calendar.current.isDateInToday(d.date) {
                                RoundedRectangle(cornerRadius: 3).stroke(Color.primary, lineWidth: 1.5)
                            }
                        }
                }
            }
        }
    }
}

// MARK: - Detail

struct EnergyDetailView: View {
    @ObservedObject var store: EnergyStore
    @ObservedObject private var oura = OuraService.shared
    @State private var sleepRange = 14
    @State private var showOuraSetup = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = store.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                heroCard
                ouraSection
                metricsGrid
                workoutsSection
                sleepChart
                explainer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Energy")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load() }
        .sheet(isPresented: $showOuraSetup, onDismiss: { Task { await store.load() } }) {
            OuraSetupView()
        }
    }

    // MARK: Hero + breakdown

    @ViewBuilder private var heroCard: some View {
        if let latest = store.latestScored, let energy = latest.score.energy {
            let level = EnergyLevel(energy)
            let s = latest.score
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(spacing: 6) {
                        let mood = store.mood(for: latest.day, score: latest.score)
                        MushroomView(mood: mood).frame(width: 110, height: 110)
                        Text(mood.label.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(mood.accent)
                            .tracking(1.2)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: 110)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(latest.day.date.formatted(.dateTime.month().day().weekday()))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(energy)").font(.system(size: 52, weight: .bold, design: .monospaced))
                            Text("/ 100").font(.system(size: 14, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(level.color).frame(width: 9, height: 9)
                            Text(level.title).font(.subheadline).fontWeight(.semibold)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text(level.advice).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    BreakdownBar(label: "Readiness", weight: "×0.5", value: s.readiness, color: level.color,
                                 source: s.readinessFromOura ? "OURA" : nil)
                    BreakdownBar(label: "Sleep score", weight: "×0.3", value: s.sleep, color: level.color,
                                 source: s.sleepFromOura ? "OURA" : nil)
                    BreakdownBar(label: s.hrvFromOura ? "HRV balance" : "HRV vs baseline", weight: "×0.2",
                                 value: s.hrv, color: level.color, source: s.hrvFromOura ? "OURA" : nil)
                }
                Text(s.hrvFromOura
                     ? "HRV balance from Oura · 85+ optimal · 70–84 good · under 70 needs attention"
                     : "HRV baseline = median of the previous 28 days · 85+ high · 70–84 normal · under 70 low")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)

                Divider()
                EnergyStrip(store: store, count: 14)
            }
            .energyCardStyle()
        }
    }

    // MARK: Oura

    @ViewBuilder private var ouraSection: some View {
        if oura.isConnected {
            let latestDay = store.latestScored?.day.date ?? Calendar.current.startOfDay(for: Date())
            let details = store.ouraDetails(for: latestDay)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Oura Readiness", systemImage: "circle.circle")
                        .font(.headline)
                    Spacer()
                    if let battery = store.ringBattery { RingBatteryBadge(battery: battery) }
                    Button { showOuraSetup = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if let err = store.ouraError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                if let battery = store.ringBattery {
                    RingBatteryLine(battery: battery)
                }
                if let details, let contributors = details.contributors {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(details.score.map(String.init) ?? "—")
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                        Text("readiness").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let t = details.temperatureDeviation {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "%+.1f°C", t))
                                    .font(.system(.subheadline, design: .monospaced)).fontWeight(.semibold)
                                    .foregroundStyle(abs(t) >= 0.5 ? Color.orange : Color.primary)
                                Text("body temp").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(spacing: 10) {
                        ForEach(contributors.list, id: \.0) { name, value in
                            BreakdownBar(label: name, weight: "", value: value, color: contributorColor(value))
                        }
                    }
                    Text("Oura rates each factor 1–100. 85+ is optimal, 70–84 good, under 70 needs attention.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if store.ouraError == nil {
                    Text("No Oura readiness for this day yet. It usually appears after the ring syncs in the morning. Open the Oura app, then pull down here to refresh.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .energyCardStyle()
        } else {
            Button { showOuraSetup = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "circle.circle")
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect Oura").font(.subheadline).fontWeight(.semibold)
                        Text("Use your ring's real Readiness and Sleep scores")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
                .energyCardStyle()
            }
            .buttonStyle(.plain)
        }
    }

    private func contributorColor(_ v: Int?) -> Color {
        guard let v else { return .gray }
        if v >= 85 { return EnergyLevel.high.color }
        if v >= 70 { return EnergyLevel.mid.color }
        return EnergyLevel.low.color
    }

    // MARK: Metric tiles

    private var metricsGrid: some View {
        let recent = store.lastDays(7)
        let previous = Array(store.days.dropLast(7).suffix(28))

        func avg(_ v: [Double?]) -> Double? {
            let x = v.compactMap { $0 }
            return x.isEmpty ? nil : x.reduce(0, +) / Double(x.count)
        }
        func readiness(_ list: [EnergyDay]) -> [Double?] {
            list.map { store.scores[$0.date]?.readiness.map(Double.init) }
        }
        func sleep(_ list: [EnergyDay]) -> [Double?] { list.map { $0.hasSleep ? $0.sleepHours : nil } }

        let tiles: [MetricTileData] = [
            .init(title: "Sleep", unit: "h", format: "%.1f", higherIsBetter: true,
                  now: avg(sleep(recent)), before: avg(sleep(previous)), spark: sleep(recent)),
            .init(title: "HRV", unit: "ms", format: "%.0f", higherIsBetter: true,
                  now: avg(recent.map(\.hrv)), before: avg(previous.map(\.hrv)), spark: recent.map(\.hrv)),
            .init(title: "Resting HR", unit: "bpm", format: "%.0f", higherIsBetter: false,
                  now: avg(recent.map(\.rhr)), before: avg(previous.map(\.rhr)), spark: recent.map(\.rhr)),
            .init(title: "Readiness", unit: "", format: "%.0f", higherIsBetter: true,
                  now: avg(readiness(recent)), before: avg(readiness(previous)), spark: readiness(recent)),
            .init(title: "Steps", unit: "", format: "steps", higherIsBetter: true,
                  now: avg(recent.map(\.steps)), before: avg(previous.map(\.steps)), spark: recent.map(\.steps)),
            .init(title: "Active", unit: "min", format: "%.0f", higherIsBetter: true,
                  now: avg(recent.map(\.activeMinutes)), before: avg(previous.map(\.activeMinutes)),
                  spark: recent.map(\.activeMinutes)),
        ]

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(tiles) { MetricTile(data: $0) }
        }
    }

    // MARK: Workouts

    private var workoutsSection: some View {
        let week = store.recentWorkouts(days: 7)
        let minutes = week.reduce(0) { $0 + $1.minutes }
        let kcal = week.compactMap(\.kcal).reduce(0, +)
        let list = Array(store.workouts.prefix(10))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workouts").font(.headline)
                    Text("From Apple Health").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(minutes.rounded())) min").font(.system(.title3, design: .monospaced)).fontWeight(.semibold)
                    Text("\(week.count) workout\(week.count == 1 ? "" : "s") · \(Int(kcal)) kcal this week")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if list.isEmpty {
                Text("No workouts in the last 30 days. Workouts you record on Apple Watch, Oura or apps like Strava appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(list) { w in
                    HStack(spacing: 12) {
                        Image(systemName: w.icon)
                            .font(.body)
                            .foregroundStyle(.orange)
                            .frame(width: 34, height: 34)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(.subheadline).fontWeight(.medium)
                            Text(w.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(w.minutes.rounded())) min").font(.subheadline).fontWeight(.semibold)
                            Text([w.kcal.map { "\(Int($0)) kcal" },
                                  w.avgHeartRate.map { "\(Int($0)) bpm" },
                                  w.distanceKm.flatMap { $0 > 0.05 ? String(format: "%.1f km", $0) : nil }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .energyCardStyle()
    }

    // MARK: Sleep chart

    private var sleepChart: some View {
        let nights = store.lastDays(sleepRange)
        let slept = nights.filter(\.hasSleep)
        let average = slept.isEmpty ? 0 : slept.map(\.sleepHours).reduce(0, +) / Double(slept.count)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Did you sleep?").font(.headline)
                    Text("Deep / REM / Light, in hours. Dated by the morning you woke up.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1fh", average)).font(.system(.title3, design: .monospaced)).fontWeight(.semibold)
                    Text("average").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Picker("Range", selection: $sleepRange) {
                Text("7D").tag(7); Text("14D").tag(14); Text("30D").tag(30)
            }
            .pickerStyle(.segmented)

            Chart {
                ForEach(nights) { d in
                    BarMark(x: .value("Night", d.date, unit: .day), y: .value("Hours", d.deep))
                        .foregroundStyle(by: .value("Stage", "Deep"))
                    BarMark(x: .value("Night", d.date, unit: .day), y: .value("Hours", d.rem))
                        .foregroundStyle(by: .value("Stage", "REM"))
                    BarMark(x: .value("Night", d.date, unit: .day), y: .value("Hours", d.light))
                        .foregroundStyle(by: .value("Stage", "Light"))
                }
                RuleMark(y: .value("Goal", 8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartForegroundStyleScale([
                "Deep":  Color(red: 0.16, green: 0.30, blue: 0.62),
                "REM":   Color(red: 0.32, green: 0.52, blue: 0.88),
                "Light": Color(red: 0.66, green: 0.77, blue: 0.95),
            ])
            .chartYScale(domain: 0...10)
            .chartYAxis { AxisMarks(values: [0, 4, 8]) { v in
                AxisGridLine(); AxisValueLabel { if let h = v.as(Int.self) { Text("\(h)h") } }
            } }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: sleepRange > 14 ? 7 : 2)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            } }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 220)
        }
        .energyCardStyle()
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How it's calculated").font(.subheadline).fontWeight(.semibold)
            Group {
                Text("• Energy = Readiness × 0.5 + Sleep × 0.3 + HRV vs baseline × 0.2")
                Text("• Readiness = HRV × 0.4 + Resting HR × 0.3 + Sleep × 0.3")
                Text("• Sleep score: 8h+ of sleep, 15%+ deep and 20%+ REM gives 100. Under 4h counts as no rest")
                Text("• HRV at your baseline = 80; every 10% above or below moves it 20 points")
                Text("• Baselines use your previous 28 days, so scores settle after about a week of wearing your device")
                Text("• Cards compare your 7-day average with the 4 weeks before")
                Text("• With Oura connected, Readiness, Sleep and HRV use Oura's own scores (marked OURA)")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .energyCardStyle()
    }
}

// MARK: - Pieces

// MARK: - Ring battery

/// Small pill: battery icon + percentage. Red at 20% or below, green while charging.
struct RingBatteryBadge: View {
    let battery: OuraBattery
    private var color: Color {
        if battery.isCharging { return .green }
        return battery.level <= 20 ? .red : .secondary
    }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.circle").font(.system(size: 9, weight: .semibold))
            Image(systemName: battery.symbol).font(.system(size: 12))
            Text("\(battery.level)%").font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Oura ring battery \(battery.level) percent\(battery.isCharging ? ", charging" : "")")
    }
}

/// One-line explanation under the Oura card, with how fresh the reading is.
private struct RingBatteryLine: View {
    let battery: OuraBattery
    var body: some View {
        let status: String = {
            if battery.isCharging { return "charging" }
            if battery.level <= 20 { return "time to charge" }
            return "battery"
        }()
        HStack(spacing: 6) {
            Image(systemName: battery.symbol)
                .foregroundStyle(battery.isCharging ? Color.green : (battery.level <= 20 ? Color.red : Color.secondary))
            Text("Ring \(battery.level)% · \(status)")
                .font(.caption).fontWeight(.medium)
            Spacer()
            if let d = battery.date {
                Text("updated \(d.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct BreakdownBar: View {
    let label: String; let weight: String; let value: Int?; let color: Color; var source: String? = nil
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.caption)
                Text(weight).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                if let source {
                    Text(source)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                Text(value.map(String.init) ?? "—").font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(color).frame(width: g.size.width * CGFloat(value ?? 0) / 100)
                }
            }
            .frame(height: 5)
        }
    }
}

struct MetricTileData: Identifiable {
    let title: String
    let unit: String
    let format: String          // printf format, or "steps" for grouped thousands
    let higherIsBetter: Bool
    let now: Double?
    let before: Double?
    let spark: [Double?]
    var id: String { title }

    func text(_ v: Double) -> String {
        format == "steps" ? Int(v.rounded()).formatted(.number) : String(format: format, v)
    }
}

private struct MetricTile: View {
    let data: MetricTileData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(data.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("7D").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(data.now.map(data.text) ?? "—")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.6).lineLimit(1)
                if !data.unit.isEmpty {
                    Text(data.unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let now = data.now, let before = data.before {
                let diff = now - before
                let good = (diff >= 0) == data.higherIsBetter
                Text("\(diff >= 0 ? "↑" : "↓") \(data.text(abs(diff))) vs 4 wks")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(abs(diff) < 0.05 ? Color.secondary : (good ? Color.green : Color.orange))
            } else {
                Text("building baseline…").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Sparkline(values: data.spark).frame(height: 28)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct Sparkline: View {
    let values: [Double?]
    var body: some View {
        let points = values.enumerated().compactMap { i, v in v.map { (i, $0) } }
        if points.count >= 2 {
            Chart(points, id: \.0) { p in
                LineMark(x: .value("Day", p.0), y: .value("Value", p.1))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.blue)
                AreaMark(x: .value("Day", p.0), y: .value("Value", p.1))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
        } else {
            Color.clear
        }
    }
}

/// Your energy mood for the day, shown by the mushroom. Picked from your data.
enum BuddyMood: String, CaseIterable {
    case energized, happy, active, steady, tired, shortSleep, stressed, warm, exhausted

    var label: String {
        switch self {
        case .energized: return "Bursting with energy"
        case .happy: return "Feeling good"
        case .active: return "Active day"
        case .steady: return "Steady"
        case .tired: return "A bit tired"
        case .shortSleep: return "Short on sleep"
        case .stressed: return "Under stress"
        case .warm: return "Running warm"
        case .exhausted: return "Needs rest"
        }
    }

    /// Background tint behind the buddy.
    var tint: Color {
        switch self {
        case .energized, .happy, .active: return EnergyLevel.high.color.opacity(0.14)
        case .steady:                     return EnergyLevel.mid.color.opacity(0.14)
        case .shortSleep:                 return Color.purple.opacity(0.12)
        case .warm:                       return Color.red.opacity(0.12)
        case .tired, .stressed, .exhausted: return EnergyLevel.low.color.opacity(0.14)
        }
    }

    /// Text colour for the mood label.
    var accent: Color {
        switch self {
        case .energized, .happy, .active: return EnergyLevel.high.color
        case .steady:                     return EnergyLevel.mid.color
        case .shortSleep:                 return .purple
        case .warm:                       return .red
        case .tired, .stressed, .exhausted: return EnergyLevel.low.color
        }
    }
}

/// A little toadstool that shows your energy without a face: a bright upright cap
/// (with a baby mushroom) on good days, a pale tilted cap when tired, and a slumped,
/// faded cap when you need rest. Drawn on a 100 × 100 grid and scaled to fit.
struct MushroomView: View {
    let mood: BuddyMood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Effect { case nothing, sparkle, dew, heat, z, zzz }

    private struct Look {
        let cap: Color
        let stem: Color
        let tilt: Double          // degrees the cap leans
        let capScale: Double
        let baby: Bool            // little mushroom friend
        let glow: Bool
        let bow: Bool
        let effect: Effect
    }

    private static func hex(_ v: UInt32, _ opacity: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: opacity)
    }

    private var look: Look {
        let red = Self.hex(0xFF6F6F), stem = Self.hex(0xFFF4E6)
        let pale = Self.hex(0xF09A8E)
        switch mood {
        case .energized:  return Look(cap: red, stem: stem, tilt: 0, capScale: 1.06, baby: true, glow: true, bow: false, effect: .sparkle)
        case .happy:      return Look(cap: red, stem: stem, tilt: 0, capScale: 1, baby: true, glow: false, bow: false, effect: .nothing)
        case .active:     return Look(cap: red, stem: stem, tilt: 0, capScale: 1, baby: false, glow: false, bow: true, effect: .nothing)
        case .steady:     return Look(cap: red, stem: stem, tilt: 0, capScale: 1, baby: false, glow: false, bow: false, effect: .nothing)
        case .tired:      return Look(cap: pale, stem: stem, tilt: 10, capScale: 1, baby: false, glow: false, bow: false, effect: .nothing)
        case .shortSleep: return Look(cap: pale, stem: stem, tilt: 14, capScale: 1, baby: false, glow: false, bow: false, effect: .z)
        case .stressed:   return Look(cap: red, stem: stem, tilt: 0, capScale: 1, baby: false, glow: false, bow: false, effect: .dew)
        case .warm:       return Look(cap: Self.hex(0xFF5A3C), stem: stem, tilt: 0, capScale: 1, baby: false, glow: false, bow: false, effect: .heat)
        case .exhausted:  return Look(cap: Self.hex(0xC9A396), stem: Self.hex(0xEFE3D2), tilt: 24, capScale: 0.92, baby: false, glow: false, bow: false, effect: .zzz)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in draw(&ctx, size: size, t: t) }
        }
        .background(mood.tint)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Mushroom: \(mood.label)")
    }

    // MARK: Motion

    /// Sideways shake, hop height, squash (sx, sy) at the base, and extra cap wobble in degrees.
    private func motion(_ t: Double) -> (dx: Double, dy: Double, sx: Double, sy: Double, wobble: Double) {
        switch mood {
        case .energized:
            let h = abs(sin(t * 3.4))
            let land = max(0, 0.2 - h) * 0.4                        // squish on landing
            return (0, -h * 5, 1 + land, 1 - land, sin(t * 3.4) * 3)
        case .active:
            let h = abs(sin(t * 4.2))
            return (0, -h * 3, 1, 1, sin(t * 4.2) * 2)
        case .happy:      return (0, 0, 1 - sin(t * 2) * 0.015, 1 + sin(t * 2) * 0.03, sin(t * 1.6) * 2)
        case .steady:     return (0, 0, 1 - sin(t * 1.5) * 0.01, 1 + sin(t * 1.5) * 0.02, sin(t * 1.2) * 1.2)
        case .tired, .shortSleep: return (0, 0, 1, 1 + sin(t * 0.9) * 0.015, sin(t * 0.8) * 2)
        case .stressed:   return (sin(t * 26) * 0.7, 0, 1, 1, sin(t * 26) * 1)   // nervous tremble
        case .warm:       return (0, 0, 1, 1 + sin(t * 1.3) * 0.02, sin(t * 1.0) * 1.5)
        case .exhausted:  return (0, 0, 1, 1 + sin(t * 0.7) * 0.012, sin(t * 0.6) * 1.5)
        }
    }

    // MARK: Drawing

    private func draw(_ base: inout GraphicsContext, size: CGSize, t: Double) {
        let s = min(size.width, size.height) / 100
        base.translateBy(x: (size.width - 100 * s) / 2, y: (size.height - 100 * s) / 2)
        base.scaleBy(x: s, y: s)

        let look = self.look
        let m = motion(t)

        // Soft glow behind on high-energy days
        if look.glow {
            let pulse = 1 + sin(t * 2.2) * 0.05
            let glow = Path(ellipseIn: CGRect(x: 50 - 42 * pulse, y: 52 - 36 * pulse, width: 84 * pulse, height: 72 * pulse))
            base.fill(glow, with: .color(Self.hex(0xFFF3B0, 0.5)))
        }

        // Heat waves
        if look.effect == .heat {
            for (k, x) in [36.0, 50.0, 64.0].enumerated() {
                let p = (t * 0.6 + Double(k) * 0.33).truncatingRemainder(dividingBy: 1)
                let wobble = sin(t * 4 + Double(k)) * 1.2
                let y0 = 20 - p * 8
                var wave = Path()
                wave.move(to: CGPoint(x: x + wobble, y: y0))
                wave.addQuadCurve(to: CGPoint(x: x + wobble, y: y0 - 8), control: CGPoint(x: x + 3 + wobble, y: y0 - 4))
                wave.addQuadCurve(to: CGPoint(x: x + wobble, y: y0 - 16), control: CGPoint(x: x - 3 + wobble, y: y0 - 12))
                base.stroke(wave, with: .color(Self.hex(0xFF6B5A, sin(p * .pi))),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        }

        // Ground shadow shrinks while hopping
        let shadowScale = 1 + m.dy / 20
        base.fill(Path(ellipseIn: CGRect(x: 50 - 24 * shadowScale, y: 90, width: 48 * shadowScale, height: 6)),
                  with: .color(.black.opacity(0.07)))

        // Little friend beside it
        if look.baby { drawBaby(&base, look: look, t: t) }

        // Main mushroom: hop + squash around the base
        var ctx = base
        ctx.translateBy(x: 50 + m.dx, y: 92 + m.dy)
        ctx.scaleBy(x: m.sx, y: m.sy)
        ctx.translateBy(x: -50, y: -92)

        // Stem
        var stem = Path()
        stem.move(to: CGPoint(x: 40, y: 56))
        stem.addQuadCurve(to: CGPoint(x: 41, y: 92), control: CGPoint(x: 37, y: 88))
        stem.addLine(to: CGPoint(x: 59, y: 92))
        stem.addQuadCurve(to: CGPoint(x: 60, y: 56), control: CGPoint(x: 63, y: 88))
        stem.closeSubpath()
        ctx.fill(stem, with: .color(look.stem))
        ctx.stroke(stem, with: .color(Self.hex(0xE9D6BE)), lineWidth: 1.4)
        var ring = Path()
        ring.move(to: CGPoint(x: 41, y: 58))
        ring.addQuadCurve(to: CGPoint(x: 59, y: 58), control: CGPoint(x: 50, y: 62))
        ctx.stroke(ring, with: .color(Self.hex(0xE9D6BE)), lineWidth: 1.2)

        if look.bow { drawBow(&ctx, at: CGPoint(x: 50, y: 74), t: t) }

        // Cap leans (tilt + wobble) around the top of the stem
        var cap = ctx
        cap.translateBy(x: 50, y: 56)
        cap.rotate(by: .degrees(look.tilt + m.wobble))
        cap.scaleBy(x: look.capScale, y: look.capScale)
        cap.translateBy(x: -50, y: -56)

        var dome = Path()
        dome.move(to: CGPoint(x: 14, y: 56))
        dome.addQuadCurve(to: CGPoint(x: 50, y: 22), control: CGPoint(x: 16, y: 22))
        dome.addQuadCurve(to: CGPoint(x: 86, y: 56), control: CGPoint(x: 84, y: 22))
        dome.addQuadCurve(to: CGPoint(x: 14, y: 56), control: CGPoint(x: 50, y: 63))
        dome.closeSubpath()
        cap.fill(dome, with: .color(look.cap))
        let spots: [(Double, Double, Double)] = [(32, 40, 5.5), (52, 32, 4.5), (68, 42, 6), (44, 50, 3.5), (76, 52, 2.8)]
        for spot in spots {
            cap.fill(Path(ellipseIn: CGRect(x: spot.0 - spot.2, y: spot.1 - spot.2, width: spot.2 * 2, height: spot.2 * 2)),
                     with: .color(.white.opacity(0.95)))
        }
        let shine = Path(ellipseIn: CGRect(x: 23, y: 28, width: 14, height: 6))
            .applying(CGAffineTransform(translationX: 30, y: 31).rotated(by: -.pi * 25 / 180).translatedBy(x: -30, y: -31))
        cap.fill(shine, with: .color(.white.opacity(0.3)))

        // Effects
        switch look.effect {
        case .sparkle:
            let stars: [(Double, Double, Double)] = [(12, 18, 5), (88, 16, 6), (86, 74, 4.5), (14, 70, 4)]
            for (i, star) in stars.enumerated() {
                let a = (sin(t * 3 + Double(i) * 1.7) + 1) / 2
                base.fill(starPath(cx: star.0, cy: star.1, r: star.2 * (0.6 + 0.4 * a)),
                          with: .color(Self.hex(0xFFD23F, 0.35 + 0.65 * a)))
            }
        case .dew:
            // A drop slips off the edge of the cap and falls
            let p = (t / 1.8).truncatingRemainder(dividingBy: 1)
            let dy = p * 24
            let alpha = p < 0.7 ? 1 : (1 - p) / 0.3
            var drop = Path()
            drop.move(to: CGPoint(x: 86, y: 56 + dy))
            drop.addQuadCurve(to: CGPoint(x: 86, y: 68 + dy), control: CGPoint(x: 91, y: 64 + dy))
            drop.addQuadCurve(to: CGPoint(x: 86, y: 56 + dy), control: CGPoint(x: 81, y: 64 + dy))
            base.fill(drop, with: .color(Self.hex(0x6EC1FF, alpha)))
        case .z, .zzz:
            let count = look.effect == .z ? 1 : 3
            for k in 0..<count {
                let p = (t / 2.6 + Double(k) / Double(count)).truncatingRemainder(dividingBy: 1)
                let text = Text("z")
                    .font(.system(size: 7 + p * 7, weight: .heavy, design: .rounded))
                    .foregroundStyle(Self.hex(0x7B76A8, sin(p * .pi)))
                base.draw(text, at: CGPoint(x: 70 + p * 12, y: 30 - p * 22))
            }
        case .heat, .nothing:
            break
        }
    }

    private func drawBaby(_ ctx: inout GraphicsContext, look: Look, t: Double) {
        var c = ctx
        let bob = abs(sin(t * 3 + 1.2)) * (mood == .energized ? 3 : 1.5)
        c.translateBy(x: 0, y: -bob)
        var stem = Path()
        stem.move(to: CGPoint(x: 77, y: 80))
        stem.addQuadCurve(to: CGPoint(x: 78, y: 92), control: CGPoint(x: 76, y: 90))
        stem.addLine(to: CGPoint(x: 84, y: 92))
        stem.addQuadCurve(to: CGPoint(x: 85, y: 80), control: CGPoint(x: 86, y: 90))
        stem.closeSubpath()
        c.fill(stem, with: .color(look.stem))
        c.stroke(stem, with: .color(Self.hex(0xE9D6BE)), lineWidth: 1)
        var cap = Path()
        cap.move(to: CGPoint(x: 71, y: 81))
        cap.addQuadCurve(to: CGPoint(x: 81, y: 70), control: CGPoint(x: 72, y: 70))
        cap.addQuadCurve(to: CGPoint(x: 91, y: 81), control: CGPoint(x: 90, y: 70))
        cap.addQuadCurve(to: CGPoint(x: 71, y: 81), control: CGPoint(x: 81, y: 84))
        cap.closeSubpath()
        c.fill(cap, with: .color(look.cap))
        c.fill(Path(ellipseIn: CGRect(x: 76.2, y: 73.2, width: 3.6, height: 3.6)), with: .color(.white))
        c.fill(Path(ellipseIn: CGRect(x: 83.6, y: 75.6, width: 2.8, height: 2.8)), with: .color(.white))
    }

    private func drawBow(_ ctx: inout GraphicsContext, at p: CGPoint, t: Double) {
        let red = Self.hex(0xFF5A5F)
        let flap = sin(t * 8) * 1.2
        var bow = Path()
        bow.move(to: p); bow.addLine(to: CGPoint(x: p.x - 8, y: p.y - 5 - flap)); bow.addLine(to: CGPoint(x: p.x - 8, y: p.y + 5 + flap)); bow.closeSubpath()
        bow.move(to: p); bow.addLine(to: CGPoint(x: p.x + 8, y: p.y - 5 + flap)); bow.addLine(to: CGPoint(x: p.x + 8, y: p.y + 5 - flap)); bow.closeSubpath()
        ctx.fill(bow, with: .color(red))
        var tails = Path()
        tails.move(to: CGPoint(x: p.x, y: p.y + 1)); tails.addLine(to: CGPoint(x: p.x - 4 - flap, y: p.y + 10))
        tails.move(to: CGPoint(x: p.x, y: p.y + 1)); tails.addLine(to: CGPoint(x: p.x + 4 + flap, y: p.y + 10))
        ctx.stroke(tails, with: .color(red), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.4, y: p.y - 2.4, width: 4.8, height: 4.8)), with: .color(Self.hex(0xE0474C)))
    }

    private func starPath(cx: Double, cy: Double, r: Double) -> Path {
        let k = r * 0.32
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + k, y: cy - k))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx + k, y: cy + k))
        p.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx - k, y: cy + k))
        p.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx - k, y: cy - k))
        p.closeSubpath()
        return p
    }
}

private extension View {
    func energyCardStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
