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

    /// garmin: also fill the Garmin-only fields (Body Battery, stress, sleep
    /// score, HRV status, training load, zones, graphs through the day and
    /// second-by-second graphs for the last week's workouts)
    public static func make(today: Day, days count: Int = 120, garmin: Bool = true) -> HealthData {
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
            var day = DaySummary(day: d, steps: Int(rnd.between(5500, 13000)),
                                 restingHR: (tired ? 66 : 61) - Double(count - back) / 60 + rnd.between(-1.5, 1.5),
                                 hrv: (tired ? 34 : 44) + Double(count - back) / 30 + rnd.between(-4, 4),
                                 activeKcal: rnd.between(350, 700), exerciseMinutes: exercise.rounded())
            if garmin {
                day.stepsGoal = 8000
                day.totalKcal = 2100 + (day.activeKcal ?? 0)
                day.minHR = 48; day.maxHR = rnd.between(140, 170)
                day.moderateMinutes = (exercise * 0.7).rounded(); day.vigorousMinutes = (exercise * 0.15).rounded()
                day.stressAvg = (tired ? 42 : 28) + rnd.between(-6, 6); day.stressMax = rnd.between(70, 95)
                day.stressMix = [0.35, 0.35, 0.2, 0.1]
                day.bbHigh = tired ? rnd.between(30, 45) : rnd.between(70, 95); day.bbLow = rnd.between(10, 25)
                day.bbLatest = rnd.between(30, 60); day.bbCharged = rnd.between(40, 70); day.bbDrained = rnd.between(50, 80)
                day.floors = rnd.between(4, 16).rounded(); day.floorsGoal = 10
                day.respiration = rnd.between(13, 16).rounded()
                day.hrvWeekly = 44 + Double(count - back) / 30
                day.hrvStatus = back > count - 21 ? "NONE" : tired ? "UNBALANCED" : "BALANCED"
                day.syncedAt = "18:45"
            }
            days.append(day)
            let asleep = tired ? rnd.between(5, 6) : rnd.between(6.3, 8.1)
            let bed = Int(rnd.between(285, 345))              // 22:45 - 23:45
            var night = SleepNight(day: d, asleepHours: asleep, deep: asleep * 0.16, rem: asleep * 0.22,
                                   core: asleep * 0.62, awake: rnd.between(0.2, 0.5),
                                   bedtime: bed, wake: bed + Int(asleep * 60 + 25))
            if garmin {
                night.score = (tired ? 52 : 70) + rnd.between(0, 18)
                night.stressAvg = (tired ? 30 : 18) + rnd.between(-4, 4)
            }
            nights.append(night)
        }
        guard garmin else { return HealthData(days: days, nights: nights, workouts: workouts) }
        for i in workouts.indices {
            var w = workouts[i]
            w.source = "garmin"
            w.typeName = w.name.lowercased()
            w.load = (w.minutes * (w.sport == .run ? 2.4 : 1.1)).rounded()
            w.aerobicTE = min(5, (w.sport == .run ? 2.6 : 1.6) + w.minutes / 60)
            let m = w.minutes
            w.zones = w.sport == .run ? [m * 0.05, m * 0.25, m * 0.45, m * 0.2, m * 0.05] : [m * 0.4, m * 0.45, m * 0.15, 0, 0]
            w.elevationM = w.km > 0 ? (w.km * 6).rounded() : nil
            w.steps = w.cadence.map { Int($0 * m) }
            if w.sport == .run, w.km >= 1, let v = w.speed { w.fastest1k = (1000 / v * 0.96).rounded() }
            workouts[i] = w
        }
        var dayDetails: [Day: DayDetail] = [:], details: [String: WorkoutDetail] = [:]
        for back in 0..<7 {
            let d = today.adding(-back)
            let acts = workouts.filter { $0.day == d }
            let end = back == 0 ? 18 * 60 : 1440
            func inWorkout(_ minute: Double) -> Workout? {
                acts.first { w in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: w.start)
                    let s = Double(c.hour! * 60 + c.minute!)
                    return minute >= s && minute <= s + w.minutes
                }
            }
            var hr: [[Double]] = [], bb: [[Double]] = []
            var battery = 25.0
            for minute in stride(from: 0.0, through: Double(end), by: 2) {
                let asleep = minute < 6.5 * 60 || minute > 23 * 60
                let base = asleep ? 52 : 70 + 8 * sin(minute / 90)
                let effort = inWorkout(minute).map { $0.sport == .run ? 80.0 : 35.0 } ?? 0
                hr.append([minute, (base + effort + rnd.between(-3, 3)).rounded()])
                if Int(minute) % 30 == 0 {
                    battery += asleep ? 9 : -(effort > 0 ? 6 : 2)
                    battery = min(max(battery, 8), 96)
                    bb.append([minute, battery.rounded()])
                }
            }
            dayDetails[d] = DayDetail(day: d, hr: hr, bb: bb)
            for w in acts where w.km > 0 {
                let n = Int(w.minutes * 6)
                var det = WorkoutDetail()
                det.t = (0..<n).map { Double($0 * 10) }
                det.hr = (0..<n).map { i in (w.avgHR ?? 120) - 15 + Double(i) / Double(n) * 25 + rnd.between(-2, 2) }
                det.speed = (0..<n).map { i in (w.speed ?? 2) * (i % 30 < 20 ? 1.08 : 0.85) + rnd.between(-0.1, 0.1) }
                det.cadence = (0..<n).map { _ in (w.cadence ?? 150) + rnd.between(-4, 4) }
                det.elevation = (0..<n).map { i in 120 + 8 * sin(Double(i) / 12) }
                if w.sport == .run, w.km < 3 { det.runMin = w.minutes * 0.65; det.walkMin = w.minutes * 0.32; det.standMin = w.minutes * 0.03 }
                details[w.id] = det
            }
        }
        return HealthData(days: days, nights: nights, workouts: workouts, dayDetails: dayDetails, workoutDetails: details)
    }
}
