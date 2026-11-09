import Foundation

public struct PlanSession: Codable, Sendable, Equatable, Identifiable {
    public var id: String { day + kind }
    public var day: String
    public var kind: String
    public var km: Double
    public var done: Bool
}

public struct PlanWeek: Codable, Sendable, Equatable {
    public var monday: Day
    public var longKm: Double
    public var easyKm: Double
    public var runs: Int
    public var easier: Bool
    public var intervals: String?
    public var doneRuns: Int
    public var doneKm: Double
    public var doneLongKm: Double
    public var longDone: Bool
    public var complete: Bool
}

public struct PlanAhead: Codable, Sendable, Equatable {
    public var monday: Day
    public var longKm: Double
    public var easyKm: Double
    public var easier: Bool
}

/// A simple plan toward your next running milestone: easy runs plus one long run
/// that grows about 10% a week, with an easier week every 4th week.
/// Your changes to the weekly plan. Anything nil uses the suggested value.
public struct PlanSettings: Codable, Sendable, Equatable {
    /// 2-6 runs a week (default: your runs goal, or 3)
    public var runsPerWeek: Int?
    /// Which days you run, 1 = Monday ... 7 = Sunday; the last one is the long run
    public var days: [Int]?
    /// How much the long run grows each week, 0.05-0.15 (default 0.10)
    public var growth: Double?
    /// An easier week every n weeks (0 = never, default 4)
    public var easierEvery: Int?
    /// The milestone to build toward ("5k", "10k", "half", "full"; nil = your next one)
    public var target: String?

    public init(runsPerWeek: Int? = nil, days: [Int]? = nil, growth: Double? = nil, easierEvery: Int? = nil, target: String? = nil) {
        self.runsPerWeek = runsPerWeek; self.days = days; self.growth = growth; self.easierEvery = easierEvery; self.target = target
    }

    public static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    public static let targets: [(id: String, label: String, km: Double)] = [("5k", "5K", 5), ("10k", "10K", 10),
                                                                              ("half", "Half marathon", 21.1), ("full", "Marathon", 42.2)]
}

public struct TrainingPlan: Codable, Sendable, Equatable {
    public var target: String
    public var goalKm: Double
    public var perWeek: Int
    public var week: PlanWeek
    public var sessions: [PlanSession]
    public var past: [PlanWeek]
    public var ahead: [PlanAhead]
    public var ready: Bool
}

extension Coach {
    /// Suggested run days for each number of runs a week (1 = Monday); the last is the long run
    public static let planDays: [Int: [Int]] = [2: [3, 6], 3: [2, 4, 6], 4: [1, 3, 5, 7], 5: [1, 2, 4, 5, 7], 6: [1, 2, 3, 5, 6, 7]]
    static let startKm = 1.0

    /// Interval advice while runs are still short
    public static func runWalk(_ km: Double) -> String? {
        if km < 1.5 { return "Run 1 min, walk 2 min, repeat" }
        if km < 2.5 { return "Run 2 min, walk 1 min, repeat" }
        if km < 3.5 { return "Run 4 min, walk 1 min, repeat" }
        return nil
    }

    static func weekPlan(base: Double, goal: Double, easier: Bool, growth: Double = 0.10) -> (long: Double, easy: Double) {
        var long = easier ? max(base, startKm) : max(base * (1 + growth), startKm)
        long = (min(long, goal) * 10).rounded() / 10
        let easy = (max(long * 0.6, long >= 0.8 ? 0.8 : long) * 10).rounded() / 10
        return (long, easy)
    }

    public static func trainingPlan(_ data: HealthData, ladder: Milestones, settings: UserSettings, today: Day) -> TrainingPlan {
        let ps = settings.plan ?? PlanSettings()
        var id = ps.target ?? ladder.nextStep?.id
        var goal: Double
        switch Coach.ladder.first(where: { $0.id == id })?.goal {
        case .run(let km): goal = km
        case .firstRun: goal = 1
        default: goal = 42.2; id = "full"           // triathlons next, or all done: keep building on the marathon
        }
        let target = Coach.ladder.first { $0.id == id }!.label
        let per = min(max(ps.runsPerWeek ?? (settings.goalType == .runs ? Int(settings.goalTarget) : 3), 2), 6)
        let days = (ps.days?.count == per ? ps.days! : planDays[per]!).sorted()
        let growth = min(max(ps.growth ?? 0.10, 0.03), 0.20)
        let every = ps.easierEvery ?? 4
        let isEasier = { (w: Day) in every > 0 && w.isoWeek % every == 0 }
        let runs = data.workouts.filter { $0.sport == .run }

        func base(_ w: Day) -> Double {
            runs.filter { $0.day >= w.adding(-28) && $0.day < w }.map(\.km).max() ?? 0
        }
        func week(_ w: Day) -> PlanWeek {
            let easier = isEasier(w)
            let p = weekPlan(base: base(w), goal: goal, easier: easier, growth: growth)
            let done = runs.filter { $0.day >= w && $0.day < w.adding(7) }
            let longest = done.map(\.km).max() ?? 0
            let longDone = longest >= p.long * 0.95
            return PlanWeek(monday: w, longKm: p.long, easyKm: p.easy, runs: per, easier: easier,
                            intervals: runWalk(max(p.long, longest)), doneRuns: done.count,
                            doneKm: (done.map(\.km).reduce(0, +) * 10).rounded() / 10,
                            doneLongKm: (longest * 10).rounded() / 10, longDone: longDone,
                            complete: done.count >= per && longDone)
        }

        let this = today.monday
        let now = week(this)
        var sessions = (0..<(per - 1)).map { _ in PlanSession(day: "", kind: "Easy run", km: now.easyKm, done: false) }
        sessions.append(PlanSession(day: "", kind: "Long run", km: now.longKm, done: false))
        let easyDone = now.doneRuns - (now.longDone ? 1 : 0)
        for i in sessions.indices {
            sessions[i].day = PlanSettings.weekdayNames[days[i] - 1]
            sessions[i].done = sessions[i].kind == "Long run" ? now.longDone : i < easyDone
        }
        var ahead: [PlanAhead] = []
        var b = max(now.longKm, min(now.doneLongKm, goal))     // build on what you already ran, if longer
        for k in 1...4 {
            let w = this.adding(7 * k), easier = isEasier(w)
            let p = weekPlan(base: b, goal: goal, easier: easier, growth: growth)
            ahead.append(PlanAhead(monday: w, longKm: p.long, easyKm: p.easy, easier: easier))
            b = p.long
        }
        return TrainingPlan(target: target, goalKm: goal, perWeek: per, week: now, sessions: sessions,
                            past: (1...4).reversed().map { week(this.adding(-7 * $0)) }, ahead: ahead,
                            ready: now.longKm >= goal && base(this) >= goal * 0.9)
    }
}
