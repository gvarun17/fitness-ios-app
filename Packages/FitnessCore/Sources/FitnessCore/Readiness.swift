import Foundation

public enum SignalState: String, Codable, Sendable {
    case good, ok, poor, none

    var score: Int? {
        switch self {
        case .good: 2
        case .ok: 1
        case .poor: 0
        case .none: nil
        }
    }
}

public struct Signal: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var label: String
    public var state: SignalState
    public var value: String?
    public var note: String
}

public enum ReadinessLevel: String, Codable, Sendable {
    case go, easy, rest

    public var title: String {
        switch self {
        case .go: "Good day to train"
        case .easy: "Take it easy today"
        case .rest: "Rest and recover today"
        }
    }
    public var advice: String {
        switch self {
        case .go: "Your body looks recovered. A good day for a run, or a longer walk than usual."
        case .easy: "Keep it gentle: a walk, or a relaxed run where you can talk in full sentences."
        case .rest: "Your body is still recovering. Rest, stretch, or take a short gentle walk."
        }
    }
    /// Short word for small widgets
    public var short: String {
        switch self {
        case .go: "Train"
        case .easy: "Easy"
        case .rest: "Rest"
        }
    }
}

/// Today's call: a training, easy or rest day. A guide, not medical advice.
public struct Readiness: Codable, Sendable, Equatable {
    public var level: ReadinessLevel?
    public var title: String
    public var advice: String
    public var signals: [Signal]
}

extension Coach {
    /// HRV last night against your own 7-day average (Apple Health HRV varies a lot
    /// between people and devices, so only your own trend means anything).
    static func hrvSignal(today: Double?, previous: [Double]) -> Signal {
        guard let v = today else {
            return Signal(id: "hrv", label: "HRV", state: .none, value: nil, note: "Not measured last night")
        }
        let value = "\(Int(v.rounded())) ms"
        guard previous.count >= 3, let avg = mean(previous) else {
            return Signal(id: "hrv", label: "HRV", state: .none, value: value, note: "Still learning your normal range")
        }
        let ratio = v / avg
        let state: SignalState = ratio >= 0.95 ? .good : ratio >= 0.85 ? .ok : .poor
        let word = ["good": "Close to", "ok": "A bit below", "poor": "Well below"][state.rawValue]!
        return Signal(id: "hrv", label: "HRV", state: state, value: value,
                      note: "\(word) your 7-day average (\(Int(avg.rounded())) ms)")
    }

    static func sleepSignal(_ night: SleepNight?, need: Double) -> Signal {
        guard let n = night, n.asleepHours > 0 else {
            return Signal(id: "sleep", label: "Sleep", state: .none, value: nil, note: "Not tracked last night")
        }
        let h = n.asleepHours
        let state: SignalState = h >= need - 0.5 ? .good : h >= need - 1.5 ? .ok : .poor
        return Signal(id: "sleep", label: "Sleep", state: state, value: Fmt.hm(hours: h),
                      note: "Your target is \(Fmt.hm(hours: need))")
    }

    static func restingHRSignal(today: Double?, history: [Double]) -> Signal {
        guard let v = today else {
            return Signal(id: "rhr", label: "Resting HR", state: .none, value: nil, note: "Not measured yet today")
        }
        let value = "\(Int(v.rounded())) bpm"
        guard history.count >= 7, let usual = mean(history) else {
            return Signal(id: "rhr", label: "Resting HR", state: .none, value: value,
                          note: "Needs a week of data to know your normal")
        }
        let diff = v - usual
        let u = Int(usual.rounded()), d = Int(diff.rounded())
        if diff <= 2 { return Signal(id: "rhr", label: "Resting HR", state: .good, value: value, note: "Normal for you (usually \(u))") }
        if diff <= 5 { return Signal(id: "rhr", label: "Resting HR", state: .ok, value: value, note: "\(d) bpm above your usual \(u)") }
        return Signal(id: "rhr", label: "Resting HR", state: .poor, value: value,
                      note: "\(d) bpm above your usual \(u): tiredness, stress or a cold coming?")
    }

    /// Exercise minutes in the last 7 days against your usual week (the 4 weeks before).
    /// A big jump is the best-known early warning for overuse injuries.
    static func loadSignal(last7: Double, usualWeek: Double?) -> Signal {
        guard let usual = usualWeek, usual >= 30 else {
            return Signal(id: "load", label: "Training load", state: .none,
                          value: last7 > 0 ? "\(Int(last7.rounded())) min" : nil,
                          note: "Needs a few weeks of data")
        }
        let ratio = last7 / usual
        let state: SignalState = ratio <= 1.3 ? .good : ratio <= 1.5 ? .ok : .poor
        let note: String
        if ratio <= 1.1 {
            note = "In line with your usual week"
        } else {
            note = "\(Int(((ratio - 1) * 100).rounded()))% more than your usual week"
                + (state == .poor ? ": a big jump, ease off" : "")
        }
        return Signal(id: "load", label: "Training load", state: state, value: "\(Int(last7.rounded())) min", note: note)
    }

    public static func readiness(_ data: HealthData, settings: UserSettings, today: Day) -> Readiness {
        let summary = data.day(today)
        let before = (1...7).compactMap { data.day(today.adding(-$0))?.hrv }
        let rhrHistory = (1...30).compactMap { data.day(today.adding(-$0))?.restingHR }
        let ex = { (from: Int, to: Int) -> Double in
            (from...to).compactMap { data.day(today.adding(-$0))?.exerciseMinutes }.reduce(0, +)
        }
        let hasHistory = data.days.contains { $0.day <= today.adding(-14) }
        let signals = [
            hrvSignal(today: summary?.hrv, previous: before),
            sleepSignal(data.night(today), need: settings.sleepNeedHours),
            restingHRSignal(today: summary?.restingHR, history: rhrHistory),
            loadSignal(last7: ex(0, 6), usualWeek: hasHistory ? ex(7, 34) / 4 : nil),
        ]
        let rated = signals.map(\.state).filter { $0 != .none }
        guard rated.count >= 2 else {
            return Readiness(level: nil, title: "Not enough data yet today",
                             advice: "Wear your watch overnight and this card will tell you how ready you are to train.",
                             signals: signals)
        }
        let poor = rated.filter { $0 == .poor }.count, ok = rated.filter { $0 == .ok }.count
        let level: ReadinessLevel = poor >= 2 ? .rest : (poor > 0 || ok >= 2) ? .easy : .go
        return Readiness(level: level, title: level.title, advice: level.advice, signals: signals)
    }
}

/// The coaching logic: plain arithmetic on your data, ported from the web dashboard.
public enum Coach {}
