import Foundation

/// Today's numbers
public struct TodayStats: Codable, Sendable, Equatable {
    public var steps: Int?
    public var exerciseMinutes: Double?
    public var activeKcal: Double?
    public var restingHR: Double?
    public var hrv: Double?
    public var sleepHours: Double?
    public var workouts: Int
}

/// The last 7 days, oldest first, for small trend charts. nil = no data that day.
public struct Trends: Codable, Sendable, Equatable {
    public var days: [Day]
    public var steps: [Double?]
    public var exerciseMinutes: [Double?]
    public var activeKcal: [Double?]
    public var restingHR: [Double?]
    public var hrv: [Double?]
    public var sleepHours: [Double?]
}

/// Everything the app's Today screen and the widgets show, worked out in one go.
/// The app saves it to the shared App Group container; widgets only read it, so
/// they never need Apple Health access of their own.
public struct Snapshot: Codable, Sendable, Equatable {
    public var updated: Date
    public var today: Day
    public var name: String
    public var isDemo: Bool
    public var readiness: Readiness
    public var stats: TodayStats
    public var trends: Trends
    public var goal: WeeklyGoal
    public var milestones: Milestones
    public var plan: TrainingPlan
    public var sleep: SleepInsights
    public var records: Records
    public var lastWorkout: Workout?
    public var todaysWorkouts: [Workout]

    public var newBests: [Best] { records.bests.filter(\.isNew) }
}

extension Coach {
    public static func snapshot(_ data: HealthData, settings: UserSettings, today: Day, now: Date = Date(),
                                isDemo: Bool = false) -> Snapshot {
        let d = data.day(today)
        let week = (0..<7).map { today.adding($0 - 6) }
        let ladder = milestones(data)
        let todays = data.workouts.filter { $0.day == today }
        return Snapshot(
            updated: now, today: today, name: settings.name, isDemo: isDemo,
            readiness: readiness(data, settings: settings, today: today),
            stats: TodayStats(steps: d?.steps, exerciseMinutes: d?.exerciseMinutes, activeKcal: d?.activeKcal,
                              restingHR: d?.restingHR, hrv: d?.hrv, sleepHours: data.night(today)?.asleepHours,
                              workouts: todays.count),
            trends: Trends(days: week,
                           steps: week.map { data.day($0)?.steps.map(Double.init) },
                           exerciseMinutes: week.map { data.day($0)?.exerciseMinutes },
                           activeKcal: week.map { data.day($0)?.activeKcal },
                           restingHR: week.map { data.day($0)?.restingHR },
                           hrv: week.map { data.day($0)?.hrv },
                           sleepHours: week.map { data.night($0)?.asleepHours }),
            goal: weeklyGoal(data, settings: settings, today: today),
            milestones: ladder,
            plan: trainingPlan(data, ladder: ladder, settings: settings, today: today),
            sleep: sleepInsights(data, settings: settings, today: today),
            records: records(data, today: today),
            lastWorkout: data.workouts.last { $0.day <= today },
            todaysWorkouts: todays)
    }
}

/// Saves and loads the snapshot (and settings) as JSON in a folder both the app
/// and the widgets can read: the App Group container on a phone.
public struct SnapshotStore: Sendable {
    public static let appGroup = "group.com.gvarun17.fitness"
    public let folder: URL

    public init(folder: URL) { self.folder = folder }

    /// The shared App Group folder, or a private one if the group isn't set up
    /// (for example in tests).
    public static var shared: SnapshotStore {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("FitnessShared", isDirectory: true)
        return SnapshotStore(folder: url)
    }

    var snapshotURL: URL { folder.appendingPathComponent("snapshot.json") }
    var settingsURL: URL { folder.appendingPathComponent("settings.json") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public func save(_ s: Snapshot) throws { try write(s, to: snapshotURL) }
    public func loadSnapshot() -> Snapshot? { read(Snapshot.self, from: snapshotURL) }
    public func save(_ s: UserSettings) throws { try write(s, to: settingsURL) }
    public func loadSettings() -> UserSettings { read(UserSettings.self, from: settingsURL) ?? UserSettings() }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(T.self, from: data)
    }
}
