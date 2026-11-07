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
    static let planDays: [Int: [String]] = [2: ["Wed", "Sat"], 3: ["Tue", "Thu", "Sat"],
                                             4: ["Mon", "Wed", "Fri", "Sun"], 5: ["Mon", "Tue", "Thu", "Fri", "Sun"]]
    static let startKm = 1.0

    /// Interval advice while runs are still short
    public static func runWalk(_ km: Double) -> String? {
        if km < 1.5 { return "Run 1 min, walk 2 min, repeat" }
        if km < 2.5 { return "Run 2 min, walk 1 min, repeat" }
        if km < 3.5 { return "Run 4 min, walk 1 min, repeat" }
        return nil
    }

    static func weekPlan(base: Double, goal: Double, easier: Bool) -> (long: Double, easy: Double) {
        var long = easier ? max(base, startKm) : max(base * 1.1, startKm)
        long = (min(long, goal) * 10).rounded() / 10
        let easy = (max(long * 0.6, long >= 0.8 ? 0.8 : long) * 10).rounded() / 10
        return (long, easy)
    }

    public static func trainingPlan(_ data: HealthData, ladder: Milestones, settings: UserSettings, today: Day) -> TrainingPlan {
        var id = ladder.nextStep?.id
        var goal: Double
        switch Coach.ladder.first(where: { $0.id == id })?.goal {
        case .run(let km): goal = km
        case .firstRun: goal = 1
        default: goal = 42.2; id = "full"           // triathlons next, or all done: keep building on the marathon
        }
        let target = Coach.ladder.first { $0.id == id }!.label
        let per = settings.goalType == .runs ? min(max(Int(settings.goalTarget), 2), 5) : 3
        let runs = data.workouts.filter { $0.sport == .run }

        func base(_ w: Day) -> Double {
            runs.filter { $0.day >= w.adding(-28) && $0.day < w }.map(\.km).max() ?? 0
        }
        func week(_ w: Day) -> PlanWeek {
            let easier = w.isoWeek % 4 == 0
            let p = weekPlan(base: base(w), goal: goal, easier: easier)
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
            sessions[i].day = planDays[per]![i]
            sessions[i].done = sessions[i].kind == "Long run" ? now.longDone : i < easyDone
        }
        var ahead: [PlanAhead] = []
        var b = max(now.longKm, min(now.doneLongKm, goal))     // build on what you already ran, if longer
        for k in 1...4 {
            let w = this.adding(7 * k), easier = w.isoWeek % 4 == 0
            let p = weekPlan(base: b, goal: goal, easier: easier)
            ahead.append(PlanAhead(monday: w, longKm: p.long, easyKm: p.easy, easier: easier))
            b = p.long
        }
        return TrainingPlan(target: target, goalKm: goal, perWeek: per, week: now, sessions: sessions,
                            past: (1...4).reversed().map { week(this.adding(-7 * $0)) }, ahead: ahead,
                            ready: now.longKm >= goal && base(this) >= goal * 0.9)
    }
}
