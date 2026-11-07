import Foundation

public struct GoalWeek: Codable, Sendable, Equatable {
    public var monday: Day
    public var value: Double
    public var hit: Bool
}

public struct WeeklyGoal: Codable, Sendable, Equatable {
    public var type: GoalType
    public var target: Double
    public var suggested: Bool
    public var value: Double
    public var need: Double
    public var daysLeft: Int
    public var perDay: Double
    public var streak: Int
    public var best: Int
    public var hits: Int
    public var of: Int
    public var weeks: [GoalWeek]

    public var progress: Double { target > 0 ? min(value / target, 1) : 0 }
    public var reached: Bool { value >= target }

    /// "120 of 150 min"
    public var summary: String {
        "\(Self.text(value, type)) of \(Self.text(target, type)) \(type.unit)"
    }

    public static func text(_ v: Double, _ t: GoalType) -> String {
        t.unit == "km" ? Fmt.km(v) : Fmt.number(v)
    }
}

extension Coach {
    static func goalValue(_ data: HealthData, _ type: GoalType, from: Day, to: Day) -> Double {
        switch type {
        case .minutes:
            return data.days.filter { $0.day >= from && $0.day < to }.compactMap(\.exerciseMinutes).reduce(0, +)
        case .km:
            return (data.workouts.filter { $0.day >= from && $0.day < to }.map(\.km).reduce(0, +) * 10).rounded() / 10
        case .runKm:
            return (data.workouts.filter { $0.day >= from && $0.day < to && $0.sport == .run }.map(\.km).reduce(0, +) * 10).rounded() / 10
        case .runs:
            return Double(data.workouts.filter { $0.day >= from && $0.day < to && $0.sport == .run }.count)
        }
    }

    public static func weeklyGoal(_ data: HealthData, settings: UserSettings, today: Day) -> WeeklyGoal {
        let type = settings.goalType, target = settings.goalTarget
        let this = today.monday
        let firsts = [data.days.first?.day, data.workouts.first?.day].compactMap { $0 }
        var w = max(firsts.min()?.monday ?? this, this.adding(-7 * 104))
        var weeks: [GoalWeek] = []
        while w <= this {
            let v = goalValue(data, type, from: w, to: w.adding(7))
            weeks.append(GoalWeek(monday: w, value: v, hit: v >= target))
            w = w.adding(7)
        }
        let done = weeks.dropLast()
        var streak = 0
        for wk in done.reversed() {
            if !wk.hit { break }
            streak += 1
        }
        if weeks.last!.hit { streak += 1 }
        var best = 0, run = 0
        for wk in weeks {
            run = wk.hit ? run + 1 : 0
            best = max(best, run)
        }
        let now = weeks.last!.value
        let left = 8 - today.weekday             // days left, including today
        let need = max(target - now, 0)
        let recent = done.suffix(12)
        return WeeklyGoal(type: type, target: target, suggested: settings.goalValue == nil, value: now,
                          need: type.unit == "km" ? (need * 10).rounded() / 10 : need.rounded(.up),
                          daysLeft: left, perDay: (need / Double(left) * 10).rounded() / 10,
                          streak: streak, best: best, hits: recent.filter(\.hit).count, of: recent.count,
                          weeks: Array(weeks.suffix(8)))
    }
}
