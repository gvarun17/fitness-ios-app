import Foundation

/// A number with a comparison and 12 weeks of history, as in the web dashboard's tiles.
public struct Tile: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var value: String
    public var unit: String
    /// e.g. "▲ 1.2 km vs usual by now"
    public var delta: String
    /// true = the change is good, false = bad, nil = neither
    public var deltaGood: Bool?
    /// One value per week, oldest first (nil = no data)
    public var weeks: [Double?]
}

/// One week's workouts for one sport
public struct SportWeek: Codable, Sendable, Equatable {
    public var monday: Day
    public var sport: Sport
    public var km: Double
    public var minutes: Double
    public var count: Int
    public var load: Double
}

/// Everything shown for one day in the Today screen (any of the last 90 days)
public struct DayView: Sendable, Equatable {
    public var day: Day
    public var summary: DaySummary?
    public var night: SleepNight?
    public var detail: DayDetail?
    public var workouts: [Workout]
    /// Exercise minutes in that day's week so far
    public var weekMinutes: Double
}

extension Coach {
    // MARK: Tiles

    static func avg(_ xs: [Double?]) -> Double? { mean(xs.compactMap { $0 }) }

    static func delta(_ v: Double?, _ ref: Double?, upGood: Bool?, word: String, fmt: (Double) -> String) -> (String, Bool?) {
        guard let v, let ref else { return ("", nil) }
        let d = v - ref
        if abs(d) < 1e-9 { return ("level with \(word)", nil) }
        return ("\(d > 0 ? "▲" : "▼") \(fmt(abs(d))) vs \(word)", upGood.map { (d > 0) == $0 })
    }

    static func weekly(_ today: Day, _ n: Int = 12, _ f: (Day, Day) -> Double?) -> [Double?] {
        (0..<n).map { i in let w = today.monday.adding(-7 * (n - 1 - i)); return f(w, w.adding(7)) }
    }

    /// The web dashboard's six training tiles
    public static func trainingTiles(_ data: HealthData, today: Day) -> [Tile] {
        let days = { (a: Day, b: Day) in data.days.filter { $0.day >= a && $0.day < b } }
        let acts = { (a: Day, b: Day) in data.workouts.filter { $0.day >= a && $0.day < b } }
        let w0 = today.monday, idx = w0.days(until: today)
        var out: [Tile] = []

        let km = weekly(today) { a, b in acts(a, b).map(\.km).reduce(0, +) }
        let usual = (1...4).map { k in acts(w0.adding(-7 * k), w0.adding(-7 * k + idx + 1)).map(\.km).reduce(0, +) }.reduce(0, +) / 4
        let (kd, kg) = delta(km.last!, usual, upGood: true, word: "usual by now") { Fmt.km($0) }
        out.append(Tile(id: "km", label: "Distance this week", value: Fmt.km(km.last! ?? 0), unit: "km", delta: kd, deltaGood: kg, weeks: km))

        let last7 = (today.adding(-7), today)
        let st7 = avg(days(last7.0, last7.1).map { $0.steps.map(Double.init) })
        let goal = data.days.last(where: { $0.stepsGoal != nil })?.stepsGoal.map(Double.init)
        let (sd, sg) = goal != nil ? delta(st7, goal, upGood: true, word: "goal") { Fmt.number($0) } : ("", nil)
        out.append(Tile(id: "steps", label: "Steps, 7-day avg", value: st7.map(Fmt.number) ?? "–", unit: "", delta: sd, deltaGood: sg,
                        weeks: weekly(today) { a, b in avg(days(a, b).map { $0.steps.map(Double.init) }) }))

        let r7 = avg(days(today.adding(-6), today.adding(1)).map(\.restingHR))
        let r90 = avg(days(today.adding(-97), today.adding(-6)).map(\.restingHR))
        let (rd, rg) = delta(r7.map { $0.rounded() }, r90.map { $0.rounded() }, upGood: false, word: "90-day avg") { Fmt.number($0) }
        out.append(Tile(id: "rhr", label: "Resting HR, 7-day", value: r7.map(Fmt.number) ?? "–", unit: "bpm", delta: rd, deltaGood: rg,
                        weeks: weekly(today) { a, b in avg(days(a, b).map(\.restingHR)) }))

        let h7 = avg(days(today.adding(-6), today.adding(1)).map(\.hrv))
        let status = data.days.last(where: { $0.hrv != nil })?.hrvStatus
        let hnote = h7 == nil ? "No readings this week" : (status == nil || status == "NONE") ? "Compare with your own trend" : status!.lowercased()
        out.append(Tile(id: "hrv", label: "HRV, 7-night avg", value: h7.map(Fmt.number) ?? "–", unit: "ms", delta: hnote, deltaGood: nil,
                        weeks: weekly(today) { a, b in avg(days(a, b).map(\.hrv)) }))

        let s7 = data.nights.filter { $0.day >= today.adding(-6) && $0.day <= today }
        let sh = mean(s7.map(\.asleepHours)), sc = mean(s7.compactMap(\.score))
        out.append(Tile(id: "sleep", label: "Sleep, last 7 nights", value: sh.map { Fmt.hm(hours: $0) } ?? "–", unit: "",
                        delta: "\(s7.count) of 7 nights tracked" + (sc.map { " · score \(Int($0.rounded()))" } ?? ""), deltaGood: nil,
                        weeks: weekly(today) { a, b in mean(data.nights.filter { $0.day >= a && $0.day < b }.map(\.asleepHours)) }))

        // Garmin's training load when there is one, exercise minutes otherwise
        let hasLoad = data.workouts.contains { $0.load != nil }
        let load = { (a: Day, b: Day) -> Double in
            hasLoad ? acts(a, b).compactMap(\.load).reduce(0, +) : days(a, b).compactMap(\.exerciseMinutes).reduce(0, +)
        }
        let l7 = load(today.adding(-6), today.adding(1)), l4 = load(w0.adding(-28), w0) / 4
        let (ld, _) = delta(l7, l4, upGood: nil, word: "4-wk avg") { Fmt.number($0) }
        out.append(Tile(id: "load", label: hasLoad ? "Training load, 7-day" : "Exercise, 7-day", value: Fmt.number(l7), unit: hasLoad ? "" : "min",
                        delta: ld, deltaGood: nil, weeks: weekly(today) { a, b in load(a, b) }))
        return out
    }

    /// Stress, Body Battery and calories: daily averages over 7 days vs the 4 weeks before
    public static func healthTiles(_ data: HealthData, today: Day) -> [Tile] {
        let days = { (a: Day, b: Day) in data.days.filter { $0.day >= a && $0.day < b } }
        let w0 = today.monday
        func tile(_ id: String, _ label: String, _ unit: String, _ upGood: Bool, _ f: @escaping (DaySummary) -> Double?) -> Tile? {
            guard data.days.contains(where: { f($0) != nil }) else { return nil }
            let v7 = avg(days(today.adding(-7), today).map(f)), v4 = avg(days(w0.adding(-28), w0).map(f))
            let (d, g) = delta(v7.map { $0.rounded() }, v4.map { $0.rounded() }, upGood: upGood, word: "4-wk avg") { Fmt.number($0) }
            return Tile(id: id, label: label, value: v7.map(Fmt.number) ?? "–", unit: unit, delta: d, deltaGood: g,
                        weeks: weekly(today) { a, b in avg(days(a, b).map(f)) })
        }
        return [tile("stress", "Stress, 7-day avg", "", false, \.stressAvg),
                tile("bb", "Body Battery peak, 7-day", "", true, \.bbHigh),
                tile("kcal", "Active calories, 7-day", "kcal", true, \.activeKcal)].compactMap { $0 }
    }

    // MARK: Weeks by sport

    public static func sportWeeks(_ data: HealthData, today: Day, weeks n: Int = 12) -> [SportWeek] {
        var out: [SportWeek] = []
        for i in 0..<n {
            let w = today.monday.adding(-7 * (n - 1 - i))
            let acts = data.workouts.filter { $0.day >= w && $0.day < w.adding(7) }
            for s in Sport.allCases {
                let a = acts.filter { $0.sport == s }
                if a.isEmpty { continue }
                out.append(SportWeek(monday: w, sport: s, km: a.map(\.km).reduce(0, +), minutes: a.map(\.minutes).reduce(0, +),
                                     count: a.count, load: a.compactMap(\.load).reduce(0, +)))
            }
        }
        return out
    }

    /// Exercise minutes per week, oldest first
    public static func exerciseWeeks(_ data: HealthData, today: Day, weeks n: Int = 12) -> [(Day, Double)] {
        (0..<n).map { i in
            let w = today.monday.adding(-7 * (n - 1 - i))
            return (w, data.days.filter { $0.day >= w && $0.day < w.adding(7) }.compactMap(\.exerciseMinutes).reduce(0, +))
        }
    }

    // MARK: Heart rate zones and biggest days

    /// Minutes in zones 1-5 over the last 4 weeks
    public static func zones(_ data: HealthData, today: Day) -> [Double]? {
        let z = data.workouts.filter { $0.day > today.adding(-28) }.compactMap(\.zones)
        guard !z.isEmpty else { return nil }
        return (0..<5).map { i in z.map { $0[i] }.reduce(0, +) }
    }

    /// The five longest sessions
    public static func biggest(_ data: HealthData, n: Int = 5) -> [Workout] {
        Array(data.workouts.sorted { ($0.km, $0.minutes) > ($1.km, $1.minutes) }.prefix(n))
    }

    // MARK: Any one day

    public static func dayView(_ data: HealthData, day: Day) -> DayView {
        DayView(day: day, summary: data.day(day), night: data.night(day), detail: data.dayDetails[day],
                workouts: data.workouts.filter { $0.day == day },
                weekMinutes: data.days.filter { $0.day >= day.monday && $0.day <= day }.compactMap(\.exerciseMinutes).reduce(0, +))
    }
}
