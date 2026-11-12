import Foundation

/// A raw location fix handed to the tracker. Mirrors the parts of CLLocation we use.
public struct LocationSample: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    /// Meters; negative means invalid.
    public var horizontalAccuracy: Double
    /// Meters; zero or negative means the altitude is invalid.
    public var verticalAccuracy: Double
    /// Meters per second; negative means invalid.
    public var speed: Double
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, altitude: Double = 0,
                horizontalAccuracy: Double = 5, verticalAccuracy: Double = 5,
                speed: Double = -1, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.timestamp = timestamp
    }
}

/// A recorded point on a run. Compact keys keep the stored JSON small.
public struct TrackPoint: Codable, Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    /// Altitude in meters.
    public var alt: Double
    /// Wall-clock time of the fix.
    public var time: Date
    /// Cumulative distance in meters at this point.
    public var d: Double
    /// Active (unpaused) elapsed seconds at this point.
    public var e: Double

    public init(lat: Double, lon: Double, alt: Double, time: Date, d: Double, e: Double) {
        self.lat = lat
        self.lon = lon
        self.alt = alt
        self.time = time
        self.d = d
        self.e = e
    }
}

public enum Geo {
    /// Great-circle distance in meters.
    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

public enum RouteThumbnail {
    /// Downsamples a route and normalizes it into the unit square (aspect preserved,
    /// centered, y pointing down) so it can be drawn without a map.
    /// Returns a flat array [x0, y0, x1, y1, ...].
    public static func normalized(_ points: [TrackPoint], maxPoints: Int = 80) -> [Double] {
        guard points.count >= 2, maxPoints >= 2 else { return [] }
        let stride = max(1, Int((Double(points.count) / Double(maxPoints)).rounded(.up)))
        var picked: [TrackPoint] = []
        var i = 0
        while i < points.count {
            picked.append(points[i])
            i += stride
        }
        if let last = points.last, picked.last != last { picked.append(last) }

        let midLat = (picked.map(\.lat).min()! + picked.map(\.lat).max()!) / 2
        let lonScale = cos(midLat * .pi / 180)
        let xs = picked.map { $0.lon * lonScale }
        let ys = picked.map { $0.lat }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let span = max(maxX - minX, maxY - minY)
        guard span > 0 else { return [] }
        let offsetX = (span - (maxX - minX)) / 2
        let offsetY = (span - (maxY - minY)) / 2
        var out: [Double] = []
        out.reserveCapacity(picked.count * 2)
        for k in picked.indices {
            out.append((xs[k] - minX + offsetX) / span)
            out.append(1 - (ys[k] - minY + offsetY) / span)
        }
        return out
    }
}
