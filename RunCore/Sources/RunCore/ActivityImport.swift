import Foundation

/// A heart rate reading at `t` seconds after the run started.
public struct HeartRatePoint: Equatable, Sendable {
    public var t: Double
    public var bpm: Double

    public init(t: Double, bpm: Double) {
        self.t = t
        self.bpm = bpm
    }
}

/// A run recorded elsewhere, converted to the shape this app stores.
public struct ImportedRun: Equatable, Sendable {
    public var startDate: Date
    public var endDate: Date
    /// Active seconds, pauses excluded.
    public var duration: TimeInterval
    public var distance: Double
    public var elevationGain: Double
    public var calories: Double?
    public var points: [TrackPoint]
    public var heartRates: [HeartRatePoint]
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    /// False when the file says it is some other sport.
    public var isRun: Bool
}

public enum ActivityImport {
    /// Converts a decoded activity file. Returns nil when it holds no usable data.
    public static func run(from file: FITFile) -> ImportedRun? {
        let records = file.records.sorted { $0.time < $1.time }
        let session = file.session
        guard let start = session?.startTime ?? records.first?.time else { return nil }

        // Stretches when the watch's timer was stopped.
        var pauses: [(start: Date, end: Date)] = []
        var stoppedAt: Date?
        for event in file.timerEvents.sorted(by: { $0.time < $1.time }) {
            if event.isStart {
                if let stopped = stoppedAt, event.time > stopped { pauses.append((stopped, event.time)) }
                stoppedAt = nil
            } else if stoppedAt == nil {
                stoppedAt = event.time
            }
        }

        func activeElapsed(at time: Date) -> Double {
            var paused = 0.0
            for pause in pauses where pause.start < time {
                paused += min(pause.end, time).timeIntervalSince(max(pause.start, start))
            }
            if let stopped = stoppedAt, stopped < time { paused += time.timeIntervalSince(stopped) }
            return max(0, time.timeIntervalSince(start) - max(0, paused))
        }

        var points: [TrackPoint] = []
        var heartRates: [HeartRatePoint] = []
        var computedDistance = 0.0
        var lastPositioned: FITRecord?
        var lastAltitude = 0.0
        var lastHeartRateTime = -Double.infinity
        var smoothedAltitude: Double?
        var altitudeReference: Double?
        var computedGain = 0.0

        for record in records {
            if let bpm = record.heartRate, bpm > 0 {
                let t = record.time.timeIntervalSince(start)
                if t - lastHeartRateTime >= 4 {
                    heartRates.append(HeartRatePoint(t: max(0, t), bpm: bpm))
                    lastHeartRateTime = t
                }
            }
            guard let lat = record.latitude, let lon = record.longitude,
                  abs(lat) <= 90, abs(lon) <= 180, !(lat == 0 && lon == 0) else { continue }

            let elapsed = activeElapsed(at: record.time)
            if let previous = lastPositioned, let pLat = previous.latitude, let pLon = previous.longitude {
                // Movement while the timer was stopped doesn't count.
                if elapsed > (points.last?.e ?? 0) {
                    computedDistance += Geo.distance(lat1: pLat, lon1: pLon, lat2: lat, lon2: lon)
                }
            }
            lastPositioned = record

            if let altitude = record.altitude {
                let smoothed = smoothedAltitude.map { $0 + 0.3 * (altitude - $0) } ?? altitude
                smoothedAltitude = smoothed
                lastAltitude = smoothed
                if let reference = altitudeReference {
                    if smoothed - reference >= 3 {
                        computedGain += smoothed - reference
                        altitudeReference = smoothed
                    } else if smoothed - reference <= -3 {
                        altitudeReference = smoothed
                    }
                } else {
                    altitudeReference = smoothed
                }
            }

            // Prefer the watch's own distance; it accounts for its GPS smoothing.
            let distance = max(record.distance ?? computedDistance, points.last?.d ?? 0)
            points.append(TrackPoint(lat: lat, lon: lon, alt: lastAltitude, time: record.time,
                                     d: distance, e: max(elapsed, points.last?.e ?? 0)))
        }

        let lastRecordDistance = records.last(where: { $0.distance != nil })?.distance
        let distance = session?.totalDistance ?? lastRecordDistance ?? points.last?.d ?? 0
        let end = records.last?.time ?? start.addingTimeInterval(session?.totalElapsedTime ?? 0)
        let duration = session?.totalTimerTime ?? activeElapsed(at: end)
        guard distance > 0 || duration > 0 else { return nil }

        let bpmValues = heartRates.map(\.bpm)
        let average = session?.averageHeartRate
            ?? (bpmValues.isEmpty ? nil : bpmValues.reduce(0, +) / Double(bpmValues.count))
        let sport = session?.sport ?? file.sport

        return ImportedRun(startDate: start,
                           endDate: end,
                           duration: duration,
                           distance: distance,
                           elevationGain: session?.totalAscent ?? computedGain,
                           calories: session?.totalCalories,
                           points: points,
                           heartRates: heartRates,
                           averageHeartRate: average,
                           maxHeartRate: session?.maxHeartRate ?? bpmValues.max(),
                           isRun: sport == nil || sport == 1)
    }
}

/// One file inside a ZIP archive, still compressed.
public struct ZipEntry: Equatable, Sendable {
    public var name: String
    /// 0 is stored (no compression); 8 is DEFLATE.
    public var method: Int
    public var data: [UInt8]
    public var uncompressedSize: Int
}

/// Reads the directory of a ZIP archive. Decompression is left to the caller.
public enum ZipArchive {
    public static func isZip(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04
    }

    public static func entries(_ bytes: [UInt8]) -> [ZipEntry]? {
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }

        // The end-of-central-directory record sits at the end, before an optional comment.
        guard bytes.count >= 22 else { return nil }
        var eocd = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while eocd >= lowest {
            if bytes[eocd] == 0x50, bytes[eocd + 1] == 0x4B, bytes[eocd + 2] == 0x05, bytes[eocd + 3] == 0x06 { break }
            eocd -= 1
        }
        guard eocd >= lowest else { return nil }
        let count = u16(eocd + 10)
        var position = u32(eocd + 16)

        var entries: [ZipEntry] = []
        for _ in 0..<count {
            guard position + 46 <= bytes.count, u32(position) == 0x0201_4B50 else { return nil }
            let method = u16(position + 10)
            let compressedSize = u32(position + 20)
            let uncompressedSize = u32(position + 24)
            let nameLength = u16(position + 28)
            let extraLength = u16(position + 30)
            let commentLength = u16(position + 32)
            let localHeader = u32(position + 42)
            guard position + 46 + nameLength <= bytes.count else { return nil }
            let name = String(decoding: bytes[(position + 46)..<(position + 46 + nameLength)], as: UTF8.self)
            position += 46 + nameLength + extraLength + commentLength

            guard localHeader + 30 <= bytes.count, u32(localHeader) == 0x0403_4B50 else { return nil }
            let dataStart = localHeader + 30 + u16(localHeader + 26) + u16(localHeader + 28)
            guard dataStart + compressedSize <= bytes.count else { return nil }
            entries.append(ZipEntry(name: name, method: method,
                                    data: Array(bytes[dataStart..<(dataStart + compressedSize)]),
                                    uncompressedSize: uncompressedSize))
        }
        return entries
    }
}
