import Foundation

public struct MilestoneStep: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var detail: String
    public var reached: Day?
}

public struct Milestones: Codable, Sendable, Equatable {
    public var steps: [MilestoneStep]
    /// Index of the next step, nil when the whole ladder is done
    public var next: Int?
    public var runs: Int
    public var walks: Int
    public var longestKm: Double
    public var longestDay: Day?
    public var toGoKm: Double?
    public var weeks: Int?
    public var tip: String

    public var nextStep: MilestoneStep? { next.map { steps[$0] } }
    public var reachedCount: Int { steps.filter { $0.reached != nil }.count }
}

extension Coach {
    /// "5 km" measured as 4.92 km by GPS still counts
    static let tolerance = 0.98

    enum StepGoal: Equatable {
        case firstRun
        case run(Double)
        case triathlon(swim: Double, ride: Double, run: Double)
    }

    static let ladder: [(id: String, label: String, detail: String, goal: StepGoal)] = [
        ("first", "First run", "Any run, even run-walk", .firstRun),
        ("1k", "1 km", "In one run", .run(1)),
        ("5k", "5K", "5 km in one run", .run(5)),
        ("10k", "10K", "10 km in one run", .run(10)),
        ("half", "Half marathon", "21.1 km", .run(21.1)),
        ("full", "Marathon", "42.2 km", .run(42.2)),
        ("703", "Half Ironman", "1.9 swim · 90 bike · 21.1 run, one day", .triathlon(swim: 1.9, ride: 90, run: 21.1)),
        ("ironman", "Ironman", "3.8 swim · 180 bike · 42.2 run, one day", .triathlon(swim: 3.8, ride: 180, run: 42.2)),
    ]

    public static func milestones(_ data: HealthData) -> Milestones {
        let runs = data.workouts.filter { $0.sport == .run }
        var byDay: [Day: [Sport: Double]] = [:]
        for w in data.workouts where [.swim, .cycle, .run].contains(w.sport) {
            byDay[w.day, default: [:]][w.sport, default: 0] += w.km
        }
        func reached(_ goal: StepGoal) -> Day? {
            switch goal {
            case .firstRun:
                return runs.first?.day
            case .run(let km):
                return runs.first { $0.km >= km * tolerance }?.day
            case .triathlon(let s, let r, let n):
                return byDay.keys.sorted().first { d in
                    let t = byDay[d]!
                    return (t[.swim] ?? 0) >= s * tolerance && (t[.cycle] ?? 0) >= r * tolerance && (t[.run] ?? 0) >= n * tolerance
                }
            }
        }
        let steps = ladder.map { MilestoneStep(id: $0.id, label: $0.label, detail: $0.detail, reached: reached($0.goal)) }
        let longest = runs.max { $0.km < $1.km }
        let longKm = longest?.km ?? 0
        let walks = data.workouts.filter { $0.sport == .walk }.count
        let next = steps.firstIndex { $0.reached == nil }
        var out = Milestones(steps: steps, next: next, runs: runs.count, walks: walks, longestKm: longKm,
                             longestDay: longest?.day, toGoKm: nil, weeks: nil, tip: "")
        guard let i = next else {
            out.tip = "You've climbed the whole ladder. Time to pick a new goal!"
            return out
        }
        switch ladder[i].goal {
        case .firstRun:
            out.tip = "Try run-walk: 1 minute of easy running, then 2 minutes of walking, 8 times. "
                + (walks > 0 ? "Your \(walks) walks are already a good base." : "Easy enough that you could chat the whole time.")
        case .triathlon:
            let best = { (s: Sport) in data.workouts.filter { $0.sport == s }.map(\.km).max() ?? 0 }
            out.tip = "Build up swimming and cycling alongside your running. Longest swim so far "
                + "\(Fmt.km(best(.swim))) km, longest ride \(Int(best(.cycle).rounded())) km."
        case .run(let km):
            out.toGoKm = (max(km - longKm, 0) * 10).rounded() / 10
            if longKm > 0 {
                let w = max(1, Int((log(km / longKm) / log(1.1)).rounded(.up)))
                out.weeks = w
                out.tip = "Add about 10% to your longest run each week, and you'll get there in about \(w) week\(w == 1 ? "" : "s")."
            } else {
                out.tip = "Use run-walk to build up: run a little longer each time before you walk."
            }
        }
        return out
    }
}
