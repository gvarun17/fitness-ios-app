import Foundation
import SwiftData
import RunCore

/// Persists finished runs and keeps related records in step.
enum RunStore {
    static func defaultTitle(for date: Date, tag: RunTag) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part: String
        switch hour {
        case 4..<11: part = "Morning"
        case 11..<14: part = "Lunch"
        case 14..<18: part = "Afternoon"
        case 18..<22: part = "Evening"
        default: part = "Night"
        }
        switch tag {
        case .easy: return "\(part) Run"
        case .tempo: return "\(part) Tempo Run"
        case .long: return "\(part) Long Run"
        case .intervals: return "\(part) Intervals"
        case .race: return "Race"
        }
    }

    @discardableResult
    static func save(_ finished: FinishedRun, in context: ModelContext) -> Run {
        let run = Run(startDate: finished.startDate, endDate: finished.endDate,
                      duration: finished.duration, distance: finished.distance)
        run.elevationGain = finished.elevationGain
        run.calories = Calories.estimate(distanceMeters: finished.distance, weightKg: AppSettings.weightKg)
        run.tag = finished.setup.tag
        run.title = defaultTitle(for: finished.startDate, tag: finished.setup.tag)
        run.plannedWorkoutID = finished.setup.plannedWorkoutID

        let encoder = JSONEncoder()
        run.pointsData = try? encoder.encode(finished.points)
        run.thumbnailData = try? encoder.encode(RouteThumbnail.normalized(finished.points))
        var efforts: [String: Double] = [:]
        for (id, time) in BestEfforts.all(points: finished.points) {
            efforts[String(id)] = time
        }
        run.bestEffortsData = try? encoder.encode(efforts)

        if !finished.heartRates.isEmpty {
            let values = finished.heartRates.map(\.bpm)
            run.averageHeartRate = values.reduce(0, +) / Double(values.count)
            run.maxHeartRate = values.max()
            run.heartRateData = try? encoder.encode(finished.heartRates)
        }

        context.insert(run)

        if let shoeID = finished.setup.shoeID,
           let shoe = (try? context.fetch(FetchDescriptor<Shoe>()))?.first(where: { $0.uuid == shoeID }) {
            run.shoe = shoe
        }

        if let workoutID = finished.setup.plannedWorkoutID,
           let record = (try? context.fetch(FetchDescriptor<PlanRecord>()))?.first {
            var completed = record.completed
            completed.insert(workoutID)
            record.completed = completed
        }

        try? context.save()

        if AppSettings.healthEnabled {
            let calories = run.calories
            Task { @MainActor in
                if await HealthService.shared.save(finished, calories: calories) {
                    run.savedToHealth = true
                    try? context.save()
                }
            }
        }
        return run
    }

    static func delete(_ run: Run, in context: ModelContext) {
        context.delete(run)
        try? context.save()
    }
}
