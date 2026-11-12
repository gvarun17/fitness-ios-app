import Foundation
import SwiftData
import SwiftUI
import CoreLocation
import RunCore

enum RunTag: String, CaseIterable, Identifiable {
    case easy, tempo, long, intervals, race

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return "Easy"
        case .tempo: return "Tempo"
        case .long: return "Long"
        case .intervals: return "Intervals"
        case .race: return "Race"
        }
    }

    var color: Color {
        switch self {
        case .easy: return .green
        case .tempo: return .orange
        case .long: return .blue
        case .intervals: return .purple
        case .race: return .red
        }
    }
}

struct HeartRateSample: Codable, Identifiable {
    /// Seconds since the run started.
    var t: Double
    var bpm: Double
    var id: Double { t }
}

@Model
final class Run {
    var uuid: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date = Date()
    /// Active seconds (pauses excluded).
    var duration: Double = 0
    /// Meters.
    var distance: Double = 0
    var elevationGain: Double = 0
    var calories: Double = 0
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var title: String = ""
    var tagRaw: String = RunTag.easy.rawValue
    var notes: String = ""
    /// Perceived effort 1...10, 0 when not rated.
    var effort: Int = 0
    var plannedWorkoutID: String?
    var savedToHealth: Bool = false
    /// JSON-encoded [TrackPoint].
    @Attribute(.externalStorage) var pointsData: Data?
    /// JSON-encoded [Double]: route normalized for drawing a thumbnail.
    var thumbnailData: Data?
    /// JSON-encoded [String: Double]: record distance id to best time on this run.
    var bestEffortsData: Data?
    /// JSON-encoded [HeartRateSample].
    var heartRateData: Data?
    var shoe: Shoe?

    init(startDate: Date, endDate: Date, duration: Double, distance: Double) {
        self.uuid = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.distance = distance
    }

    var tag: RunTag {
        get { RunTag(rawValue: tagRaw) ?? .easy }
        set { tagRaw = newValue.rawValue }
    }

    var secondsPerMeter: Double? {
        distance > 1 && duration > 0 ? duration / distance : nil
    }

    var points: [TrackPoint] {
        guard let pointsData else { return [] }
        return (try? JSONDecoder().decode([TrackPoint].self, from: pointsData)) ?? []
    }

    var thumbnail: [Double] {
        guard let thumbnailData else { return [] }
        return (try? JSONDecoder().decode([Double].self, from: thumbnailData)) ?? []
    }

    /// Record distance id (meters, rounded) to best time in seconds.
    var bestEfforts: [Int: Double] {
        guard let bestEffortsData,
              let raw = try? JSONDecoder().decode([String: Double].self, from: bestEffortsData) else { return [:] }
        var out: [Int: Double] = [:]
        for (key, value) in raw {
            if let id = Int(key) { out[id] = value }
        }
        return out
    }

    var heartRates: [HeartRateSample] {
        guard let heartRateData else { return [] }
        return (try? JSONDecoder().decode([HeartRateSample].self, from: heartRateData)) ?? []
    }

    var summary: RunSummary {
        RunSummary(date: startDate, distance: distance, duration: duration)
    }
}

@Model
final class Shoe {
    var uuid: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var addedDate: Date = Date()
    /// Meters already on the shoe before it was added to the app.
    var initialDistance: Double = 0
    /// Meters after which the shoe should be replaced.
    var targetDistance: Double = 700_000
    var retired: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \Run.shoe) var runs: [Run] = []

    init(name: String, brand: String, initialDistance: Double, targetDistance: Double) {
        self.uuid = UUID()
        self.name = name
        self.brand = brand
        self.initialDistance = initialDistance
        self.targetDistance = targetDistance
    }

    var totalDistance: Double {
        initialDistance + runs.reduce(0) { $0 + $1.distance }
    }

    var wearFraction: Double {
        targetDistance > 0 ? totalDistance / targetDistance : 0
    }

    var displayName: String {
        brand.isEmpty ? name : "\(brand) \(name)"
    }
}

/// The runner's current training plan plus which workouts are done.
@Model
final class PlanRecord {
    var createdDate: Date = Date()
    /// JSON-encoded TrainingPlan.
    var planData: Data = Data()
    /// JSON-encoded [String] of completed workout ids.
    var completedData: Data = Data()

    init(plan: TrainingPlan) {
        self.createdDate = Date()
        self.planData = (try? JSONEncoder().encode(plan)) ?? Data()
        self.completedData = (try? JSONEncoder().encode([String]())) ?? Data()
    }

    var plan: TrainingPlan? {
        try? JSONDecoder().decode(TrainingPlan.self, from: planData)
    }

    var completed: Set<String> {
        get { Set((try? JSONDecoder().decode([String].self, from: completedData)) ?? []) }
        set { completedData = (try? JSONEncoder().encode(newValue.sorted())) ?? Data() }
    }
}

/// An interval workout the runner saved for reuse.
@Model
final class SavedWorkout {
    var createdDate: Date = Date()
    var name: String = ""
    /// JSON-encoded IntervalWorkout.
    var workoutData: Data = Data()

    init(workout: IntervalWorkout) {
        self.createdDate = Date()
        self.name = workout.name
        self.workoutData = (try? JSONEncoder().encode(workout)) ?? Data()
    }

    var workout: IntervalWorkout? {
        try? JSONDecoder().decode(IntervalWorkout.self, from: workoutData)
    }
}

extension TrackPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
