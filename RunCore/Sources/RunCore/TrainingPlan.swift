import Foundation

public enum RaceDistance: String, Codable, CaseIterable, Sendable {
    case fiveK, tenK, half

    public var meters: Double {
        switch self {
        case .fiveK: return 5000
        case .tenK: return 10000
        case .half: return 21097.5
        }
    }

    public var title: String {
        switch self {
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .half: return "Half Marathon"
        }
    }
}

public enum RunnerLevel: String, Codable, CaseIterable, Sendable {
    case beginner, intermediate, advanced

    public var title: String { rawValue.capitalized }

    public var summary: String {
        switch self {
        case .beginner: return "New to running or returning after a break"
        case .intermediate: return "Running regularly, a few times a week"
        case .advanced: return "Experienced and chasing a faster time"
        }
    }
}

public enum PlannedWorkoutKind: String, Codable, Sendable {
    case easy, long, tempo, intervals, race

    public var title: String {
        switch self {
        case .easy: return "Easy Run"
        case .long: return "Long Run"
        case .tempo: return "Tempo Run"
        case .intervals: return "Intervals"
        case .race: return "Race Day"
        }
    }
}

public struct PlannedWorkout: Codable, Hashable, Identifiable, Sendable {
    /// Stable within a plan, e.g. "w3-d1".
    public var id: String
    public var date: Date
    public var kind: PlannedWorkoutKind
    /// Target distance in meters for distance-based runs.
    public var distance: Double?
    public var detail: String
    /// Structured session for tempo and interval days.
    public var intervals: IntervalWorkout?
}

public struct PlanWeek: Codable, Hashable, Identifiable, Sendable {
    /// 1-based week number.
    public var number: Int
    public var workouts: [PlannedWorkout]
    public var id: Int { number }

    /// Sum of the distance-based runs this week, in meters.
    public var plannedDistance: Double { workouts.compactMap(\.distance).reduce(0, +) }
}

public struct TrainingPlan: Codable, Hashable, Sendable {
    public var race: RaceDistance
    public var level: RunnerLevel
    public var runsPerWeek: Int
    public var startDate: Date
    public var raceDate: Date
    public var weeks: [PlanWeek]

    public var allWorkouts: [PlannedWorkout] { weeks.flatMap(\.workouts) }

    public func workout(on date: Date, calendar: Calendar) -> PlannedWorkout? {
        allWorkouts.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    public func nextWorkout(after date: Date, calendar: Calendar, excluding completed: Set<String>) -> PlannedWorkout? {
        let today = calendar.startOfDay(for: date)
        return allWorkouts.first { $0.date >= today && !completed.contains($0.id) }
    }
}

public enum PlanGenerator {
    public static let minimumWeeks = 2
    public static let maximumWeeks = 24

    /// Peak long run in km.
    static func peakLongRun(_ race: RaceDistance, _ level: RunnerLevel) -> Double {
        switch (race, level) {
        case (.fiveK, .beginner): return 6
        case (.fiveK, .intermediate): return 8
        case (.fiveK, .advanced): return 11
        case (.tenK, .beginner): return 10
        case (.tenK, .intermediate): return 13
        case (.tenK, .advanced): return 16
        case (.half, .beginner): return 18
        case (.half, .intermediate): return 20
        case (.half, .advanced): return 23
        }
    }

    /// Day offsets within a week whose last day (offset 6) is the race weekday.
    /// The first entry is the quality day; offset 6 (the long run) is added separately.
    static func midweekOffsets(runsPerWeek: Int) -> [Int] {
        switch runsPerWeek {
        case ...3: return [1, 3]
        case 4: return [1, 3, 4]
        default: return [1, 2, 4, 5]
        }
    }

    static func roundHalfKm(_ km: Double) -> Double {
        max(1, (km * 2).rounded() / 2)
    }

    /// Long-run distance in km for each build week (everything except race week).
    static func longRuns(race: RaceDistance, level: RunnerLevel, buildWeeks: Int) -> [Double] {
        guard buildWeeks > 0 else { return [] }
        let peak = peakLongRun(race, level)
        // With a taper, the peak lands one week earlier.
        let hasTaper = buildWeeks >= 4
        let climbWeeks = hasTaper ? buildWeeks - 1 : buildWeeks
        // Start low, but never so low that weekly jumps exceed roughly 10% of peak.
        let start = max(peak * 0.45, peak * (1 - 0.1 * Double(climbWeeks - 1)))
        var runs: [Double] = []
        for i in 0..<climbWeeks {
            let t = climbWeeks > 1 ? Double(i) / Double(climbWeeks - 1) : 1
            var km = start + (peak - start) * t
            // Every fourth week is a lighter recovery week, except the peak week.
            if (i + 1) % 4 == 0 && i != climbWeeks - 1 { km *= 0.8 }
            runs.append(roundHalfKm(km))
        }
        if hasTaper { runs.append(roundHalfKm(peak * 0.65)) }
        return runs
    }

    static func qualityWorkout(race: RaceDistance, level: RunnerLevel, weekIndex: Int, buildWeeks: Int)
        -> (kind: PlannedWorkoutKind, detail: String, workout: IntervalWorkout) {
        let progress = buildWeeks > 1 ? Double(weekIndex) / Double(buildWeeks - 1) : 1
        let warm: TimeInterval = level == .beginner ? 5 * 60 : 10 * 60

        if weekIndex % 2 == 1 {
            // Tempo: one sustained comfortably-hard block.
            let range: (Double, Double)
            switch level {
            case .beginner: range = (8, 20)
            case .intermediate: range = (15, 30)
            case .advanced: range = (20, 40)
            }
            let minutes = ((range.0 + (range.1 - range.0) * progress) / 5).rounded() * 5
            let workout = IntervalWorkout.make(name: "Tempo \(Int(minutes)) min", warmup: warm, repeats: 1,
                                               run: .time(minutes * 60), recover: nil, cooldown: warm)
            return (.tempo, "\(Int(minutes)) min at a comfortably hard pace, with warm-up and cool-down", workout)
        }

        let repDistance: Double
        let reps: (Double, Double)
        let recovery: TimeInterval
        switch race {
        case .fiveK:
            repDistance = 400; recovery = 90
            reps = level == .beginner ? (4, 8) : (level == .intermediate ? (6, 10) : (8, 12))
        case .tenK:
            repDistance = 800; recovery = 120
            reps = level == .beginner ? (3, 5) : (level == .intermediate ? (4, 7) : (5, 8))
        case .half:
            repDistance = 1000; recovery = 120
            reps = level == .beginner ? (3, 5) : (level == .intermediate ? (4, 7) : (5, 8))
        }
        let count = Int((reps.0 + (reps.1 - reps.0) * progress).rounded())
        let label = repDistance >= 1000 ? "\(Int(repDistance / 1000)) km" : "\(Int(repDistance)) m"
        let workout = IntervalWorkout.make(name: "\(count) x \(label)", warmup: warm, repeats: count,
                                           run: .distance(repDistance), recover: .time(recovery), cooldown: warm)
        let rest = recovery >= 120 ? "\(Int(recovery / 60)) min" : "\(Int(recovery)) sec"
        return (.intervals, "\(count) x \(label) hard with \(rest) easy jog between", workout)
    }

    /// Number of weeks a plan from `start` to `raceDate` would have.
    public static func weekCount(start: Date, raceDate: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: raceDate)
        let days = (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
        return Int((Double(days) / 7).rounded(.up))
    }

    /// Builds a plan whose final workout is the race itself. Weeks are counted back from
    /// race day, so the long run always falls on the race's weekday.
    /// Returns nil when the race is too close or too far away.
    public static func generate(race: RaceDistance, level: RunnerLevel, runsPerWeek: Int,
                                start: Date, raceDate: Date, calendar: Calendar) -> TrainingPlan? {
        let startDay = calendar.startOfDay(for: start)
        let raceDay = calendar.startOfDay(for: raceDate)
        let weekTotal = weekCount(start: startDay, raceDate: raceDay, calendar: calendar)
        guard weekTotal >= minimumWeeks, weekTotal <= maximumWeeks else { return nil }

        let perWeek = min(5, max(3, runsPerWeek))
        let offsets = midweekOffsets(runsPerWeek: perWeek)
        let buildWeeks = weekTotal - 1
        let longs = longRuns(race: race, level: level, buildWeeks: buildWeeks)

        func date(week: Int, offset: Int) -> Date? {
            // Offset 6 of the last week is race day.
            let daysBeforeRace = (weekTotal - 1 - week) * 7 + (6 - offset)
            return calendar.date(byAdding: .day, value: -daysBeforeRace, to: raceDay)
        }

        var weeks: [PlanWeek] = []
        for week in 0..<weekTotal {
            var workouts: [PlannedWorkout] = []
            func add(_ offset: Int, _ kind: PlannedWorkoutKind, km: Double?, detail: String, intervals: IntervalWorkout? = nil) {
                guard let day = date(week: week, offset: offset), day >= startDay else { return }
                workouts.append(PlannedWorkout(id: "w\(week + 1)-d\(offset)", date: day, kind: kind,
                                               distance: km.map { $0 * 1000 }, detail: detail, intervals: intervals))
            }

            if week == weekTotal - 1 {
                // Race week: stay loose, then race.
                let lastLong = longs.last ?? peakLongRun(race, level) * 0.6
                let shakeout = roundHalfKm(min(lastLong * 0.4, race.meters / 1000 * 0.6))
                add(1, .easy, km: shakeout, detail: "Relaxed pace. Finish with a few short, quick strides.")
                add(3, .easy, km: roundHalfKm(shakeout * 0.75), detail: "Very easy. Just keeping the legs moving.")
                add(6, .race, km: race.meters / 1000, detail: "\(race.title) race day. Start controlled and finish strong.")
            } else {
                let long = longs[week]
                let easy = roundHalfKm(long * (race == .half ? 0.4 : 0.55))
                // Beginners spend the first third of the plan on easy running only.
                let easyOnly = level == .beginner && week < max(1, buildWeeks / 3)
                let isTaper = buildWeeks >= 4 && week == buildWeeks - 1
                for (i, offset) in offsets.enumerated() {
                    if i == 0 && !easyOnly && !isTaper {
                        let quality = qualityWorkout(race: race, level: level, weekIndex: week, buildWeeks: buildWeeks)
                        add(offset, quality.kind, km: nil, detail: quality.detail, intervals: quality.workout)
                    } else {
                        add(offset, .easy, km: easy, detail: "Comfortable pace. You should be able to hold a conversation.")
                    }
                }
                add(6, .long, km: long, detail: "Slow and steady. Time on feet matters more than pace.")
            }
            if !workouts.isEmpty {
                weeks.append(PlanWeek(number: weeks.count + 1, workouts: workouts))
            }
        }

        return TrainingPlan(race: race, level: level, runsPerWeek: perWeek,
                            startDate: startDay, raceDate: raceDay, weeks: weeks)
    }
}
