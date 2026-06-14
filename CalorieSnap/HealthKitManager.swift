import SwiftUI
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    let store = HKHealthStore()

    @Published var steps: Int = 0
    @Published var distance: Double = 0
    @Published var activeCalories: Double = 0
    @Published var sleepHours: Double = 0
    @Published var sleepMinutes: Int = 0
    @Published var heartRate: Double = 0
    @Published var isAuthorized = false
    @Published var errorMessage: String? = nil

    // Period tracking
    @Published var lastPeriodStart: Date? = nil
    @Published var lastPeriodEnd: Date? = nil
    @Published var periodCycleDays: Int = 0
    @Published var periodDates: [Date] = []

    var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
        if let menstrual = HKObjectType.categoryType(forIdentifier: .menstrualFlow) {
            types.insert(menstrual)
        }
        return types
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data not available on this device"
            return
        }
        store.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.isAuthorized = true
                    self.fetchAll()
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Authorization failed"
                }
            }
        }
    }

    func fetchAll() {
        fetchSteps()
        fetchDistance()
        fetchActiveCalories()
        fetchSleep()
        fetchHeartRate()
        fetchPeriodData()
    }

    func fetchSteps() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async { self.steps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0) }
        }
        store.execute(query)
    }

    func fetchDistance() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async { self.distance = result?.sumQuantity()?.doubleValue(for: .meter()) ?? 0 }
        }
        store.execute(query)
    }

    func fetchActiveCalories() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            DispatchQueue.main.async { self.activeCalories = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0 }
        }
        store.execute(query)
    }

    func fetchSleep() {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let start = Calendar.current.startOfDay(for: yesterday)
        let end = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 30, sortDescriptors: [sort]) { _, samples, _ in
            DispatchQueue.main.async {
                let sleepSamples = samples as? [HKCategorySample] ?? []
                let asleep = sleepSamples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }
                let total = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                self.sleepHours = total / 3600
                self.sleepMinutes = Int((total / 60).truncatingRemainder(dividingBy: 60))
            }
        }
        store.execute(query)
    }

    func fetchHeartRate() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            DispatchQueue.main.async {
                let sample = samples?.first as? HKQuantitySample
                self.heartRate = sample?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? 0
            }
        }
        store.execute(query)
    }

    func fetchPeriodData() {
        guard let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else { return }
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: threeMonthsAgo, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 200, sortDescriptors: [sort]) { _, samples, _ in
            DispatchQueue.main.async {
                let periodSamples = (samples as? [HKCategorySample] ?? [])
                    .filter { $0.value != HKCategoryValueMenstrualFlow.none.rawValue }
                self.periodDates = periodSamples.map { $0.startDate }

                // Find last period start and end
                if let first = periodSamples.first {
                    self.lastPeriodStart = first.startDate
                }

                // Estimate cycle length from last two periods
                let grouped = self.groupPeriodDates(periodSamples.map { $0.startDate })
                if grouped.count >= 2 {
                    let diff = Calendar.current.dateComponents([.day], from: grouped[1], to: grouped[0]).day ?? 0
                    self.periodCycleDays = diff
                }
            }
        }
        store.execute(query)
    }

    func groupPeriodDates(_ dates: [Date]) -> [Date] {
        // Group dates that are within 2 days of each other as the same period
        var groups: [Date] = []
        var lastDate: Date? = nil
        for date in dates.sorted(by: >) {
            if let last = lastDate {
                let diff = Calendar.current.dateComponents([.day], from: date, to: last).day ?? 0
                if diff > 2 { groups.append(date) }
            } else {
                groups.append(date)
            }
            lastDate = date
        }
        return groups
    }

    var nextPeriodEstimate: Date? {
        guard let last = lastPeriodStart, periodCycleDays > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: periodCycleDays, to: last)
    }

    var daysUntilNextPeriod: Int? {
        guard let next = nextPeriodEstimate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: next).day
    }

    var isPeriodDay: Bool {
        periodDates.contains { Calendar.current.isDateInToday($0) }
    }

    func isPeriodDate(_ date: Date) -> Bool {
        periodDates.contains { Calendar.current.isDate($0, inSameDayAs: date) }
    }

    var stepsProgress: Double { min(Double(steps) / 10000.0, 1.0) }
    var distanceKm: Double { distance / 1000 }
    var sleepFormatted: String {
        if sleepHours < 1 { return "No data" }
        return "\(Int(sleepHours))h \(sleepMinutes)m"
    }
    var stepsGoalMet: Bool { steps >= 10000 }
    var sleepGoalMet: Bool { sleepHours >= 7 }
}
