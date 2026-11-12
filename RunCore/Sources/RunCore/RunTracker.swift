import Foundation

/// Turns a stream of location fixes into run metrics. Pure value type: the caller
/// supplies the clock, so it can be driven by real GPS or by tests.
public struct RunTracker: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case running
        /// Paused by the runner.
        case paused
        /// Paused automatically because the runner stopped moving.
        case autoPaused
        case finished
    }

    public enum Event: Equatable, Sendable {
        case split(Split)
        case autoPaused
        case autoResumed
    }

    public struct Config: Sendable {
        /// Length of one split in meters.
        public var splitLength: Double = 1000
        public var autoPause: Bool = true
        /// Fixes less accurate than this (meters) are ignored.
        public var maxHorizontalAccuracy: Double = 30
        /// Movement below this (meters) from the last recorded point is treated as GPS jitter.
        public var minimumMovement: Double = 3
        /// Implied speeds above this (m/s) are treated as GPS jumps.
        public var maxSpeed: Double = 12
        /// Seconds without movement before auto-pause kicks in.
        public var autoPauseDelay: TimeInterval = 6
        /// Meters of movement needed to auto-resume.
        public var autoResumeDistance: Double = 8
        /// Altitude change (meters) needed before it counts toward elevation gain.
        public var elevationThreshold: Double = 3

        public init() {}
    }

    public var config: Config
    public private(set) var state: State = .idle
    public private(set) var points: [TrackPoint] = []
    public private(set) var distance: Double = 0
    public private(set) var elevationGain: Double = 0
    public private(set) var splits: [Split] = []
    public private(set) var startDate: Date?
    public private(set) var endDate: Date?
    /// Wall-clock intervals during which the run was paused (manual or automatic).
    public private(set) var pauseIntervals: [DateInterval] = []

    private var accumulatedElapsed: TimeInterval = 0
    private var segmentStart: Date?
    private var pauseStart: Date?
    /// Last fix that was recorded or used as a reference for movement.
    private var anchor: LocationSample?
    private var lastMovement: Date?
    /// Time of the last usable fix, so lost signal isn't mistaken for standing still.
    private var lastGoodFix: Date?
    private var smoothedAltitude: Double?
    private var altitudeReference: Double?
    private var nextSplitBoundary: Double
    private var splitStartElapsed: TimeInterval = 0
    private var splitStartAltitude: Double?

    public init(config: Config = Config()) {
        self.config = config
        self.nextSplitBoundary = config.splitLength
    }

    public var isActive: Bool { state == .running }

    // MARK: Lifecycle

    public mutating func start(at date: Date) {
        guard state == .idle else { return }
        state = .running
        startDate = date
        segmentStart = date
        lastMovement = date
    }

    public mutating func pause(at date: Date) {
        switch state {
        case .running:
            closeSegment(at: date)
            pauseStart = date
            state = .paused
        case .autoPaused:
            // Promote to a manual pause so movement no longer resumes the run.
            state = .paused
        default:
            break
        }
    }

    public mutating func resume(at date: Date) {
        guard state == .paused || state == .autoPaused else { return }
        openSegment(at: date)
        state = .running
    }

    public mutating func finish(at date: Date) {
        switch state {
        case .running:
            closeSegment(at: date)
        case .paused, .autoPaused:
            if let pauseStart { pauseIntervals.append(DateInterval(start: pauseStart, end: max(pauseStart, date))) }
            pauseStart = nil
        case .idle, .finished:
            return
        }
        endDate = date
        state = .finished
    }

    // MARK: Metrics

    /// Active (unpaused) seconds as of `date`.
    public func elapsed(at date: Date) -> TimeInterval {
        if state == .running, let segmentStart {
            return accumulatedElapsed + max(0, date.timeIntervalSince(segmentStart))
        }
        return accumulatedElapsed
    }

    /// Average pace in seconds per meter.
    public func averagePace(at date: Date) -> Double? {
        guard distance >= 10 else { return nil }
        return elapsed(at: date) / distance
    }

    /// Pace over roughly the last `window` seconds of movement, in seconds per meter.
    public func currentPace(at date: Date, window: TimeInterval = 20) -> Double? {
        guard state == .running, let last = points.last else { return nil }
        let now = elapsed(at: date)
        // Stale data: no recorded movement recently.
        guard now - last.e < 10 else { return nil }
        let cutoff = last.e - window
        var startIndex = points.count - 1
        while startIndex > 0 && points[startIndex].e > cutoff { startIndex -= 1 }
        let first = points[startIndex]
        let dd = last.d - first.d
        let dt = last.e - first.e
        guard dd >= 8, dt > 0 else { return nil }
        return dt / dd
    }

    /// Meters covered and seconds spent in the split currently in progress.
    public func currentSplitProgress(at date: Date) -> (distance: Double, duration: TimeInterval) {
        (distance - (nextSplitBoundary - config.splitLength), elapsed(at: date) - splitStartElapsed)
    }

    // MARK: Input

    /// Call about once a second. Auto-pauses when recent accurate fixes show the runner
    /// has stopped; a lost GPS signal keeps the clock running instead.
    @discardableResult
    public mutating func tick(at date: Date) -> [Event] {
        guard state == .running, config.autoPause, let lastMovement, let lastGoodFix else { return [] }
        guard date.timeIntervalSince(lastGoodFix) <= 3 else { return [] }
        if date.timeIntervalSince(lastMovement) >= config.autoPauseDelay {
            closeSegment(at: date)
            pauseStart = date
            state = .autoPaused
            return [.autoPaused]
        }
        return []
    }

    @discardableResult
    public mutating func add(_ sample: LocationSample) -> [Event] {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= config.maxHorizontalAccuracy else { return [] }
        guard let startDate, sample.timestamp >= startDate else { return [] }

        switch state {
        case .running:
            return addWhileRunning(sample)
        case .autoPaused:
            return addWhileAutoPaused(sample)
        case .idle, .paused, .finished:
            return []
        }
    }

    private mutating func addWhileRunning(_ sample: LocationSample) -> [Event] {
        // Ignore fixes from before the current segment (e.g. cached fixes after resuming).
        guard let segmentStart, sample.timestamp >= segmentStart else { return [] }
        lastGoodFix = sample.timestamp

        guard let anchor else {
            // First fix of the run or of a resumed segment: record it without adding distance.
            self.anchor = sample
            lastMovement = sample.timestamp
            record(sample, addedDistance: 0)
            return []
        }

        let dt = sample.timestamp.timeIntervalSince(anchor.timestamp)
        guard dt > 0 else { return [] }
        let moved = Geo.distance(lat1: anchor.latitude, lon1: anchor.longitude,
                                 lat2: sample.latitude, lon2: sample.longitude)
        guard moved / dt <= config.maxSpeed else { return [] }

        var events: [Event] = []
        if moved >= config.minimumMovement {
            self.anchor = sample
            lastMovement = sample.timestamp
            events += record(sample, addedDistance: moved)
        }
        events += tick(at: sample.timestamp)
        return events
    }

    private mutating func addWhileAutoPaused(_ sample: LocationSample) -> [Event] {
        guard let anchor else {
            self.anchor = sample
            return []
        }
        guard sample.timestamp > anchor.timestamp else { return [] }
        let moved = Geo.distance(lat1: anchor.latitude, lon1: anchor.longitude,
                                 lat2: sample.latitude, lon2: sample.longitude)
        let movingFast = sample.speed >= 1.5 && sample.horizontalAccuracy <= 15
        guard moved >= config.autoResumeDistance || (movingFast && moved >= config.minimumMovement) else { return [] }
        openSegment(at: sample.timestamp)
        state = .running
        self.anchor = sample
        lastMovement = sample.timestamp
        record(sample, addedDistance: 0)
        return [.autoResumed]
    }

    // MARK: Internals

    private mutating func closeSegment(at date: Date) {
        if let segmentStart {
            accumulatedElapsed += max(0, date.timeIntervalSince(segmentStart))
        }
        segmentStart = nil
    }

    private mutating func openSegment(at date: Date) {
        if let pauseStart {
            pauseIntervals.append(DateInterval(start: pauseStart, end: max(pauseStart, date)))
        }
        pauseStart = nil
        segmentStart = date
        lastMovement = date
        // Whatever happened during the pause must not count as distance.
        anchor = nil
    }

    @discardableResult
    private mutating func record(_ sample: LocationSample, addedDistance: Double) -> [Event] {
        let previous = points.last
        distance += addedDistance
        let elapsedNow = max(elapsed(at: sample.timestamp), previous?.e ?? 0)

        var altitude = previous?.alt ?? sample.altitude
        if sample.verticalAccuracy > 0 {
            let smoothed = smoothedAltitude.map { $0 + 0.3 * (sample.altitude - $0) } ?? sample.altitude
            smoothedAltitude = smoothed
            altitude = smoothed
            if let reference = altitudeReference {
                let delta = smoothed - reference
                if delta >= config.elevationThreshold {
                    elevationGain += delta
                    altitudeReference = smoothed
                } else if delta <= -config.elevationThreshold {
                    altitudeReference = smoothed
                }
            } else {
                altitudeReference = smoothed
            }
        }
        if splitStartAltitude == nil { splitStartAltitude = altitude }

        let point = TrackPoint(lat: sample.latitude, lon: sample.longitude, alt: altitude,
                               time: sample.timestamp, d: distance, e: elapsedNow)
        points.append(point)

        var events: [Event] = []
        if let previous, point.d > previous.d {
            while point.d >= nextSplitBoundary {
                let fraction = (nextSplitBoundary - previous.d) / (point.d - previous.d)
                let elapsedAtBoundary = previous.e + fraction * (point.e - previous.e)
                let altAtBoundary = previous.alt + fraction * (point.alt - previous.alt)
                let split = Split(index: splits.count + 1,
                                  distance: config.splitLength,
                                  duration: elapsedAtBoundary - splitStartElapsed,
                                  elevationChange: altAtBoundary - (splitStartAltitude ?? altAtBoundary),
                                  isPartial: false)
                splits.append(split)
                events.append(.split(split))
                splitStartElapsed = elapsedAtBoundary
                splitStartAltitude = altAtBoundary
                nextSplitBoundary += config.splitLength
            }
        }
        return events
    }
}
