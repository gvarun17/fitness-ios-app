import Foundation

public struct SleepInsights: Codable, Sendable, Equatable {
    public var need: Double
    public var nightsTracked: Int
    public var averageHours: Double?
    public var debtHours: Double?
    /// Minutes after 18:00
    public var bedtime: Int?
    public var bedtimeSpread: Int?
    public var wake: Int?
    public var wakeSpread: Int?
    public var nights: [SleepNight]
    public var tips: [String]
}

extension Coach {
    public static func sleepInsights(_ data: HealthData, settings: UserSettings, today: Day, nights count: Int = 14) -> SleepInsights {
        let start = today.adding(-(count - 1))
        let rows = data.nights.filter { $0.day >= start && $0.day <= today && $0.asleepHours > 0 }
        let need = settings.sleepNeedHours
        var out = SleepInsights(need: need, nightsTracked: rows.count, nights: rows, tips: [])
        guard !rows.isEmpty else {
            out.tips = ["No nights tracked in the last two weeks. Wear your watch to bed to get sleep insights."]
            return out
        }
        let avg = rows.map(\.asleepHours).reduce(0, +) / Double(rows.count)
        let week = rows.filter { $0.day >= today.adding(-6) }
        let debt = max(week.map { need - $0.asleepHours }.reduce(0, +), 0)
        out.averageHours = (avg * 100).rounded() / 100
        out.debtHours = (debt * 10).rounded() / 10
        let gap = need - avg
        if abs(gap) <= 0.25 {
            out.tips.append("You averaged \(Fmt.hm(hours: avg)) a night, right around your \(Fmt.hm(hours: need)) target.")
        } else if gap > 0 {
            out.tips.append("You averaged \(Fmt.hm(hours: avg)) a night, \(Fmt.hm(hours: gap)) less than your \(Fmt.hm(hours: need)) target.")
        } else {
            out.tips.append("You averaged \(Fmt.hm(hours: avg)) a night, more than your \(Fmt.hm(hours: need)) target. Good for recovery.")
        }
        if debt >= 2 {
            out.tips.append("Over the last 7 days that's a sleep debt of about \(Fmt.hm(hours: debt)). "
                + "An earlier night or two this week would help you recover from training.")
        }
        let beds = rows.compactMap(\.bedtime).map(Double.init)
        if beds.count >= 3 {
            let (m, sd) = spread(beds)
            out.bedtime = Int(m.rounded())
            out.bedtimeSpread = Int(sd.rounded())
            let at = Fmt.timeOfNight(Int(m.rounded()))
            if sd <= 30 {
                out.tips.append("Your bedtime is steady, usually around \(at) (give or take \(Int(sd.rounded())) min).")
            } else {
                out.tips.append("Your bedtime moves around: usually \(at), give or take \(Int(sd.rounded())) min. "
                    + "Going to bed within the same half hour each night tends to improve sleep.")
            }
            let early = rows.filter { $0.bedtime != nil && Double($0.bedtime!) <= m }.map(\.asleepHours)
            let late = rows.filter { $0.bedtime != nil && Double($0.bedtime!) > m }.map(\.asleepHours)
            if early.count >= 3, late.count >= 3, let e = mean(early), let l = mean(late), abs(e - l) >= 0.5 {
                let better = e > l ? "before" : "after"
                out.tips.append("You slept \(Fmt.hm(hours: abs(e - l))) longer on nights you went to bed \(better) \(at).")
            }
        }
        let wakes = rows.compactMap(\.wake).map(Double.init)
        if wakes.count >= 3 {
            let (m, sd) = spread(wakes)
            out.wake = Int(m.rounded())
            out.wakeSpread = Int(sd.rounded())
        }
        return out
    }
}
