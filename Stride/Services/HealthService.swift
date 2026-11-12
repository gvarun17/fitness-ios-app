import Foundation
import HealthKit
import CoreLocation
import RunCore

/// Saves runs to Apple Health and reads heart rate while running.
final class HealthService {
    static let shared = HealthService()

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Health permission sheet if needed. Returns false when Health is
    /// unavailable or the request failed (not when the runner declines a type).
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned)
        ]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate)]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
    }

    /// Writes the run as a running workout with its route. Returns whether it was saved.
    func save(_ finished: FinishedRun, calories: Double) async -> Bool {
        guard isAvailable else { return false }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: finished.startDate)

            var samples: [HKSample] = [
                HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning),
                                 quantity: HKQuantity(unit: .meter(), doubleValue: finished.distance),
                                 start: finished.startDate, end: finished.endDate)
            ]
            if calories > 0 {
                samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                                                start: finished.startDate, end: finished.endDate))
            }
            try await builder.addSamples(samples)

            var events: [HKWorkoutEvent] = []
            for pause in finished.pauseIntervals {
                events.append(HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause.start, duration: 0), metadata: nil))
                events.append(HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pause.end, duration: 0), metadata: nil))
            }
            if !events.isEmpty {
                try await builder.addWorkoutEvents(events)
            }

            try await builder.endCollection(at: finished.endDate)
            let saved: HKWorkout? = try await builder.finishWorkout()
            guard let workout = saved else { return false }

            let locations = finished.points.map { point in
                CLLocation(coordinate: point.coordinate, altitude: point.alt,
                           horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: point.time)
            }
            if !locations.isEmpty {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                try await routeBuilder.insertRouteData(locations)
                _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
            return true
        } catch {
            return false
        }
    }

    /// Streams heart rate samples recorded from `start` onward (from a paired watch or
    /// chest strap that writes to Health). The handler runs on the main thread.
    func startHeartRateUpdates(from start: Date, handler: @escaping (_ bpm: Double, _ date: Date) -> Void) -> HKQuery? {
        guard isAvailable else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        let process: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { _, samples, _, _, _ in
            let readings = (samples ?? []).compactMap { $0 as? HKQuantitySample }
                .map { ($0.quantity.doubleValue(for: unit), $0.endDate) }
            guard !readings.isEmpty else { return }
            DispatchQueue.main.async {
                for (bpm, date) in readings { handler(bpm, date) }
            }
        }
        let query = HKAnchoredObjectQuery(type: HKQuantityType(.heartRate), predicate: predicate,
                                          anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: process)
        query.updateHandler = process
        store.execute(query)
        return query
    }

    func stop(_ query: HKQuery?) {
        if let query { store.stop(query) }
    }
}
