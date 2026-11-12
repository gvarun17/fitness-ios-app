import Foundation

public enum StepKind: String, Codable, Sendable {
    case warmup, run, recover, cooldown

    public var title: String {
        switch self {
        case .warmup: return "Warm Up"
        case .run: return "Run"
        case .recover: return "Recover"
        case .cooldown: return "Cool Down"
        }
    }
}

public enum StepMeasure: Codable, Hashable, Sendable {
    case time(TimeInterval)
    case distance(Double)
}

public struct IntervalStep: Codable, Hashable, Sendable {
    public var kind: StepKind
    public var measure: StepMeasure

    public init(kind: StepKind, measure: StepMeasure) {
        self.kind = kind
        self.measure = measure
    }
}

public struct IntervalWorkout: Codable, Hashable, Sendable {
    public var name: String
    public var steps: [IntervalStep]

    public init(name: String, steps: [IntervalStep]) {
        self.name = name
        self.steps = steps
    }

    /// Builds warm-up, `repeats` runs with a recovery between each, then cool-down.
    public static func make(name: String, warmup: TimeInterval?, repeats: Int,
                            run: StepMeasure, recover: StepMeasure?, cooldown: TimeInterval?) -> IntervalWorkout {
        var steps: [IntervalStep] = []
        if let warmup, warmup > 0 { steps.append(IntervalStep(kind: .warmup, measure: .time(warmup))) }
        let count = max(1, repeats)
        for rep in 1...count {
            steps.append(IntervalStep(kind: .run, measure: run))
            if let recover, rep < count { steps.append(IntervalStep(kind: .recover, measure: recover)) }
        }
        if let cooldown, cooldown > 0 { steps.append(IntervalStep(kind: .cooldown, measure: .time(cooldown))) }
        return IntervalWorkout(name: name, steps: steps)
    }

    public var runStepCount: Int { steps.filter { $0.kind == .run }.count }
}

/// Follows an interval workout as elapsed time and distance advance.
public struct IntervalProgress: Sendable {
    public enum Event: Equatable, Sendable {
        /// A new step began (index into `workout.steps`).
        case stepStarted(Int)
        case workoutFinished
    }

    public let workout: IntervalWorkout
    public private(set) var currentIndex: Int = 0
    public private(set) var isFinished: Bool
    private var stepStartElapsed: TimeInterval = 0
    private var stepStartDistance: Double = 0
    private var lastElapsed: TimeInterval = 0
    private var lastDistance: Double = 0

    public init(workout: IntervalWorkout) {
        self.workout = workout
        self.isFinished = workout.steps.isEmpty
    }

    public var currentStep: IntervalStep? {
        isFinished ? nil : workout.steps[currentIndex]
    }

    public var nextStep: IntervalStep? {
        guard !isFinished, currentIndex + 1 < workout.steps.count else { return nil }
        return workout.steps[currentIndex + 1]
    }

    /// 1-based number of the current run repeat, counting only `.run` steps.
    public var currentRepeat: Int {
        guard !workout.steps.isEmpty else { return 0 }
        let upTo = min(currentIndex, workout.steps.count - 1)
        return workout.steps[0...upTo].filter { $0.kind == .run }.count
    }

    /// What is left of the current step: seconds for timed steps, meters for distance steps.
    public var remaining: Double {
        guard let step = currentStep else { return 0 }
        switch step.measure {
        case .time(let t): return max(0, t - (lastElapsed - stepStartElapsed))
        case .distance(let d): return max(0, d - (lastDistance - stepStartDistance))
        }
    }

    /// 0...1 progress through the current step.
    public var fraction: Double {
        guard let step = currentStep else { return 1 }
        switch step.measure {
        case .time(let t): return t > 0 ? min(1, (lastElapsed - stepStartElapsed) / t) : 1
        case .distance(let d): return d > 0 ? min(1, (lastDistance - stepStartDistance) / d) : 1
        }
    }

    public mutating func update(elapsed: TimeInterval, distance: Double) -> [Event] {
        lastElapsed = elapsed
        lastDistance = distance
        var events: [Event] = []
        while let step = currentStep {
            var boundaryElapsed = elapsed
            var boundaryDistance = distance
            switch step.measure {
            case .time(let t):
                guard elapsed - stepStartElapsed >= t else { return events }
                boundaryElapsed = stepStartElapsed + t
            case .distance(let d):
                guard distance - stepStartDistance >= d else { return events }
                boundaryDistance = stepStartDistance + d
            }
            events += advance(elapsed: boundaryElapsed, distance: boundaryDistance)
        }
        return events
    }

    /// Jump to the next step right now.
    public mutating func skip() -> [Event] {
        guard !isFinished else { return [] }
        return advance(elapsed: lastElapsed, distance: lastDistance)
    }

    private mutating func advance(elapsed: TimeInterval, distance: Double) -> [Event] {
        stepStartElapsed = elapsed
        stepStartDistance = distance
        if currentIndex + 1 < workout.steps.count {
            currentIndex += 1
            return [.stepStarted(currentIndex)]
        }
        isFinished = true
        return [.workoutFinished]
    }
}

/// A target for a single run.
public enum RunGoal: Codable, Hashable, Sendable {
    /// Meters.
    case distance(Double)
    /// Seconds.
    case time(TimeInterval)
    /// Target average pace in seconds per meter.
    case pace(Double)
}

public struct GoalProgress: Sendable {
    public enum Event: Equatable, Sendable {
        case halfway
        case completed
    }

    public let goal: RunGoal
    public private(set) var fraction: Double = 0
    private var announcedHalfway = false
    private var announcedComplete = false

    public init(goal: RunGoal) {
        self.goal = goal
    }

    public var isComplete: Bool { announcedComplete }

    public mutating func update(elapsed: TimeInterval, distance: Double) -> [Event] {
        switch goal {
        case .distance(let target):
            fraction = target > 0 ? min(1, distance / target) : 1
        case .time(let target):
            fraction = target > 0 ? min(1, elapsed / target) : 1
        case .pace:
            // A pace goal has no finish line.
            fraction = 0
            return []
        }
        var events: [Event] = []
        if fraction >= 0.5, !announcedHalfway {
            announcedHalfway = true
            if fraction < 1 { events.append(.halfway) }
        }
        if fraction >= 1, !announcedComplete {
            announcedComplete = true
            events.append(.completed)
        }
        return events
    }

    /// For pace goals: seconds per meter the runner is ahead (negative) or behind (positive) target.
    public static func paceDelta(target: Double, elapsed: TimeInterval, distance: Double) -> Double? {
        guard distance >= 50 else { return nil }
        return elapsed / distance - target
    }
}
