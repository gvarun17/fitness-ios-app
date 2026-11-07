import FitnessCore
import Foundation
import HealthKit

/// Reads everything the app needs from Apple Health. Read-only: the app never
/// writes to Apple Health, and nothing leaves the phone.
final class HealthKitService {
    let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let quantities: [HKQuantityTypeIdentifier] = [
        .stepCount, .restingHeartRate, .heartRateVariabilitySDNN, .activeEnergyBurned, .appleExerciseTime,
        .heartRate, .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .runningStrideLength,
    ]

    var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = Set(quantities.map { HKQuantityType($0) })
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Everything from `days` days ago until now
    func load(days: Int = 400, calendar: Calendar = .current) async throws -> HealthData {
        let now = Date()
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -days, to: now)!)
        async let steps = daily(.stepCount, .count(), .cumulativeSum, from: start)
        async let energy = daily(.activeEnergyBurned, .kilocalorie(), .cumulativeSum, from: start)
        async let exercise = daily(.appleExerciseTime, .minute(), .cumulativeSum, from: start)
        async let rhr = daily(.restingHeartRate, .count().unitDivided(by: .minute()), .discreteAverage, from: start)
        async let hrv = daily(.heartRateVariabilitySDNN, .secondUnit(with: .milli), .discreteAverage, from: start)
        async let nights = sleep(from: start, calendar: calendar)
        async let workouts = workouts(from: start, calendar: calendar)

        let (st, en, ex, rh, hv) = try await (steps, energy, exercise, rhr, hrv)
        let keys = Set(st.keys).union(en.keys).union(ex.keys).union(rh.keys).union(hv.keys)
        let summaries = keys.map { d in
            DaySummary(day: d, steps: st[d].map { Int($0.rounded()) }, restingHR: rh[d], hrv: hv[d],
                       activeKcal: en[d], exerciseMinutes: ex[d])
        }
        return HealthData(days: summaries, nights: try await nights, workouts: try await workouts)
    }

    // MARK: - Daily totals and averages

    private func daily(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ options: HKStatisticsOptions,
                       from start: Date) async throws -> [Day: Double] {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: options, anchorDate: start, intervalComponents: DateComponents(day: 1))
        let collection = try await query.result(for: store)
        var out: [Day: Double] = [:]
        collection.enumerateStatistics(from: start, to: Date()) { stats, _ in
            let q = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
            if let v = q?.doubleValue(for: unit), v > 0 { out[Day(date: stats.startDate)] = v }
        }
        return out
    }

    // MARK: - Sleep

    /// Sleep stages grouped into nights, filed under the day you woke up. When
    /// several apps record the same night (a watch and the phone, say), the one
    /// with the most sleep is used, so nights aren't counted twice.
    private func sleep(from start: Date, calendar: Calendar) async throws -> [SleepNight] {
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await query.result(for: store)
        // night key: the day of (end + 6h), so 23:30 and 06:00 belong to the same night
        var groups: [Day: [String: [HKCategorySample]]] = [:]
        for s in samples {
            let key = Day(date: s.endDate.addingTimeInterval(6 * 3600), calendar: calendar)
            groups[key, default: [:]][s.sourceRevision.source.bundleIdentifier, default: []].append(s)
        }
        return groups.compactMap { day, bySource in
            let nights = bySource.values.map { Self.night(day, $0, calendar: calendar) }
            return nights.max { $0.asleepHours < $1.asleepHours }.flatMap { $0.asleepHours > 0 ? $0 : nil }
        }
    }

    static func night(_ day: Day, _ samples: [HKCategorySample], calendar: Calendar) -> SleepNight {
        var deep = 0.0, rem = 0.0, core = 0.0, unspecified = 0.0, awake = 0.0
        var first: Date?, last: Date?
        for s in samples {
            let h = s.endDate.timeIntervalSince(s.startDate) / 3600
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .asleepDeep: deep += h
            case .asleepREM: rem += h
            case .asleepCore: core += h
            case .asleepUnspecified: unspecified += h
            case .awake: awake += h
            default: continue                        // "in bed" isn't sleep
            }
            if s.value != HKCategoryValueSleepAnalysis.awake.rawValue {
                first = min(first ?? s.startDate, s.startDate)
                last = max(last ?? s.endDate, s.endDate)
            }
        }
        func afterSix(_ d: Date?) -> Int? {
            guard let d else { return nil }
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return ((c.hour! * 60 + c.minute!) - 18 * 60 + 1440) % 1440
        }
        return SleepNight(day: day, asleepHours: deep + rem + core + unspecified, deep: deep, rem: rem,
                          core: core + unspecified, awake: awake, bedtime: afterSix(first), wake: afterSix(last))
    }

    // MARK: - Workouts

    private func workouts(from start: Date, calendar: Calendar) async throws -> [Workout] {
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let items = try await query.result(for: store)
        var out: [Workout] = []
        for w in items {
            let sport = Self.sport(w.workoutActivityType)
            let minutes = w.duration / 60
            let distance = [HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
                .compactMap { w.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
                .max() ?? w.totalDistance?.doubleValue(for: .meter()) ?? 0
            let hr = w.statistics(for: HKQuantityType(.heartRate))
            let bpm = HKUnit.count().unitDivided(by: .minute())
            let steps = (sport == .run || sport == .walk || sport == .hike)
                ? try? await stepsDuring(w) : nil
            let indoor = (w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) == true
            out.append(Workout(
                id: w.uuid.uuidString, day: Day(date: w.startDate, calendar: calendar), start: w.startDate, sport: sport,
                name: (w.metadata?[HKMetadataKeyWorkoutBrandName] as? String) ?? (indoor ? "Indoor \(sport.name.lowercased())" : sport.name),
                km: distance / 1000, minutes: minutes,
                avgHR: hr?.averageQuantity()?.doubleValue(for: bpm), maxHR: hr?.maximumQuantity()?.doubleValue(for: bpm),
                kcal: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                cadence: steps.map { $0 / max(minutes, 1) },
                strideM: w.statistics(for: HKQuantityType(.runningStrideLength))?.averageQuantity()?.doubleValue(for: .meter())))
        }
        return out
    }

    private func stepsDuring(_ w: HKWorkout) async throws -> Double? {
        let query = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount),
                                       predicate: HKQuery.predicateForSamples(withStart: w.startDate, end: w.endDate, options: .strictStartDate)),
            options: .cumulativeSum)
        return try await query.result(for: store)?.sumQuantity()?.doubleValue(for: .count())
    }

    static func sport(_ t: HKWorkoutActivityType) -> Sport {
        switch t {
        case .running: .run
        case .walking: .walk
        case .cycling, .handCycling: .cycle
        case .swimming, .swimBikeRun: .swim
        case .hiking: .hike
        case .traditionalStrengthTraining, .functionalStrengthTraining, .highIntensityIntervalTraining,
             .coreTraining, .crossTraining, .yoga, .pilates: .strength
        default: .other
        }
    }

    // MARK: - Background updates

    /// Asks Apple Health to wake the app when new data arrives, so the widgets
    /// stay current without opening the app.
    func watchForChanges(onChange: @escaping @Sendable () async -> Void) {
        let types: [HKSampleType] = [HKQuantityType(.stepCount), HKQuantityType(.restingHeartRate),
                                     HKQuantityType(.heartRateVariabilitySDNN), HKCategoryType(.sleepAnalysis),
                                     HKObjectType.workoutType()]
        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: type == HKQuantityType(.stepCount) ? .hourly : .immediate) { _, _ in }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task {
                    await onChange()
                    completion()
                }
            }
            store.execute(query)
        }
    }
}
