import Foundation

/// One sample from an activity file.
public struct FITRecord: Equatable, Sendable {
    public var time: Date
    public var latitude: Double?
    public var longitude: Double?
    /// Meters.
    public var altitude: Double?
    public var heartRate: Double?
    /// Cumulative meters as measured by the device.
    public var distance: Double?
    public var cadence: Double?
}

/// Device-computed totals for the activity.
public struct FITSession: Equatable, Sendable {
    /// FIT sport code; 1 is running.
    public var sport: Int?
    public var startTime: Date?
    /// Seconds with the timer running (pauses excluded).
    public var totalTimerTime: Double?
    public var totalElapsedTime: Double?
    public var totalDistance: Double?
    public var totalCalories: Double?
    public var totalAscent: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
}

/// The timer being started or stopped (manual pause, auto-pause, end).
public struct FITTimerEvent: Equatable, Sendable {
    public var time: Date
    public var isStart: Bool
}

public struct FITFile: Equatable, Sendable {
    public var records: [FITRecord] = []
    public var session: FITSession?
    public var timerEvents: [FITTimerEvent] = []
    /// Sport code from the sport message, when the session doesn't carry one.
    public var sport: Int?
}

public enum FITError: Error, Equatable {
    case notAFITFile
    case corrupt
}

/// Decoder for Garmin's FIT activity format. Reads the messages a run needs
/// (record, session, event, sport) and skips everything else. A file that was cut
/// short yields the messages before the cut.
public enum FITDecoder {
    /// Seconds between the Unix epoch and the FIT epoch (1989-12-31 00:00:00 UTC).
    static let epochOffset: TimeInterval = 631_065_600

    private struct Field {
        var number: Int
        var size: Int
        var baseType: UInt8
    }

    private struct Definition {
        var global: Int
        var bigEndian: Bool
        var fields: [Field]
        var developerBytes: Int
        var size: Int
    }

    public static func decode(_ bytes: [UInt8]) throws -> FITFile {
        guard bytes.count >= 14 else { throw FITError.notAFITFile }
        let headerSize = Int(bytes[0])
        guard headerSize >= 12, bytes.count >= headerSize,
              bytes[8] == 0x2E, bytes[9] == 0x46, bytes[10] == 0x49, bytes[11] == 0x54 else {
            throw FITError.notAFITFile
        }
        let dataSize = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
        let end = min(bytes.count, headerSize + dataSize)

        var file = FITFile()
        var definitions: [Int: Definition] = [:]
        var lastTimestamp: UInt32 = 0
        var position = headerSize

        while position < end {
            let header = bytes[position]
            position += 1

            if header & 0x80 != 0 {
                // Compressed timestamp: 5-bit offset from the previous timestamp.
                let local = Int((header >> 5) & 0x03)
                let offset = UInt32(header & 0x1F)
                guard let definition = definitions[local] else { throw FITError.corrupt }
                var timestamp = (lastTimestamp & ~UInt32(0x1F)) &+ offset
                if offset < (lastTimestamp & 0x1F) { timestamp = timestamp &+ 0x20 }
                lastTimestamp = timestamp
                try readData(bytes, &position, end, definition, timestampOverride: timestamp,
                             lastTimestamp: &lastTimestamp, into: &file)
            } else if header & 0x40 != 0 {
                let local = Int(header & 0x0F)
                guard position + 5 <= end else { break }
                let bigEndian = bytes[position + 1] == 1
                let global = bigEndian
                    ? Int(bytes[position + 2]) << 8 | Int(bytes[position + 3])
                    : Int(bytes[position + 2]) | Int(bytes[position + 3]) << 8
                let fieldCount = Int(bytes[position + 4])
                position += 5
                guard position + fieldCount * 3 <= end else { break }
                var fields: [Field] = []
                var size = 0
                for _ in 0..<fieldCount {
                    let field = Field(number: Int(bytes[position]), size: Int(bytes[position + 1]), baseType: bytes[position + 2])
                    fields.append(field)
                    size += field.size
                    position += 3
                }
                var developerBytes = 0
                if header & 0x20 != 0 {
                    guard position < end else { break }
                    let developerCount = Int(bytes[position])
                    position += 1
                    guard position + developerCount * 3 <= end else { position = end; break }
                    for _ in 0..<developerCount {
                        developerBytes += Int(bytes[position + 1])
                        position += 3
                    }
                }
                definitions[local] = Definition(global: global, bigEndian: bigEndian, fields: fields,
                                                developerBytes: developerBytes, size: size)
            } else {
                let local = Int(header & 0x0F)
                guard let definition = definitions[local] else { throw FITError.corrupt }
                try readData(bytes, &position, end, definition, timestampOverride: nil,
                             lastTimestamp: &lastTimestamp, into: &file)
            }
        }
        return file
    }

    /// Width in bytes of one value of each base type, indexed by the type's low five bits.
    private static let baseTypeSizes = [1, 1, 1, 2, 2, 4, 4, 1, 4, 8, 1, 2, 4, 1, 8, 8, 8]

    private static func readData(_ bytes: [UInt8], _ position: inout Int, _ end: Int, _ definition: Definition,
                                 timestampOverride: UInt32?, lastTimestamp: inout UInt32, into file: inout FITFile) throws {
        guard position + definition.size + definition.developerBytes <= end else {
            // Cut short mid-message: keep what was read so far.
            position = end
            return
        }
        let wanted = definition.global == 20 || definition.global == 18 || definition.global == 21 || definition.global == 12

        var values: [Int: Int64] = [:]
        var cursor = position
        for field in definition.fields {
            defer { cursor += field.size }
            // The timestamp is tracked for every message so compressed headers stay in step.
            guard wanted || field.number == 253 else { continue }
            if let value = integer(bytes, at: cursor, field: field, bigEndian: definition.bigEndian) {
                values[field.number] = value
            }
        }
        position += definition.size + definition.developerBytes

        if let raw = values[253] { lastTimestamp = UInt32(truncatingIfNeeded: raw) }
        let timestamp: Date? = (timestampOverride.map { Int64($0) } ?? values[253]).map(date)

        switch definition.global {
        case 20:
            guard let timestamp else { return }
            var record = FITRecord(time: timestamp)
            if let lat = values[0], let lon = values[1] {
                record.latitude = Double(lat) * 180 / 2_147_483_648
                record.longitude = Double(lon) * 180 / 2_147_483_648
            }
            if let altitude = values[78] ?? values[2] { record.altitude = Double(altitude) / 5 - 500 }
            if let heartRate = values[3] { record.heartRate = Double(heartRate) }
            if let cadence = values[4] { record.cadence = Double(cadence) }
            if let distance = values[5] { record.distance = Double(distance) / 100 }
            file.records.append(record)
        case 18:
            var session = FITSession()
            session.sport = values[5].map { Int($0) }
            session.startTime = values[2].map(date)
            session.totalElapsedTime = values[7].map { Double($0) / 1000 }
            session.totalTimerTime = values[8].map { Double($0) / 1000 }
            session.totalDistance = values[9].map { Double($0) / 100 }
            session.totalCalories = values[11].map { Double($0) }
            session.averageHeartRate = values[16].map { Double($0) }
            session.maxHeartRate = values[17].map { Double($0) }
            session.totalAscent = values[22].map { Double($0) }
            // Multisport files have several sessions; keep the first.
            if file.session == nil { file.session = session }
        case 21:
            // Event 0 is the timer; type 0 starts it, 1 and 4 stop it.
            guard let timestamp, values[0] == 0, let type = values[1] else { return }
            if type == 0 {
                file.timerEvents.append(FITTimerEvent(time: timestamp, isStart: true))
            } else if type == 1 || type == 4 {
                file.timerEvents.append(FITTimerEvent(time: timestamp, isStart: false))
            }
        case 12:
            if file.sport == nil { file.sport = values[0].map { Int($0) } }
        default:
            break
        }
    }

    private static func date(_ fitSeconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(fitSeconds) + epochOffset)
    }

    /// Reads a single integer field, returning nil for invalid markers, arrays,
    /// strings and floating-point fields.
    private static func integer(_ bytes: [UInt8], at offset: Int, field: Field, bigEndian: Bool) -> Int64? {
        let type = Int(field.baseType & 0x1F)
        guard type < baseTypeSizes.count, type != 7, type != 8, type != 9, type != 13 else { return nil }
        let size = baseTypeSizes[type]
        guard field.size == size, size <= 4 else { return nil }

        var raw: UInt64 = 0
        for index in 0..<size {
            let byte = UInt64(bytes[offset + (bigEndian ? index : size - 1 - index)])
            raw = raw << 8 | byte
        }
        let bits = UInt64(size * 8)
        let allOnes: UInt64 = (1 << bits) - 1
        let isSigned = type == 1 || type == 3 || type == 5
        let isZeroInvalid = type == 10 || type == 11 || type == 12

        if isSigned {
            // Invalid marker is the largest positive value.
            if raw == allOnes >> 1 { return nil }
            let signBit: UInt64 = 1 << (bits - 1)
            return raw & signBit != 0 ? Int64(raw) - Int64(allOnes) - 1 : Int64(raw)
        }
        if isZeroInvalid ? raw == 0 : raw == allOnes { return nil }
        return Int64(raw)
    }
}
