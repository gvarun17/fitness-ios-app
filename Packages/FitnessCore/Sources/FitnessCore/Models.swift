import Foundation

/// A calendar day ("2026-11-07"), free of time zones and daylight saving.
/// The app turns "now" into a Day once, with the phone's calendar; everything
/// after that is plain date arithmetic.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let iso: String

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    public init(_ iso: String) { self.iso = iso }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        iso = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Midnight UTC of this day: only for arithmetic and formatting.
    public var date: Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return Day.utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
    }

    public func adding(_ days: Int) -> Day {
        let d = Day.utc.date(byAdding: .day, value: days, to: date)!
        return Day(date: d, calendar: Day.utc)
    }

    /// 1 = Monday ... 7 = Sunday
    public var weekday: Int { (Day.utc.component(.weekday, from: date) + 5) % 7 + 1 }
    public var monday: Day { adding(1 - weekday) }
    public var isoWeek: Int {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.component(.weekOfYear, from: date)
    }

    public func days(until other: Day) -> Int {
        Day.utc.dateComponents([.day], from: date, to: other.date).day!
    }

    public static func < (a: Day, b: Day) -> Bool { a.iso < b.iso }
    public var description: String { iso }

    public init(from decoder: Decoder) throws { iso = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}

/// One day of health data, from Apple Health and/or Garmin. The Garmin-only
/// fields stay nil when Garmin isn't connected.
public struct DaySummary: Codable, Sendable, Equatable {
    public var day: Day
    public var steps: Int?
    public var restingHR: Double?
    /// HRV in ms. Apple Health reports SDNN, Garmin its overnight average:
    /// different scales, so only ever compare with your own trend.
    public var hrv: Double?
    public var activeKcal: Double?
    /// Apple's exercise minutes, or Garmin's intensity minutes (vigorous count double)
    public var exerciseMinutes: Double?
    // Garmin only
    public var stepsGoal: Int?
    public var totalKcal: Double?
    public var minHR: Double?
    public var maxHR: Double?
    public var moderateMinutes: Double?
    public var vigorousMinutes: Double?
    public var stressAvg: Double?
    public var stressMax: Double?
    /// Share of the day: rest, low, medium, high stress
    public var stressMix: [Double]?
    public var bbHigh: Double?
    public var bbLow: Double?
    public var bbLatest: Double?
    public var bbCharged: Double?
    public var bbDrained: Double?
    public var floors: Double?
    public var floorsGoal: Double?
    public var respiration: Double?
    public var hrvWeekly: Double?
    /// Garmin's HRV status: BALANCED, UNBALANCED, LOW, POOR (or NONE while it learns)
    public var hrvStatus: String?
    public var restingHR7: Double?
    /// When the watch last synced this day ("18:45")
    public var syncedAt: String?

    public init(day: Day, steps: Int? = nil, restingHR: Double? = nil, hrv: Double? = nil,
                activeKcal: Double? = nil, exerciseMinutes: Double? = nil) {
        self.day = day; self.steps = steps; self.restingHR = restingHR; self.hrv = hrv
        self.activeKcal = activeKcal; self.exerciseMinutes = exerciseMinutes
    }

    /// Fills this day's missing values from another source (Apple Health under Garmin)
    public func filled(from o: DaySummary) -> DaySummary {
        var d = self
        d.steps = d.steps ?? o.steps
        d.restingHR = d.restingHR ?? o.restingHR
        d.hrv = d.hrv ?? o.hrv
        d.activeKcal = d.activeKcal ?? o.activeKcal
        d.exerciseMinutes = d.exerciseMinutes ?? o.exerciseMinutes
        return d
    }
}

public enum Sport: String, Codable, CaseIterable, Sendable {
    case run, walk, cycle, swim, hike, strength, other

    public var name: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        case .cycle: "Ride"
        case .swim: "Swim"
        case .hike: "Hike"
        case .strength: "Strength"
        case .other: "Workout"
        }
    }

    /// SF Symbol for this sport
    public var symbol: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .cycle: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .hike: "figure.hiking"
        case .strength: "dumbbell.fill"
        case .other: "figure.mixed.cardio"
        }
    }
}

public struct Workout: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var day: Day
    public var start: Date
    public var sport: Sport
    public var name: String
    public var km: Double
    public var minutes: Double
    public var avgHR: Double?
    public var maxHR: Double?
    public var kcal: Double?
    public var cadence: Double?          // steps per minute
    public var strideM: Double?          // metres per step
    // Garmin only
    public var source: String?           // "garmin" for workouts from Garmin
    public var typeName: String?         // Garmin's type, e.g. "treadmill running"
    public var load: Double?             // training load
    public var aerobicTE: Double?        // aerobic training effect, 0-5
    public var anaerobicTE: Double?
    /// Minutes in heart rate zones 1-5
    public var zones: [Double]?
    public var elevationM: Double?
    public var steps: Int?
    public var fastest1k: Double?        // seconds, Garmin's fastest split
    public var fastest5k: Double?

    public init(id: String, day: Day, start: Date, sport: Sport, name: String, km: Double, minutes: Double,
                avgHR: Double? = nil, maxHR: Double? = nil, kcal: Double? = nil, cadence: Double? = nil,
                strideM: Double? = nil) {
        self.id = id; self.day = day; self.start = start; self.sport = sport; self.name = name; self.km = km
        self.minutes = minutes; self.avgHR = avgHR; self.maxHR = maxHR; self.kcal = kcal
        self.cadence = cadence; self.strideM = strideM
    }

    public var isGarmin: Bool { source == "garmin" }

    /// Average speed in metres per second, over the whole workout
    public var speed: Double? { km > 0 && minutes > 0 ? km * 1000 / (minutes * 60) : nil }
}

/// One night's sleep, filed under the day you woke up.
public struct SleepNight: Codable, Sendable, Equatable {
    public var day: Day
    public var asleepHours: Double
    public var deep: Double
    public var rem: Double
    public var core: Double
    public var awake: Double
    /// Minutes after 18:00 local time, so bedtimes either side of midnight average properly
    public var bedtime: Int?
    public var wake: Int?
    // Garmin only
    public var score: Double?
    public var stressAvg: Double?
    /// Garmin's own sleep need for the night, in hours
    public var needHours: Double?

    public init(day: Day, asleepHours: Double, deep: Double = 0, rem: Double = 0, core: Double = 0,
                awake: Double = 0, bedtime: Int? = nil, wake: Int? = nil) {
        self.day = day; self.asleepHours = asleepHours; self.deep = deep; self.rem = rem; self.core = core
        self.awake = awake; self.bedtime = bedtime; self.wake = wake
    }
}

/// Heart rate and Body Battery through one day (Garmin only).
/// Points are (minutes after local midnight, value).
public struct DayDetail: Codable, Sendable, Equatable {
    public var day: Day
    public var hr: [[Double]]
    public var bb: [[Double]]

    public init(day: Day, hr: [[Double]] = [], bb: [[Double]] = []) {
        self.day = day; self.hr = hr; self.bb = bb
    }
}

/// Second-by-second graphs for one workout (Garmin only).
public struct WorkoutDetail: Codable, Sendable, Equatable {
    /// Seconds since the start, one per sample
    public var t: [Double]
    public var hr: [Double?]
    /// Metres per second
    public var speed: [Double?]
    public var cadence: [Double?]
    public var elevation: [Double?]
    public var power: [Double?]
    /// Minutes spent running, walking and standing (run-walk workouts)
    public var runMin: Double?
    public var walkMin: Double?
    public var standMin: Double?

    public init(t: [Double] = [], hr: [Double?] = [], speed: [Double?] = [], cadence: [Double?] = [],
                elevation: [Double?] = [], power: [Double?] = []) {
        self.t = t; self.hr = hr; self.speed = speed; self.cadence = cadence; self.elevation = elevation; self.power = power
    }

    public var isEmpty: Bool { t.count < 2 }
}

/// Everything read from Apple Health and/or Garmin, oldest first.
public struct HealthData: Codable, Sendable, Equatable {
    public var days: [DaySummary]
    public var nights: [SleepNight]
    public var workouts: [Workout]
    public var dayDetails: [Day: DayDetail]
    public var workoutDetails: [String: WorkoutDetail]

    public init(days: [DaySummary] = [], nights: [SleepNight] = [], workouts: [Workout] = [],
                dayDetails: [Day: DayDetail] = [:], workoutDetails: [String: WorkoutDetail] = [:]) {
        self.days = days.sorted { $0.day < $1.day }
        self.nights = nights.sorted { $0.day < $1.day }
        self.workouts = workouts.sorted { $0.start < $1.start }
        self.dayDetails = dayDetails
        self.workoutDetails = workoutDetails
    }

    /// Garmin first, Apple Health filling the gaps. Workouts recorded by another
    /// app (an Apple Watch, say) are kept unless Garmin has one starting within
    /// 10 minutes, which would be the same workout synced twice.
    public static func merge(apple: HealthData, garmin: HealthData?) -> HealthData {
        guard let g = garmin else { return apple }
        var days = Dictionary(uniqueKeysWithValues: apple.days.map { ($0.day, $0) })
        for d in g.days { days[d.day] = days[d.day].map { d.filled(from: $0) } ?? d }
        var nights = Dictionary(uniqueKeysWithValues: apple.nights.map { ($0.day, $0) })
        for n in g.nights { nights[n.day] = n }
        let extra = apple.workouts.filter { a in !g.workouts.contains { abs($0.start.timeIntervalSince(a.start)) < 600 } }
        return HealthData(days: Array(days.values), nights: Array(nights.values), workouts: g.workouts + extra,
                          dayDetails: g.dayDetails, workoutDetails: g.workoutDetails)
    }

    public func day(_ d: Day) -> DaySummary? { days.last { $0.day == d } }
    public func night(_ d: Day) -> SleepNight? { nights.last { $0.day == d } }
}

public enum GoalType: String, Codable, CaseIterable, Sendable, Identifiable {
    case minutes, km, runKm, runs
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .minutes: "Exercise minutes"
        case .km: "Distance, all workouts"
        case .runKm: "Running distance"
        case .runs: "Number of runs"
        }
    }
    public var unit: String {
        switch self {
        case .minutes: "min"
        case .km, .runKm: "km"
        case .runs: "runs"
        }
    }
    /// The suggested weekly target (150 exercise minutes is the WHO guideline)
    public var suggested: Double {
        switch self {
        case .minutes: 150
        case .km: 15
        case .runKm: 10
        case .runs: 3
        }
    }
    public var maximum: Double {
        switch self {
        case .minutes: 3000
        case .km: 500
        case .runKm: 300
        case .runs: 14
        }
    }
}

public struct UserSettings: Codable, Sendable, Equatable {
    public var name: String
    public var goalType: GoalType
    /// nil = the suggested target
    public var goalValue: Double?
    public var sleepNeedHours: Double
    /// Your changes to the weekly plan (nil = the suggested plan). Optional so
    /// settings saved by older versions still load.
    public var plan: PlanSettings?
    /// The day-by-day plan to a race, if you've made one
    public var race: RaceSettings?

    public init(name: String = "", goalType: GoalType = .minutes, goalValue: Double? = nil, sleepNeedHours: Double = 8,
                plan: PlanSettings? = nil, race: RaceSettings? = nil) {
        self.name = name; self.goalType = goalType; self.goalValue = goalValue; self.sleepNeedHours = sleepNeedHours
        self.plan = plan; self.race = race
    }

    public var goalTarget: Double { goalValue ?? goalType.suggested }

    /// Checks a typed weekly goal. Empty means "use the suggested target".
    public static func cleanGoal(_ type: GoalType, _ text: String) throws -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { return nil }
        guard let v = Double(t) else { throw GoalError.notANumber }
        guard v > 0, v <= type.maximum else { throw GoalError.outOfRange(type.maximum, type.unit) }
        if type == .runs, v.rounded() != v { throw GoalError.wholeRuns }
        return v
    }
}

public enum GoalError: Error, Equatable, LocalizedError {
    case notANumber, outOfRange(Double, String), wholeRuns

    public var errorDescription: String? {
        switch self {
        case .notANumber: "Please enter your weekly goal as a number, or leave it empty."
        case .outOfRange(let top, let unit): "Please pick a weekly goal above 0 and up to \(Int(top)) \(unit)."
        case .wholeRuns: "Please enter a whole number of runs."
        }
    }
}
