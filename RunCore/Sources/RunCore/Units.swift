import Foundation

/// Distance unit the runner prefers. All stored values are metric (meters, seconds).
public enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case kilometers
    case miles

    public var meters: Double {
        switch self {
        case .kilometers: return 1000
        case .miles: return 1609.344
        }
    }

    /// Short label, e.g. "km".
    public var abbreviation: String {
        switch self {
        case .kilometers: return "km"
        case .miles: return "mi"
        }
    }

    public var singular: String {
        switch self {
        case .kilometers: return "kilometer"
        case .miles: return "mile"
        }
    }

    public var plural: String { singular + "s" }

    /// Unit used for elevation alongside this distance unit.
    public var elevationAbbreviation: String {
        switch self {
        case .kilometers: return "m"
        case .miles: return "ft"
        }
    }

    public func elevation(fromMeters meters: Double) -> Double {
        switch self {
        case .kilometers: return meters
        case .miles: return meters * 3.28084
        }
    }
}

/// Display formatting for run metrics.
public enum Fmt {
    public static let placeholderPace = "--:--"

    /// "5.23" style distance in the given unit.
    public static func distance(_ meters: Double, unit: DistanceUnit, decimals: Int = 2) -> String {
        let value = max(0, meters) / unit.meters
        // Truncate rather than round so the display never shows a distance not yet covered.
        let factor = pow(10.0, Double(decimals))
        let truncated = (value * factor + 1e-9).rounded(.down) / factor
        return String(format: "%.\(decimals)f", truncated)
    }

    /// "12:34" or "1:02:03".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Pace as "5:07" per unit. `secondsPerMeter` nil or implausibly slow gives a placeholder.
    public static func pace(secondsPerMeter: Double?, unit: DistanceUnit) -> String {
        guard let spm = secondsPerMeter, spm.isFinite, spm > 0 else { return placeholderPace }
        let perUnit = spm * unit.meters
        guard perUnit < 3600 else { return placeholderPace }
        let total = Int(perUnit.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func pace(distance: Double, duration: TimeInterval, unit: DistanceUnit) -> String {
        guard distance > 1, duration > 0 else { return placeholderPace }
        return pace(secondsPerMeter: duration / distance, unit: unit)
    }

    /// "42 m" / "138 ft".
    public static func elevation(_ meters: Double, unit: DistanceUnit) -> String {
        "\(Int(unit.elevation(fromMeters: meters).rounded())) \(unit.elevationAbbreviation)"
    }
}

public enum Calories {
    /// Rough net energy cost of running: about 1.036 kcal per kg per km.
    public static func estimate(distanceMeters: Double, weightKg: Double) -> Double {
        max(0, distanceMeters) / 1000 * max(0, weightKg) * 1.036
    }
}
