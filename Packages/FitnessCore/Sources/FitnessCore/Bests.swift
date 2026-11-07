import Foundation

public struct Best: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var text: String
    public var day: Day
    public var isNew: Bool
    public var workoutID: String?
    public var name: String
    public var note: String
}

public struct First: Codable, Sendable, Equatable, Identifiable {
    public var id: String { sport.rawValue }
    public var sport: Sport
    public var day: Day
    public var name: String
    public var isNew: Bool
}

public struct Records: Codable, Sendable, Equatable {
    public var bests: [Best]
    public var firsts: [First]
}

extension Coach {
    public static func records(_ data: HealthData, today: Day) -> Records {
        let weekAgo = today.adding(-6)
        var bests: [Best] = []
        func add(_ id: String, _ label: String, _ day: Day?, _ text: String, workout: Workout? = nil, note: String = "") {
            guard let day else { return }
            bests.append(Best(id: id, label: label, text: text, day: day, isNew: day >= weekAgo,
                              workoutID: workout?.id, name: workout?.name ?? "", note: note))
        }
        func addWorkout(_ id: String, _ label: String, _ w: Workout?, _ text: (Workout) -> String, note: String = "") {
            if let w { add(id, label, w.day, text(w), workout: w, note: note) }
        }
        let runs = data.workouts.filter { $0.sport == .run }
        addWorkout("run_long", "Longest run", runs.filter { $0.km > 0 }.max { $0.km < $1.km }) { "\(Fmt.km($0.km)) km" }
        addWorkout("run_pace", "Fastest run pace", runs.filter { $0.km >= 1 && $0.speed != nil }.max { $0.speed! < $1.speed! },
                   { "\(Fmt.pace(speed: $0.speed!)) /km" }, note: "average for the whole run")
        // Garmin's own fastest splits when it has them, otherwise a whole run of at least that distance
        for (id, label, metres, split) in [("run_1k", "Fastest 1 km", 1000.0, \Workout.fastest1k), ("run_5k", "Fastest 5K", 5000.0, \Workout.fastest5k)] {
            let timed = runs.compactMap { w -> (Workout, Double, Bool)? in
                if let s = w[keyPath: split], s > 0 { return (w, s, true) }
                if let v = w.speed, w.km * 1000 >= metres * tolerance { return (w, metres / v, false) }
                return nil
            }
            if let b = timed.min(by: { $0.1 < $1.1 }) {
                add(id, label, b.0.day, Fmt.clock(seconds: b.1), workout: b.0, note: b.2 ? "fastest split" : "whole-run average")
            }
        }
        var weeks: [Day: Double] = [:]
        for r in runs { weeks[r.day.monday, default: 0] += r.km }
        if let w = weeks.filter({ $0.value > 0 }).max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            add("run_week", "Biggest running week", w.key, "\(Fmt.km(w.value)) km", note: "week")
        }
        for (sport, id, label) in [(Sport.walk, "walk_long", "Longest walk"), (.cycle, "ride_long", "Longest ride"),
                                   (.hike, "hike_long", "Longest hike"), (.swim, "swim_long", "Longest swim")] {
            addWorkout(id, label, data.workouts.filter { $0.sport == sport && $0.km > 0 }.max { $0.km < $1.km }) { "\(Fmt.km($0.km)) km" }
        }
        addWorkout("strength_long", "Longest strength session",
                   data.workouts.filter { $0.sport == .strength && $0.minutes > 0 }.max { $0.minutes < $1.minutes }) { "\(Int($0.minutes.rounded())) min" }
        addWorkout("climb", "Most climbing", data.workouts.filter { ($0.elevationM ?? 0) > 0 }.max { $0.elevationM! < $1.elevationM! }) { "\(Int($0.elevationM!)) m" }
        addWorkout("load", "Hardest session", data.workouts.filter { ($0.load ?? 0) > 0 }.max { $0.load! < $1.load! }) { "load \(Int($0.load!))" }
        let steps = data.days.filter { ($0.steps ?? 0) > 0 }.max { $0.steps! < $1.steps! }
        add("steps_day", "Most steps in a day", steps?.day, steps.map { Fmt.number(Double($0.steps!)) } ?? "")
        let rhr = data.days.filter { $0.restingHR != nil }.min { $0.restingHR! < $1.restingHR! }
        add("rhr_low", "Lowest resting heart rate", rhr?.day, rhr.map { "\(Int($0.restingHR!.rounded())) bpm" } ?? "")
        var minutes: [Day: Double] = [:]
        for d in data.days { minutes[d.day.monday, default: 0] += d.exerciseMinutes ?? 0 }
        if let w = minutes.filter({ $0.value > 0 }).max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            add("im_week", "Most exercise in a week", w.key, "\(Fmt.number(w.value)) min", note: "week")
        }
        if let sc = data.nights.filter({ $0.score != nil }).max(by: { $0.score! < $1.score! }) {
            add("sleep_score", "Best sleep score", sc.day, "\(Int(sc.score!))")
        }
        let sleep = data.nights.filter { $0.asleepHours > 0 }.max { $0.asleepHours < $1.asleepHours }
        add("sleep_long", "Longest night's sleep", sleep?.day, sleep.map { Fmt.hm(hours: $0.asleepHours) } ?? "")

        var firsts: [First] = [], seen: Set<Sport> = []
        for w in data.workouts where !seen.contains(w.sport) {         // oldest first
            seen.insert(w.sport)
            firsts.append(First(sport: w.sport, day: w.day, name: w.name, isNew: w.day >= weekAgo))
        }
        return Records(bests: bests, firsts: firsts)
    }
}
