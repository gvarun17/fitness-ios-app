import Foundation

public struct Split: Codable, Equatable, Identifiable, Sendable {
    /// 1-based split number.
    public var index: Int
    /// Meters covered in this split (shorter than a full unit for the final partial split).
    public var distance: Double
    /// Active seconds spent on this split.
    public var duration: TimeInterval
    /// Net altitude change in meters over the split.
    public var elevationChange: Double
    public var isPartial: Bool

    public var id: Int { index }
    public var secondsPerMeter: Double? { distance > 0 ? duration / distance : nil }

    public init(index: Int, distance: Double, duration: TimeInterval, elevationChange: Double, isPartial: Bool) {
        self.index = index
        self.distance = distance
        self.duration = duration
        self.elevationChange = elevationChange
        self.isPartial = isPartial
    }
}

public enum SplitCalculator {
    /// Splits of `splitLength` meters over a recorded track. A trailing partial split
    /// is included when it is at least `minimumPartial` meters long.
    public static func splits(points: [TrackPoint], splitLength: Double, minimumPartial: Double = 50) -> [Split] {
        guard splitLength > 0, let last = points.last, points.count >= 2 else { return [] }
        var result: [Split] = []
        var boundary = splitLength
        var startElapsed = 0.0
        var startAlt = points[0].alt
        var prev = points[0]

        for point in points.dropFirst() {
            while point.d >= boundary && point.d > prev.d {
                let fraction = (boundary - prev.d) / (point.d - prev.d)
                let elapsedAtBoundary = prev.e + fraction * (point.e - prev.e)
                let altAtBoundary = prev.alt + fraction * (point.alt - prev.alt)
                result.append(Split(index: result.count + 1,
                                    distance: splitLength,
                                    duration: elapsedAtBoundary - startElapsed,
                                    elevationChange: altAtBoundary - startAlt,
                                    isPartial: false))
                startElapsed = elapsedAtBoundary
                startAlt = altAtBoundary
                boundary += splitLength
            }
            prev = point
        }

        let remaining = last.d - (boundary - splitLength)
        if remaining >= minimumPartial {
            result.append(Split(index: result.count + 1,
                                distance: remaining,
                                duration: last.e - startElapsed,
                                elevationChange: last.alt - startAlt,
                                isPartial: true))
        }
        return result
    }
}

/// A named distance we track personal records for.
public struct RecordDistance: Hashable, Identifiable, Sendable {
    public var name: String
    public var meters: Double
    public var id: Int { Int(meters.rounded()) }

    public static let all: [RecordDistance] = [
        RecordDistance(name: "1K", meters: 1000),
        RecordDistance(name: "1 Mile", meters: 1609.344),
        RecordDistance(name: "5K", meters: 5000),
        RecordDistance(name: "10K", meters: 10000),
        RecordDistance(name: "Half Marathon", meters: 21097.5),
        RecordDistance(name: "Marathon", meters: 42195)
    ]
}

public enum BestEfforts {
    /// Fastest active time over any continuous stretch of `target` meters, or nil if
    /// the run was shorter than that.
    public static func fastest(points: [TrackPoint], target: Double) -> TimeInterval? {
        guard target > 0, let last = points.last, last.d >= target else { return nil }
        // Work on (distance, elapsed) pairs starting from the origin.
        var d: [Double] = [0]
        var e: [Double] = [0]
        for p in points where p.d > d[d.count - 1] {
            d.append(p.d)
            e.append(max(p.e, e[e.count - 1]))
        }
        var best: TimeInterval?
        var i = 0
        for j in 1..<d.count where d[j] >= target {
            let startDistance = d[j] - target
            while i + 1 < j && d[i + 1] <= startDistance { i += 1 }
            let span = d[i + 1] - d[i]
            let fraction = span > 0 ? (startDistance - d[i]) / span : 0
            let startElapsed = e[i] + fraction * (e[i + 1] - e[i])
            let time = e[j] - startElapsed
            if time > 0, best == nil || time < best! { best = time }
        }
        return best
    }

    /// Best efforts for every standard record distance the run covers, keyed by `RecordDistance.id`.
    public static func all(points: [TrackPoint]) -> [Int: TimeInterval] {
        var out: [Int: TimeInterval] = [:]
        for record in RecordDistance.all {
            if let t = fastest(points: points, target: record.meters) { out[record.id] = t }
        }
        return out
    }
}

public struct ChartSample: Identifiable, Equatable, Sendable {
    /// Distance from the start in meters.
    public var distance: Double
    public var value: Double
    public var id: Double { distance }

    public init(distance: Double, value: Double) {
        self.distance = distance
        self.value = value
    }
}

public enum ChartSeries {
    /// Pace (seconds per meter) averaged over consecutive buckets of the route.
    public static func pace(points: [TrackPoint], buckets: Int = 60) -> [ChartSample] {
        guard let last = points.last, last.d > 0, buckets > 0, points.count >= 2 else { return [] }
        let bucketLength = max(last.d / Double(buckets), 25)
        return SplitCalculator.splits(points: points, splitLength: bucketLength, minimumPartial: bucketLength / 2)
            .compactMap { split in
                guard let pace = split.secondsPerMeter, pace > 0 else { return nil }
                let end = Double(split.index - 1) * bucketLength + split.distance
                return ChartSample(distance: end - split.distance / 2, value: pace)
            }
    }

    /// Altitude along the route, downsampled.
    public static func elevation(points: [TrackPoint], maxSamples: Int = 120) -> [ChartSample] {
        guard points.count >= 2, maxSamples > 0 else { return [] }
        let step = max(1, Int((Double(points.count) / Double(maxSamples)).rounded(.up)))
        var out: [ChartSample] = []
        var i = 0
        while i < points.count {
            // Small moving average to hide GPS altitude noise.
            let lo = max(0, i - 2), hi = min(points.count - 1, i + 2)
            let avg = points[lo...hi].map(\.alt).reduce(0, +) / Double(hi - lo + 1)
            if out.last?.distance != points[i].d {
                out.append(ChartSample(distance: points[i].d, value: avg))
            }
            i += step
        }
        return out
    }
}
