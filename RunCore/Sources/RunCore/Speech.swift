import Foundation

/// Builds the sentences spoken during a run.
public enum SpeechText {
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) \(h == 1 ? "hour" : "hours")") }
        if m > 0 { parts.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        if s > 0 || parts.isEmpty { parts.append("\(s) \(s == 1 ? "second" : "seconds")") }
        return parts.joined(separator: " ")
    }

    public static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        let value = (meters / unit.meters * 100).rounded() / 100
        if abs(value - value.rounded()) < 0.005 {
            let whole = Int(value.rounded())
            return "\(whole) \(whole == 1 ? unit.singular : unit.plural)"
        }
        var text = String(format: "%.2f", value)
        if text.hasSuffix("0") { text.removeLast() }
        return "\(text) \(unit.plural)"
    }

    public static func pace(secondsPerMeter: Double, unit: DistanceUnit) -> String {
        "\(duration((secondsPerMeter * unit.meters).rounded())) per \(unit.singular)"
    }

    public static func measure(_ measure: StepMeasure, unit: DistanceUnit) -> String {
        switch measure {
        case .time(let t): return duration(t)
        case .distance(let d):
            if d < 1000 || (unit == .kilometers && d.truncatingRemainder(dividingBy: 1000) != 0 && d < 2000) {
                return "\(Int(d.rounded())) meters"
            }
            return distance(d, unit: unit)
        }
    }

    public static func split(totalDistance: Double, elapsed: TimeInterval, split: Split,
                             unit: DistanceUnit, targetPace: Double? = nil) -> String {
        var text = "\(distance(totalDistance, unit: unit)). Time, \(duration(elapsed))."
        if let splitPace = split.secondsPerMeter {
            text += " Last \(unit.singular), \(duration((splitPace * unit.meters).rounded()))."
        }
        if totalDistance > 0 {
            text += " Average pace, \(pace(secondsPerMeter: elapsed / totalDistance, unit: unit))."
        }
        if let targetPace, let delta = GoalProgress.paceDelta(target: targetPace, elapsed: elapsed, distance: totalDistance) {
            let perUnit = (delta * unit.meters).rounded()
            if abs(perUnit) < 3 {
                text += " Right on target pace."
            } else if perUnit < 0 {
                text += " \(duration(-perUnit)) per \(unit.singular) ahead of target."
            } else {
                text += " \(duration(perUnit)) per \(unit.singular) behind target."
            }
        }
        return text
    }

    public static func stepStarted(_ step: IntervalStep, repeatNumber: Int, totalRepeats: Int, unit: DistanceUnit) -> String {
        let length = measure(step.measure, unit: unit)
        switch step.kind {
        case .warmup: return "Warm up. \(length)."
        case .run:
            if totalRepeats > 1 { return "Run. \(length). Interval \(repeatNumber) of \(totalRepeats)." }
            return "Run. \(length)."
        case .recover: return "Recover. \(length)."
        case .cooldown: return "Cool down. \(length)."
        }
    }
}
