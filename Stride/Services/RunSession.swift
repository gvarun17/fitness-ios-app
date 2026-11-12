import Foundation
import CoreLocation
import HealthKit
import UIKit
import RunCore

enum RunMode: Hashable {
    case free
    case goal(RunGoal)
    case intervals(IntervalWorkout)
}

/// Everything decided before the run starts.
struct RunSetup: Identifiable, Hashable {
    let id = UUID()
    var mode: RunMode = .free
    var tag: RunTag = .easy
    var plannedWorkoutID: String?
    var shoeID: UUID?
}

/// The result of a completed run, ready to be stored.
struct FinishedRun {
    var setup: RunSetup
    var startDate: Date
    var endDate: Date
    var duration: TimeInterval
    var distance: Double
    var elevationGain: Double
    var points: [TrackPoint]
    var pauseIntervals: [DateInterval]
    var heartRates: [HeartRateSample]
}

/// Drives a live run: feeds GPS into the tracker, publishes metrics for the UI,
/// and triggers audio cues.
final class RunSession: ObservableObject {
    enum Phase: Equatable {
        case countdown(Int)
        case active
        case finished
    }

    let setup: RunSetup
    let unit: DistanceUnit

    @Published private(set) var phase: Phase = .countdown(3)
    @Published private(set) var state: RunTracker.State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var distance: Double = 0
    @Published private(set) var currentPace: Double?
    @Published private(set) var averagePace: Double?
    @Published private(set) var elevationGain: Double = 0
    @Published private(set) var heartRate: Double?
    @Published private(set) var splits: [Split] = []
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var gpsAccuracy: Double?
    @Published private(set) var locationDenied = false
    @Published private(set) var interval: IntervalProgress?
    @Published private(set) var goal: GoalProgress?

    private var tracker: RunTracker
    private let location = LocationService()
    private let coach = AudioCoach()
    private var timer: Timer?
    private var heartRateQuery: HKQuery?
    private var heartRates: [HeartRateSample] = []
    private var lastHeartRateDate: Date?
    private var hasStarted = false
    private let cueEverySplits: Int
    private let weightKg: Double

    init(setup: RunSetup) {
        self.setup = setup
        self.unit = AppSettings.unit
        self.cueEverySplits = AppSettings.cueEverySplits
        self.weightKg = AppSettings.weightKg

        var config = RunTracker.Config()
        config.splitLength = AppSettings.unit.meters
        config.autoPause = AppSettings.autoPause
        self.tracker = RunTracker(config: config)
        self.coach.isEnabled = AppSettings.audioCues

        switch setup.mode {
        case .free:
            break
        case .goal(let goal):
            self.goal = GoalProgress(goal: goal)
        case .intervals(let workout):
            self.interval = IntervalProgress(workout: workout)
        }
    }

    var calories: Double {
        Calories.estimate(distanceMeters: distance, weightKg: weightKg)
    }

    /// Target pace (seconds per meter) when running to a pace goal.
    var targetPace: Double? {
        if case .goal(.pace(let pace)) = setup.mode { return pace }
        return nil
    }

    var totalRunSteps: Int { interval?.workout.runStepCount ?? 0 }

    // MARK: Lifecycle

    /// Begins GPS warm-up and the countdown. Safe to call more than once.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        location.onLocations = { [weak self] locations in
            self?.handle(locations)
        }
        location.startTracking()
        if AppSettings.keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if AppSettings.countdown {
            phase = .countdown(3)
            countdownStarted = Date()
        } else {
            begin()
        }
    }

    private var countdownStarted: Date?

    /// Skips whatever is left of the countdown.
    func skipCountdown() {
        if case .countdown = phase { begin() }
    }

    private func begin() {
        let now = Date()
        tracker.start(at: now)
        phase = .active
        if AppSettings.healthEnabled {
            heartRateQuery = HealthService.shared.startHeartRateUpdates(from: now) { [weak self] bpm, date in
                self?.recordHeartRate(bpm, at: date)
            }
        }
        if let step = interval?.currentStep {
            coach.speak("Workout started. " + SpeechText.stepStarted(step, repeatNumber: 1, totalRepeats: totalRunSteps, unit: unit))
        } else {
            coach.speak("Run started.")
        }
        refresh(at: now)
    }

    func pause() {
        tracker.pause(at: Date())
        coach.speak("Run paused.")
        refresh(at: Date())
    }

    func resume() {
        tracker.resume(at: Date())
        coach.speak("Run resumed.")
        refresh(at: Date())
    }

    func skipIntervalStep() {
        guard var progress = interval else { return }
        let events = progress.skip()
        interval = progress
        handle(events, progress: progress)
    }

    /// Ends the run and returns what was recorded. Returns nil if the run never started.
    func finish() -> FinishedRun? {
        let now = Date()
        let wasStarted = tracker.startDate != nil
        tracker.finish(at: now)
        tearDown()
        phase = .finished
        guard wasStarted, let startDate = tracker.startDate else { return nil }
        refresh(at: now)
        coach.speak("Run complete. \(SpeechText.distance(tracker.distance, unit: unit)) in \(SpeechText.duration(tracker.elapsed(at: now))).")
        return FinishedRun(setup: setup,
                           startDate: startDate,
                           endDate: now,
                           duration: tracker.elapsed(at: now),
                           distance: tracker.distance,
                           elevationGain: tracker.elevationGain,
                           points: tracker.points,
                           pauseIntervals: tracker.pauseIntervals,
                           heartRates: heartRates)
    }

    /// Abandons the session without recording anything.
    func cancel() {
        tearDown()
        coach.stop()
        phase = .finished
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        location.stopTracking()
        location.onLocations = nil
        HealthService.shared.stop(heartRateQuery)
        heartRateQuery = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: Input

    private func tick() {
        let now = Date()
        locationDenied = location.isDenied
        switch phase {
        case .countdown:
            let passed = now.timeIntervalSince(countdownStarted ?? now)
            let remaining = 3 - Int(passed)
            if remaining <= 0 {
                begin()
            } else if phase != .countdown(remaining) {
                phase = .countdown(remaining)
            }
        case .active:
            handle(tracker.tick(at: now))
            refresh(at: now)
        case .finished:
            break
        }
    }

    private func handle(_ locations: [CLLocation]) {
        guard phase != .finished else { return }
        if let last = locations.last, last.horizontalAccuracy >= 0 {
            gpsAccuracy = last.horizontalAccuracy
        }
        guard phase == .active else { return }
        var events: [RunTracker.Event] = []
        let before = tracker.points.count
        for fix in locations {
            events += tracker.add(LocationSample(latitude: fix.coordinate.latitude,
                                                 longitude: fix.coordinate.longitude,
                                                 altitude: fix.altitude,
                                                 horizontalAccuracy: fix.horizontalAccuracy,
                                                 verticalAccuracy: fix.verticalAccuracy,
                                                 speed: fix.speed,
                                                 timestamp: fix.timestamp))
        }
        if tracker.points.count > before {
            route.append(contentsOf: tracker.points[before...].map(\.coordinate))
        }
        handle(events)
        refresh(at: Date())
    }

    private func recordHeartRate(_ bpm: Double, at date: Date) {
        guard phase == .active, let start = tracker.startDate, bpm > 0 else { return }
        if let last = lastHeartRateDate, date <= last { return }
        lastHeartRateDate = date
        heartRate = bpm
        heartRates.append(HeartRateSample(t: date.timeIntervalSince(start), bpm: bpm))
    }

    // MARK: Output

    private func refresh(at now: Date) {
        state = tracker.state
        elapsed = tracker.elapsed(at: now)
        distance = tracker.distance
        elevationGain = tracker.elevationGain
        currentPace = tracker.currentPace(at: now)
        averagePace = tracker.averagePace(at: now)
        if splits.count != tracker.splits.count {
            splits = tracker.splits
        }

        if var progress = interval, !progress.isFinished {
            let events = progress.update(elapsed: elapsed, distance: distance)
            interval = progress
            handle(events, progress: progress)
        }
        if var progress = goal, !progress.isComplete {
            let events = progress.update(elapsed: elapsed, distance: distance)
            goal = progress
            for event in events {
                switch event {
                case .halfway:
                    coach.speak("Halfway there.")
                case .completed:
                    notify(.success)
                    coach.speak("Goal reached. \(SpeechText.distance(distance, unit: unit)) in \(SpeechText.duration(elapsed)).")
                }
            }
        }
    }

    private func handle(_ events: [RunTracker.Event]) {
        for event in events {
            switch event {
            case .split(let split):
                guard split.index % cueEverySplits == 0 else { continue }
                // The split closed exactly at a whole number of units.
                let total = Double(split.index) * tracker.config.splitLength
                let elapsedAtSplit = tracker.splits.reduce(0) { $0 + $1.duration }
                coach.speak(SpeechText.split(totalDistance: total, elapsed: elapsedAtSplit, split: split,
                                             unit: unit, targetPace: targetPace))
            case .autoPaused:
                coach.speak("Paused.")
            case .autoResumed:
                coach.speak("Resumed.")
            }
        }
    }

    private func handle(_ events: [IntervalProgress.Event], progress: IntervalProgress) {
        for event in events {
            switch event {
            case .stepStarted(let index):
                notify(.warning)
                let step = progress.workout.steps[index]
                let repeatNumber = progress.workout.steps[0...index].filter { $0.kind == .run }.count
                coach.speak(SpeechText.stepStarted(step, repeatNumber: repeatNumber, totalRepeats: totalRunSteps, unit: unit))
            case .workoutFinished:
                notify(.success)
                coach.speak("Workout complete. Keep going or finish your run.")
            }
        }
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
