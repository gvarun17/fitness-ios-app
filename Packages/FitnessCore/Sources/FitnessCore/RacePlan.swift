import Foundation

/// The race a day-by-day plan builds toward
public enum RaceGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case fiveK, tenK, half, marathon
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "Half marathon"
        case .marathon: "Marathon"
        }
    }
    public var km: Double {
        switch self {
        case .fiveK: 5
        case .tenK: 10
        case .half: 21.1
        case .marathon: 42.2
        }
    }
    /// The longest run before tapering
    public var peakLongKm: Double {
        switch self {
        case .fiveK: 5
        case .tenK: 12
        case .half: 18
        case .marathon: 32
        }
    }
    /// Weeks of easing off before the race (race week included)
    public var taperWeeks: Int {
        switch self {
        case .fiveK, .tenK: 1
        case .half: 2
        case .marathon: 3
        }
    }
    /// The quality session that suits this distance
    var quality: DayKind { self == .fiveK || self == .tenK ? .intervals : .tempo }
}

public enum DayKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case rest, easy, long, intervals, tempo, strength, race
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rest: "Rest"
        case .easy: "Easy run"
        case .long: "Long run"
        case .intervals: "Intervals"
        case .tempo: "Tempo run"
        case .strength: "Strength"
        case .race: "Race day"
        }
    }
    public var isRun: Bool { ![.rest, .strength].contains(self) }

    /// SF Symbol
    public var symbol: String {
        switch self {
        case .rest: "bed.double"
        case .easy: "figure.walk.motion"
        case .long: "figure.run"
        case .intervals: "stopwatch"
        case .tempo: "speedometer"
        case .strength: "dumbbell"
        case .race: "flag.checkered"
        }
    }
}

/// Your choices for a race plan, plus any days you've changed
public struct RaceSettings: Codable, Sendable, Equatable {
    public var goal: RaceGoal
    public var raceDate: Day
    public var startDate: Day
    /// 2-6 runs a week
    public var runsPerWeek: Int
    /// 1 = Monday ... 7 = Sunday
    public var longRunDay: Int
    public var strengthDay: Bool
    /// Your longest recent run, where the plan starts from
    public var startLongKm: Double
    /// Days you've edited, by date
    public var edits: [String: PlanDay]

    public init(goal: RaceGoal, raceDate: Day, startDate: Day, runsPerWeek: Int = 3, longRunDay: Int = 6,
                strengthDay: Bool = false, startLongKm: Double = 1, edits: [String: PlanDay] = [:]) {
        self.goal = goal; self.raceDate = raceDate; self.startDate = startDate; self.runsPerWeek = runsPerWeek
        self.longRunDay = longRunDay; self.strengthDay = strengthDay; self.startLongKm = startLongKm; self.edits = edits
    }
}

public struct PlanDay: Codable, Sendable, Equatable, Identifiable {
    public var id: String { day.iso }
    public var day: Day
    public var kind: DayKind
    public var km: Double
    public var detail: String
    /// Changed by you
    public var edited: Bool = false
    /// You've chosen to skip it
    public var skipped: Bool = false

    public init(day: Day, kind: DayKind, km: Double = 0, detail: String = "", edited: Bool = false, skipped: Bool = false) {
        self.day = day; self.kind = kind; self.km = km; self.detail = detail; self.edited = edited; self.skipped = skipped
    }

    public var title: String { kind.isRun && km > 0 ? "\(kind.label) · \(Fmt.km(km)) km" : kind.label }
}

public enum DayStatus: String, Codable, Sendable { case done, missed, today, upcoming, rest, skipped }

public struct RacePlan: Codable, Sendable, Equatable {
    public var settings: RaceSettings
    public var days: [PlanDay]
    public var peakLongKm: Double
    /// e.g. "Tight timeline: …" when the date leaves too little time
    public var warning: String?
    /// The earliest race date that leaves enough time
    public var suggestedDate: Day

    public var weeks: Int { (days.first?.day.monday.days(until: settings.raceDate) ?? 0) / 7 + 1 }

    public func day(_ d: Day) -> PlanDay? { days.first { $0.day == d } }
    public func week(of d: Day) -> [PlanDay] { days.filter { $0.day.monday == d.monday } }
    public var totalKm: Double { days.filter { $0.kind.isRun && !$0.skipped }.map(\.km).reduce(0, +) }
}

extension Coach {
    /// Running days other than the long run, in order of preference: spread out,
    /// and never the day after the long run.
    static func runDays(longDay: Int, count: Int) -> [Int] {
        let order = [-3, -5, -2, -4, -6]
        let others = order.prefix(max(count - 1, 0)).map { (longDay + $0 + 14 - 1) % 7 + 1 }
        return (others + [longDay]).sorted()
    }

    static let qualityDetail: [DayKind: String] = [
        .intervals: "10 min easy, then 6 × 400 m quick (you can say only a few words) with 90 s walking between, then 10 min easy.",
        .tempo: "10 min easy, 15–20 min comfortably hard (you can say short sentences), 10 min easy.",
        .easy: "Easy pace: you can talk in full sentences.",
        .long: "Slow and steady: slower than you think. Distance matters, not speed.",
        .strength: "20–30 min: squats, lunges, calf raises, glute bridges and a plank. Fewer injuries, stronger running.",
        .rest: "Rest, or a gentle walk. Recovery is when you get fitter.",
    ]

    /// Weeks of 10% growth (with easier weeks) to go from one long run to another
    static func weeksNeeded(from: Double, to: Double) -> Int {
        guard to > from else { return 0 }
        let growing = Int((log(to / max(from, 1)) / log(1.1)).rounded(.up))
        return growing + growing / 3                 // one easier week in every four
    }

    /// The day-by-day plan from the start date to race day
    public static func racePlan(_ s: RaceSettings) -> RacePlan {
        let goal = s.goal, start = s.startDate, race = s.raceDate
        let per = min(max(s.runsPerWeek, 2), 6)
        let firstMonday = start.monday
        let totalWeeks = max(1, firstMonday.days(until: race.monday) / 7 + 1)
        let taper = min(goal.taperWeeks, totalWeeks)
        let build = totalWeeks - taper
        let l0 = max(s.startLongKm, 1)
        let needed = weeksNeeded(from: l0, to: goal.peakLongKm) + goal.taperWeeks
        let suggested = start.adding(7 * needed).monday.adding(s.longRunDay - 1)
        let runDays = runDays(longDay: s.longRunDay, count: per)
        let strengthDay = s.strengthDay ? (1...7).first { d in !runDays.contains(d) && (d - s.longRunDay + 7) % 7 >= 2 } : nil

        var longs: [Double] = []
        var prev = l0
        for w in 0..<build {
            let easier = (w + 1) % 4 == 0
            let long = w == 0 ? l0 : easier ? prev * 0.8 : min(prev * 1.1, goal.peakLongKm)
            longs.append(long)
            if !easier { prev = long }
        }
        let peak = longs.max() ?? l0
        let taperFactors: [Int: [Double]] = [1: [0.5], 2: [0.7, 0.45], 3: [0.75, 0.6, 0.4]]
        for f in taperFactors[taper] ?? [0.5] { longs.append(max(peak * f, min(l0, goal.km))) }

        var days: [PlanDay] = []
        var d = start
        while d <= race {
            let w = firstMonday.days(until: d.monday) / 7
            let long = (longs[min(w, longs.count - 1)] * 10).rounded() / 10
            let easy = (max(long * 0.55, min(long, 1.5)) * 10).rounded() / 10
            let raceWeek = d.monday == race.monday
            let wd = d.weekday
            var day: PlanDay
            if d == race {
                day = PlanDay(day: d, kind: .race, km: goal.km,
                              detail: "\(goal.label) race day. Start slower than you want to, and enjoy it!")
            } else if raceWeek {
                // Race week: a couple of short, easy runs, rest for the last two days
                let daysOut = d.days(until: race)
                if runDays.contains(wd), daysOut > 2 {
                    day = PlanDay(day: d, kind: .easy, km: (min(easy, max(goal.km * 0.3, 1.5), 5) * 10).rounded() / 10,
                                  detail: "Short and easy: stay fresh for race day.")
                } else {
                    day = PlanDay(day: d, kind: .rest, detail: daysOut <= 2 ? "Rest: race day is close." : qualityDetail[.rest]!)
                }
            } else if wd == s.longRunDay {
                day = PlanDay(day: d, kind: .long, km: long, detail: qualityDetail[.long]!)
            } else if runDays.contains(wd) {
                let easier = w < build && (w + 1) % 4 == 0
                let quality = per >= 3 && w >= 2 && w < build && !easier && wd == runDays.first
                let kind: DayKind = quality ? (w % 2 == 0 ? goal.quality : (goal.quality == .intervals ? .tempo : .intervals)) : .easy
                day = PlanDay(day: d, kind: kind, km: easy, detail: qualityDetail[kind]!)
            } else if wd == strengthDay {
                day = PlanDay(day: d, kind: .strength, detail: qualityDetail[.strength]!)
            } else {
                day = PlanDay(day: d, kind: .rest, detail: qualityDetail[.rest]!)
            }
            if day.kind.isRun, day.kind != .race, let rw = runWalk(day.km) {
                day.detail = "\(rw). " + day.detail
            }
            if let e = s.edits[d.iso] { day = e }
            days.append(day)
            d = d.adding(1)
        }

        var warning: String?
        if race < start {
            warning = "The race date is before the plan starts."
        } else if peak < goal.peakLongKm * 0.9, race < suggested {
            warning = "Tight timeline: your long run reaches \(Fmt.km(peak)) km before tapering, short of the \(Fmt.km(goal.peakLongKm)) km that makes a \(goal.label) comfortable. Racing on or after \(suggested.iso) leaves enough time, or run this one as a run-walk."
        }
        return RacePlan(settings: s, days: days, peakLongKm: (peak * 10).rounded() / 10, warning: warning, suggestedDate: suggested)
    }

    /// Whether a planned day was done, judged from that day's runs
    public static func status(_ p: PlanDay, data: HealthData, today: Day) -> DayStatus {
        if p.skipped { return .skipped }
        if !p.kind.isRun { return p.kind == .strength && data.workouts.contains { $0.day == p.day && $0.sport == .strength } ? .done : .rest }
        let km = data.workouts.filter { $0.day == p.day && $0.sport == .run }.map(\.km).reduce(0, +)
        if km > 0, km >= p.km * 0.8 || p.kind == .intervals || p.kind == .tempo { return .done }
        if p.day == today { return .today }
        return p.day < today ? .missed : .upcoming
    }

    /// Done / planned runs so far, for the plan's progress bar
    public static func progress(_ plan: RacePlan, data: HealthData, today: Day) -> (done: Int, planned: Int) {
        let past = plan.days.filter { $0.kind.isRun && !$0.skipped && $0.day <= today }
        return (past.filter { status($0, data: data, today: today) == .done }.count, past.count)
    }
}
