import Foundation

/// Small text helpers shared by the coach, the app and the widgets.
public enum Fmt {
    /// 7.25 -> "7h 15m"
    public static func hm(hours: Double) -> String {
        let m = Int((hours * 60).rounded())
        return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
    }

    /// seconds -> "5:30" or "1:02:03"
    public static func clock(seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// metres per second -> "6:05" (per km)
    public static func pace(speed: Double) -> String { clock(seconds: 1000 / speed) }

    /// minutes after 18:00 -> "23:15"
    public static func timeOfNight(_ afterSix: Int) -> String {
        let m = (afterSix + 18 * 60) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    public static func km(_ v: Double) -> String { String(format: "%.1f", (v * 10).rounded() / 10) }   // 12.25 -> 12.3

    public static func number(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v.rounded()))"
    }
}

func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }

func spread(_ xs: [Double]) -> (mean: Double, sd: Double) {
    let m = xs.reduce(0, +) / Double(xs.count)
    return (m, (xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)).squareRoot())
}
