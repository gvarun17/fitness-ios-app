import Foundation

/// Made-up but realistic data: a beginner who walks most days and has started
/// running, with sleep, heart rate and HRV. Used for Demo mode, previews and tests.
/// The same `today` always gives the same data.
public enum DemoData {
    struct Random {
        var state: UInt64
        mutating func next() -> Double {        // 0..<1
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func between(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    }

    public static func make(today: Day, days count: Int = 120) -> HealthData {
        var rnd = Random(state: 42)
        var days: [DaySummary] = [], nights: [SleepNight] = [], workouts: [Workout] = []
        var runKm = 0.8
        for back in stride(from: count - 1, through: 0, by: -1) {
            let d = today.adding(-back)
            // 07:00 local time on that day (a Day's date is midnight UTC)
            let base = d.date.addingTimeInterval(7 * 3600 - Double(TimeZone.current.secondsFromGMT(for: d.date)))
            var exercise = rnd.between(10, 30)
            // Walks most days, a run every 2-3 days from 60 days ago, rides and gym sometimes
            if back % 7 != 3 {
                let km = rnd.between(1.5, 4.5)
                workouts.append(Workout(id: "walk-\(d)", day: d, start: base, sport: .walk, name: "Morning Walk",
                                        km: km, minutes: km * 13, avgHR: rnd.between(98, 115), kcal: km * 55,
                                        cadence: rnd.between(105, 118), strideM: rnd.between(0.68, 0.76)))
                exercise += km * 4
            }
            if back < 60, back % 3 == 0 {
                runKm = min(runKm * 1.06 + 0.05, 6.5)
                let km = back == 0 ? runKm * 1.15 : runKm
                let speed = rnd.between(2.3, 2.8) + Double(60 - back) / 120
                workouts.append(Workout(id: "run-\(d)", day: d, start: base.addingTimeInterval(11 * 3600), sport: .run,
                                        name: km < 3 ? "Run-walk" : "Easy Run", km: (km * 100).rounded() / 100,
                                        minutes: km * 1000 / speed / 60, avgHR: rnd.between(138, 152), maxHR: rnd.between(160, 172),
                                        kcal: km * 70, cadence: 148 + Double(60 - back) / 4 + rnd.between(-2, 2),
                                        strideM: 0.82 + Double(60 - back) / 600))
                exercise += km * 7
            }
            if back % 9 == 4 {
                workouts.append(Workout(id: "ride-\(d)", day: d, start: base.addingTimeInterval(10 * 3600), sport: .cycle,
                                        name: "Indoor Ride", km: rnd.between(8, 15), minutes: rnd.between(25, 40),
                                        avgHR: rnd.between(120, 135), kcal: 220))
            }
            if back % 6 == 1 {
                workouts.append(Workout(id: "gym-\(d)", day: d, start: base.addingTimeInterval(12 * 3600), sport: .strength,
                                        name: "Strength", km: 0, minutes: rnd.between(25, 45), avgHR: rnd.between(105, 125), kcal: 180))
            }
            let tired = back % 11 == 0
            days.append(DaySummary(day: d, steps: Int(rnd.between(5500, 13000)),
                                   restingHR: (tired ? 66 : 61) - Double(count - back) / 60 + rnd.between(-1.5, 1.5),
                                   hrv: (tired ? 34 : 44) + Double(count - back) / 30 + rnd.between(-4, 4),
                                   activeKcal: rnd.between(350, 700), exerciseMinutes: exercise.rounded()))
            let asleep = tired ? rnd.between(5, 6) : rnd.between(6.3, 8.1)
            let bed = Int(rnd.between(285, 345))              // 22:45 - 23:45
            nights.append(SleepNight(day: d, asleepHours: asleep, deep: asleep * 0.16, rem: asleep * 0.22,
                                     core: asleep * 0.62, awake: rnd.between(0.2, 0.5),
                                     bedtime: bed, wake: bed + Int(asleep * 60 + 25)))
        }
        return HealthData(days: days, nights: nights, workouts: workouts)
    }
}
