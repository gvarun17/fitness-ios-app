import Foundation

/// One reading from a Bluetooth heart rate sensor (Heart Rate Measurement, 0x2A37).
public struct HeartRateReading: Equatable, Sendable {
    /// Beats per minute, or nil when the sensor reports no skin contact or no value.
    public var bpm: Double?
    /// Beat-to-beat intervals in seconds, when the sensor sends them.
    public var rrIntervals: [Double]

    public init(bpm: Double?, rrIntervals: [Double] = []) {
        self.bpm = bpm
        self.rrIntervals = rrIntervals
    }

    /// Decodes the standard measurement payload. Returns nil if it is malformed.
    public static func parse(_ bytes: [UInt8]) -> HeartRateReading? {
        guard bytes.count >= 2 else { return nil }
        let flags = bytes[0]
        let isSixteenBit = flags & 0x01 != 0
        let contactSupported = flags & 0x04 != 0
        let contactDetected = flags & 0x02 != 0
        let hasEnergy = flags & 0x08 != 0
        let hasRR = flags & 0x10 != 0

        var index = 1
        let raw: Int
        if isSixteenBit {
            guard bytes.count >= 3 else { return nil }
            raw = Int(bytes[1]) | Int(bytes[2]) << 8
            index = 3
        } else {
            raw = Int(bytes[1])
            index = 2
        }
        if hasEnergy { index += 2 }

        var rr: [Double] = []
        if hasRR {
            while index + 1 < bytes.count {
                let value = Int(bytes[index]) | Int(bytes[index + 1]) << 8
                rr.append(Double(value) / 1024)
                index += 2
            }
        }

        let lostContact = contactSupported && !contactDetected
        let valid = raw > 0 && raw < 255 && !lostContact
        return HeartRateReading(bpm: valid ? Double(raw) : nil, rrIntervals: rr)
    }
}

public enum HeartRateZones {
    public static let names = ["Recovery", "Easy", "Aerobic", "Threshold", "Maximum"]

    /// Zone 1...5 by percentage of maximum heart rate (60/70/80/90% boundaries).
    public static func zone(bpm: Double, maxHeartRate: Double) -> Int {
        guard maxHeartRate > 0 else { return 1 }
        let fraction = bpm / maxHeartRate
        if fraction >= 0.9 { return 5 }
        if fraction >= 0.8 { return 4 }
        if fraction >= 0.7 { return 3 }
        if fraction >= 0.6 { return 2 }
        return 1
    }

    /// Lower bound in bpm of each zone, zone 1 first.
    public static func lowerBounds(maxHeartRate: Double) -> [Int] {
        [0.5, 0.6, 0.7, 0.8, 0.9].map { Int((maxHeartRate * $0).rounded()) }
    }

    /// Seconds spent in each zone. `samples` are (seconds since start, bpm) in time order.
    /// Gaps longer than `maxGap` (sensor dropouts, pauses) are not counted.
    public static func timeInZones(samples: [(t: Double, bpm: Double)], maxHeartRate: Double,
                                   maxGap: Double = 30) -> [Double] {
        var totals = [Double](repeating: 0, count: 5)
        for (current, next) in zip(samples, samples.dropFirst()) {
            let gap = next.t - current.t
            guard gap > 0, gap <= maxGap else { continue }
            totals[zone(bpm: current.bpm, maxHeartRate: maxHeartRate) - 1] += gap
        }
        return totals
    }
}
