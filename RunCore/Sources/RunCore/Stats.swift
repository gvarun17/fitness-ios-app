import Foundation

/// Minimal view of a run for aggregate stats.
public struct RunSummary: Equatable, Sendable {
    public var date: Date
    public var distance: Double
    public var duration: TimeInterval

    public init(date: Date, distance: Double, duration: TimeInterval) {
        self.date = date
        self.distance = distance
        self.duration = duration
    }
}

public enum StatsPeriod: String, CaseIterable, Sendable {
    case week, month, year

    var component: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

public struct StatsBucket: Identifiable, Equatable, Sendable {
    public var start: Date
    public var distance: Double
    public var duration: TimeInterval
    public var runCount: Int
    public var id: Date { start }
}

public enum Stats {
    /// Start of the week/month/year containing `date`.
    public static func periodStart(_ period: StatsPeriod, containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: period.component, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The last `count` periods ending with the one containing `now`, oldest first.
    /// Periods with no runs are included with zero totals.
    public static func buckets(_ runs: [RunSummary], period: StatsPeriod, count: Int,
                               now: Date, calendar: Calendar) -> [StatsBucket] {
        guard count > 0 else { return [] }
        let currentStart = periodStart(period, containing: now, calendar: calendar)
        var starts: [Date] = []
        for back in stride(from: count - 1, through: 0, by: -1) {
            if let d = calendar.date(byAdding: period.component, value: -back, to: currentStart) {
                starts.append(periodStart(period, containing: d, calendar: calendar))
            }
        }
        var byStart: [Date: StatsBucket] = [:]
        for s in starts { byStart[s] = StatsBucket(start: s, distance: 0, duration: 0, runCount: 0) }
        for run in runs {
            let s = periodStart(period, containing: run.date, calendar: calendar)
            guard var bucket = byStart[s] else { continue }
            bucket.distance += run.distance
            bucket.duration += run.duration
            bucket.runCount += 1
            byStart[s] = bucket
        }
        return starts.compactMap { byStart[$0] }
    }

    /// Totals for the period containing `now`.
    public static func current(_ runs: [RunSummary], period: StatsPeriod, now: Date, calendar: Calendar) -> StatsBucket {
        buckets(runs, period: period, count: 1, now: now, calendar: calendar).first
            ?? StatsBucket(start: now, distance: 0, duration: 0, runCount: 0)
    }

    /// Consecutive days with a run, counting back from today (or yesterday if today has no run yet).
    public static func currentDayStreak(dates: [Date], today: Date, calendar: Calendar) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        var cursor = calendar.startOfDay(for: today)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    public static func longestDayStreak(dates: [Date], calendar: Calendar) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous), next == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }

    /// Consecutive weeks (ending with this week, or last week if this one has no run yet) with at least one run.
    public static func currentWeekStreak(dates: [Date], today: Date, calendar: Calendar) -> Int {
        let weeks = Set(dates.map { periodStart(.week, containing: $0, calendar: calendar) })
        var cursor = periodStart(.week, containing: today, calendar: calendar)
        if !weeks.contains(cursor) {
            guard let last = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = last
        }
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
