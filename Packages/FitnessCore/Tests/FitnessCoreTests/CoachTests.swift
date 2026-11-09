import Foundation
import Testing
@testable import FitnessCore

let today = Day("2026-11-06")          // a Friday

func run(_ day: String, _ km: Double, minutes: Double? = nil, id: String? = nil) -> Workout {
    Workout(id: id ?? "run-\(day)-\(km)", day: Day(day), start: Day(day).date.addingTimeInterval(8 * 3600), sport: .run,
            name: "Run", km: km, minutes: minutes ?? km * 6.5)
}

func workout(_ day: String, _ sport: Sport, km: Double = 0, minutes: Double = 30) -> Workout {
    Workout(id: "\(sport)-\(day)", day: Day(day), start: Day(day).date, sport: sport, name: sport.name, km: km, minutes: minutes)
}

@Suite struct DayTests {
    @Test func arithmeticAndWeeks() {
        #expect(today.weekday == 5)
        #expect(today.monday == Day("2026-11-02"))
        #expect(Day("2026-11-08").weekday == 7)
        #expect(Day("2026-11-09").monday == Day("2026-11-09"))
        #expect(today.adding(-6) == Day("2026-10-31"))
        #expect(Day("2026-12-31").adding(1) == Day("2027-01-01"))
        #expect(Day("2026-10-01").days(until: today) == 36)
        #expect(Day("2026-01-05").isoWeek == 2)
        #expect(Day(date: today.date, calendar: { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()) == today)
    }

    @Test func codableAsPlainString() throws {
        let data = try JSONEncoder().encode([today])
        #expect(String(data: data, encoding: .utf8) == "[\"2026-11-06\"]")
        #expect(try JSONDecoder().decode([Day].self, from: data) == [today])
    }
}

@Suite struct FormatTests {
    @Test func text() {
        #expect(Fmt.hm(hours: 7.25) == "7h 15m")
        #expect(Fmt.hm(hours: 0.5) == "30m")
        #expect(Fmt.clock(seconds: 330) == "5:30")
        #expect(Fmt.clock(seconds: 3725) == "1:02:05")
        #expect(Fmt.pace(speed: 1000.0 / 360) == "6:00")
        #expect(Fmt.timeOfNight(315) == "23:15")
        #expect(Fmt.timeOfNight(420) == "01:00")
        #expect(Fmt.number(19811) == "19,811")
        #expect(Fmt.km(4.96) == "5.0")
    }
}

@Suite struct ReadinessTests {
    func data(rhr: Double = 60, hrv: Double = 45, sleep: Double = 8, load: Double = 30) -> HealthData {
        var days = (1...35).map { DaySummary(day: today.adding(-$0), restingHR: 60, hrv: 45, exerciseMinutes: 30) }
        days.append(DaySummary(day: today, restingHR: rhr, hrv: hrv, exerciseMinutes: load))
        return HealthData(days: days, nights: [SleepNight(day: today, asleepHours: sleep)])
    }

    @Test func goodDay() {
        let r = Coach.readiness(data(), settings: UserSettings(), today: today)
        #expect(r.level == .go)
        #expect(r.title == "Good day to train")
        #expect(r.signals.map(\.id) == ["hrv", "sleep", "rhr", "load"])
        #expect(r.signals.allSatisfy { $0.state == .good })
    }

    @Test func easyAndRest() {
        #expect(Coach.readiness(data(sleep: 5), settings: UserSettings(), today: today).level == .easy)    // one poor
        #expect(Coach.readiness(data(rhr: 64, hrv: 39), settings: UserSettings(), today: today).level == .easy)   // two ok
        #expect(Coach.readiness(data(rhr: 70, sleep: 5), settings: UserSettings(), today: today).level == .rest)
    }

    @Test func notEnoughData() {
        let r = Coach.readiness(HealthData(), settings: UserSettings(), today: today)
        #expect(r.level == nil)
        #expect(r.advice.contains("Wear your watch overnight"))
    }

    @Test func hrv() {
        #expect(Coach.hrvSignal(today: nil, previous: []).state == .none)
        #expect(Coach.hrvSignal(today: 40, previous: [40, 41]).note == "Still learning your normal range")
        #expect(Coach.hrvSignal(today: 40, previous: [40, 40, 40]).state == .good)
        #expect(Coach.hrvSignal(today: 36, previous: [40, 40, 40]).state == .ok)
        let s = Coach.hrvSignal(today: 30, previous: [40, 40, 40])
        #expect(s.state == .poor)
        #expect(s.note == "Well below your 7-day average (40 ms)")
        #expect(s.value == "30 ms")
    }

    @Test func sleep() {
        #expect(Coach.sleepSignal(nil, need: 8).state == .none)
        #expect(Coach.sleepSignal(SleepNight(day: today, asleepHours: 0), need: 8).state == .none)
        #expect(Coach.sleepSignal(SleepNight(day: today, asleepHours: 7.6), need: 8).state == .good)
        #expect(Coach.sleepSignal(SleepNight(day: today, asleepHours: 6.6), need: 8).state == .ok)
        let s = Coach.sleepSignal(SleepNight(day: today, asleepHours: 6), need: 8)
        #expect(s.state == .poor)
        #expect(s.value == "6h 00m")
    }

    @Test func restingHR() {
        let usual = Array(repeating: 60.0, count: 10)
        #expect(Coach.restingHRSignal(today: nil, history: usual).state == .none)
        #expect(Coach.restingHRSignal(today: 60, history: [60, 60]).state == .none)
        #expect(Coach.restingHRSignal(today: 62, history: usual).state == .good)
        #expect(Coach.restingHRSignal(today: 64, history: usual).state == .ok)
        let s = Coach.restingHRSignal(today: 68, history: usual)
        #expect(s.state == .poor)
        #expect(s.note.hasPrefix("8 bpm above your usual 60"))
    }

    @Test func trainingLoad() {
        #expect(Coach.loadSignal(last7: 100, usualWeek: nil).state == .none)
        #expect(Coach.loadSignal(last7: 0, usualWeek: 10).value == nil)
        let steady = Coach.loadSignal(last7: 210, usualWeek: 200)
        #expect(steady.state == .good)
        #expect(steady.note == "In line with your usual week")
        #expect(Coach.loadSignal(last7: 250, usualWeek: 200).state == .good)
        #expect(Coach.loadSignal(last7: 290, usualWeek: 200).state == .ok)
        let jump = Coach.loadSignal(last7: 400, usualWeek: 200)
        #expect(jump.state == .poor)
        #expect(jump.note == "100% more than your usual week: a big jump, ease off")
    }
}

@Suite struct WeeklyGoalTests {
    func days(weeks: Int = 4, minutes: Double = 40) -> [DaySummary] {
        let first = today.monday.adding(-7 * (weeks - 1))
        return (0...first.days(until: today)).map { DaySummary(day: first.adding($0), exerciseMinutes: minutes) }
    }

    @Test func suggestedGoalAndStreak() {
        let g = Coach.weeklyGoal(HealthData(days: days()), settings: UserSettings(), today: today)
        #expect(g.type == .minutes && g.target == 150 && g.suggested)
        #expect(g.value == 200)                   // Monday to Friday at 40 a day
        #expect(g.need == 0 && g.daysLeft == 3 && g.reached)
        #expect(g.streak == 4 && g.best == 4 && g.hits == 3 && g.of == 3)
        #expect(g.weeks.count == 4)
        #expect(g.progress == 1)
        #expect(g.summary == "200 of 150 min")
    }

    @Test func yourGoalNotReachedYet() {
        let g = Coach.weeklyGoal(HealthData(days: days(minutes: 10)), settings: UserSettings(goalValue: 300), today: today)
        #expect(!g.suggested && g.value == 50 && g.need == 250 && g.perDay == 83.3)
        #expect(g.streak == 0 && g.best == 0)
        #expect(g.progress == 50.0 / 300)
    }

    @Test func distanceAndRunGoals() {
        let mon = today.monday
        let w = [run(mon.iso, 5.25), workout(mon.adding(1).iso, .walk, km: 3), run(mon.adding(2).iso, 4),
                 run(mon.adding(-7).iso, 30)]
        let data = HealthData(workouts: w)
        let km = Coach.weeklyGoal(data, settings: UserSettings(goalType: .km, goalValue: 15), today: today)
        #expect(km.value == 12.3 && km.need == 2.7 && km.streak == 1)
        #expect(WeeklyGoal.text(12.25, .km) == "12.3")
        let runKm = Coach.weeklyGoal(data, settings: UserSettings(goalType: .runKm, goalValue: 9), today: today)
        #expect(runKm.value == 9.3 && runKm.streak == 2)
        let runs = Coach.weeklyGoal(data, settings: UserSettings(goalType: .runs, goalValue: 3), today: today)
        #expect(runs.value == 2 && runs.need == 1)
    }

    @Test func streakBreaksAndBestIsKept() {
        let w = [1, 2, 4, 5, 6].map { run(today.monday.adding(-7 * $0).iso, 5) }
        let g = Coach.weeklyGoal(HealthData(workouts: w), settings: UserSettings(goalType: .runs, goalValue: 1), today: today)
        #expect(g.streak == 2 && g.best == 3)
    }

    @Test func noDataAndLongHistory() {
        let g = Coach.weeklyGoal(HealthData(), settings: UserSettings(goalType: .runs), today: today)
        #expect(g.target == 3 && g.value == 0 && g.of == 0 && g.weeks.count == 1)
        let old = Coach.weeklyGoal(HealthData(days: [DaySummary(day: Day("2015-01-01"), exerciseMinutes: 500)]),
                                   settings: UserSettings(), today: today)
        #expect(old.weeks.count == 8 && old.of == 12)
    }

    @Test func cleaningTypedGoals() throws {
        #expect(try UserSettings.cleanGoal(.km, " 12,5 ") == 12.5)
        #expect(try UserSettings.cleanGoal(.runs, "") == nil)
        #expect(throws: GoalError.notANumber) { try UserSettings.cleanGoal(.km, "lots") }
        #expect(throws: GoalError.outOfRange(500, "km")) { try UserSettings.cleanGoal(.km, "0") }
        #expect(throws: GoalError.wholeRuns) { try UserSettings.cleanGoal(.runs, "2.5") }
        #expect(GoalError.outOfRange(500, "km").errorDescription == "Please pick a weekly goal above 0 and up to 500 km.")
        #expect(GoalError.notANumber.errorDescription != nil && GoalError.wholeRuns.errorDescription != nil)
        #expect(GoalType.allCases.map(\.suggested) == [150, 15, 10, 3])
        #expect(GoalType.allCases.map(\.maximum) == [3000, 500, 300, 14])
        #expect(GoalType.allCases.allSatisfy { !$0.label.isEmpty && $0.id == $0.rawValue })
    }
}

@Suite struct MilestoneTests {
    @Test func noRunsYet() {
        let m = Coach.milestones(HealthData(workouts: [workout("2026-10-01", .walk, km: 3), workout("2026-10-02", .walk, km: 2)]))
        #expect(m.next == 0 && m.longestDay == nil && m.walks == 2)
        #expect(m.tip.contains("Your 2 walks are already a good base"))
        #expect(Coach.milestones(HealthData()).tip.contains("chat the whole time"))
    }

    @Test func weeksToTheNextStep() {
        let m = Coach.milestones(HealthData(workouts: [run("2026-10-01", 0.6), run("2026-10-10", 1.2), run("2026-10-20", 2.0)]))
        #expect(m.steps.map(\.reached).prefix(3) == [Day("2026-10-01"), Day("2026-10-10"), nil])
        #expect(m.next == 2 && m.toGoKm == 3 && m.weeks == 10 && m.runs == 3)
        #expect(m.longestKm == 2 && m.longestDay == Day("2026-10-20"))
        #expect(m.tip.contains("about 10 weeks"))
        #expect(m.nextStep?.label == "5K" && m.reachedCount == 2)
    }

    @Test func gpsToleranceAndOneWeek() {
        let m = Coach.milestones(HealthData(workouts: [run("2026-10-01", 4.92), run("2026-10-05", 9.5)]))
        #expect(m.steps[2].reached == Day("2026-10-01"))
        #expect(m.next == 3 && m.weeks == 1)
        #expect(m.tip.hasSuffix("about 1 week."))
    }

    @Test func runsWithoutDistance() {
        let m = Coach.milestones(HealthData(workouts: [run("2026-10-01", 0)]))
        #expect(m.next == 1 && m.toGoKm == 1 && m.weeks == nil)
        #expect(m.tip.contains("run-walk"))
    }

    @Test func triathlonsNeedAllThreeOnOneDay() {
        let w = [run("2026-06-01", 42.2), workout("2026-07-01", .swim, km: 1.9), workout("2026-07-01", .cycle, km: 90),
                 run("2026-07-02", 21.1), workout("2026-08-01", .swim, km: 1.0), workout("2026-08-01", .swim, km: 0.9),
                 workout("2026-08-01", .cycle, km: 92), run("2026-08-01", 21.0)]
        let m = Coach.milestones(HealthData(workouts: w))
        #expect(m.steps[6].reached == Day("2026-08-01"))
        #expect(m.next == 7)
        #expect(m.tip.contains("Longest swim so far 1.9 km, longest ride 92 km"))
    }

    @Test func wholeLadder() {
        let w = [run("2026-01-01", 42.2), workout("2026-09-01", .swim, km: 3.8), workout("2026-09-01", .cycle, km: 180), run("2026-09-01", 42.2)]
        let m = Coach.milestones(HealthData(workouts: w))
        #expect(m.next == nil && m.nextStep == nil)
        #expect(m.tip.contains("whole ladder"))
    }
}

@Suite struct PlanTests {
    func plan(_ w: [Workout], _ s: UserSettings = UserSettings()) -> TrainingPlan {
        let data = HealthData(workouts: w)
        return Coach.trainingPlan(data, ladder: Coach.milestones(data), settings: s, today: today)
    }

    @Test func firstRuns() {
        let p = plan([])
        #expect(p.target == "First run" && p.goalKm == 1 && p.perWeek == 3)
        #expect(p.week.longKm == 1 && p.week.intervals == "Run 1 min, walk 2 min, repeat")
        #expect(p.sessions.map(\.kind) == ["Easy run", "Easy run", "Long run"])
        #expect(p.sessions.map(\.day) == ["Tue", "Thu", "Sat"])
        #expect(p.sessions.allSatisfy { !$0.done } && p.sessions[0].id == "TueEasy run")
        #expect(p.past.count == 4 && p.ahead.count == 4)
    }

    @Test func buildingTo5K() {
        let mon = today.monday
        let w = [run(mon.adding(-10).iso, 2.0), run(mon.iso, 1.4), run(mon.adding(2).iso, 2.3)]
        let p = plan(w, UserSettings(goalType: .runs, goalValue: 4))
        #expect(p.target == "5K" && p.perWeek == 4)
        #expect(p.week.longKm == 2.2 && p.week.easyKm == 1.3)
        #expect(p.week.doneRuns == 2 && p.week.doneLongKm == 2.3 && p.week.longDone && !p.week.complete)
        #expect(p.week.intervals == "Run 2 min, walk 1 min, repeat")
        #expect(p.sessions.map(\.done) == [true, false, false, true])
        #expect(p.sessions.map(\.day) == ["Mon", "Wed", "Fri", "Sun"])
        #expect(p.ahead[0].longKm == 2.5)               // builds on the 2.3 km already run
        #expect(!p.ready)
    }

    @Test func runsPerWeekStaysSensible() {
        #expect(plan([], UserSettings(goalType: .runs, goalValue: 9)).perWeek == 6)
        #expect(plan([], UserSettings(goalType: .runs, goalValue: 1)).perWeek == 2)
        #expect(plan([], UserSettings(goalType: .km, goalValue: 20)).perWeek == 3)
    }

    @Test func easierWeeksReadyAndMarathonAfterLadder() {
        let mon = today.monday
        let p = plan([3, 10, 17].map { run(mon.adding(-$0).iso, 5) } + [run(mon.iso, 5)])
        #expect(p.target == "10K")
        let easier = p.ahead.filter(\.easier)
        #expect(easier.count == 1)
        if let i = p.ahead.firstIndex(where: \.easier), i > 0 {
            #expect(p.ahead[i].longKm == p.ahead[i - 1].longKm)       // no growth in an easier week
        }
        let long = plan([run(mon.adding(-3).iso, 10), run("2026-01-01", 21.1), run("2026-01-02", 42.2)])
        #expect(long.target == "Marathon")
        let ready = Coach.trainingPlan(HealthData(workouts: [run(mon.adding(-3).iso, 5)]),
                                       ladder: Milestones(steps: [MilestoneStep(id: "5k", label: "5K", detail: "", reached: nil)],
                                                          next: 0, runs: 1, walks: 0, longestKm: 5, longestDay: nil, tip: ""),
                                       settings: UserSettings(), today: today)
        #expect(ready.ready && ready.week.intervals == nil)
        #expect(Coach.runWalk(3) == "Run 4 min, walk 1 min, repeat")
    }
}

@Suite struct RecordsTests {
    @Test func bestsAndFirsts() {
        let w = [run("2026-10-01", 3, minutes: 18, id: "a"), run("2026-10-20", 5.1, minutes: 33, id: "b"),
                 run("2026-11-05", 2, minutes: 11, id: "c"), run("2026-11-06", 0.5, minutes: 2, id: "d"),
                 workout("2026-10-02", .walk, km: 6), workout("2026-11-03", .strength, minutes: 45)]
        let days = [DaySummary(day: Day("2026-10-05"), steps: 12000, restingHR: 52), DaySummary(day: Day("2026-10-06"), steps: 9000, restingHR: 49)]
        let nights = [SleepNight(day: Day("2026-10-05"), asleepHours: 8.5), SleepNight(day: Day("2026-10-06"), asleepHours: 6)]
        let r = Coach.records(HealthData(days: days, nights: nights, workouts: w), today: today)
        let b = Dictionary(uniqueKeysWithValues: r.bests.map { ($0.id, $0) })
        #expect(b["run_long"]?.text == "5.1 km" && b["run_long"]?.workoutID == "b" && b["run_long"]?.isNew == false)
        #expect(b["run_pace"]?.text == "5:30 /km" && b["run_pace"]?.workoutID == "c" && b["run_pace"]?.isNew == true)
        #expect(b["run_5k"]?.text == "32:21" && b["run_5k"]?.workoutID == "b")
        #expect(b["run_week"]?.text == "5.1 km" && b["run_week"]?.day == Day("2026-10-19"))
        #expect(b["walk_long"]?.text == "6.0 km")
        #expect(b["strength_long"]?.text == "45 min" && b["strength_long"]?.isNew == true)
        #expect(b["steps_day"]?.text == "12,000")
        #expect(b["rhr_low"]?.text == "49 bpm")
        #expect(b["sleep_long"]?.text == "8h 30m")
        #expect(b["ride_long"] == nil)
        #expect(r.firsts.map(\.sport) == [.run, .walk, .strength])
        #expect(r.firsts.map(\.isNew) == [false, false, true])
        #expect(r.firsts[0].id == "run")
    }

    @Test func nothingYet() {
        let r = Coach.records(HealthData(days: [DaySummary(day: today, steps: 0)]), today: today)
        #expect(r.bests.isEmpty && r.firsts.isEmpty)
    }
}

@Suite struct SleepTests {
    func night(_ back: Int, hours: Double, bed: Int?, wake: Int? = nil) -> SleepNight {
        SleepNight(day: today.adding(-back), asleepHours: hours, bedtime: bed, wake: wake)
    }

    @Test func shortIrregularSleep() {
        // early nights (21:30) are longer than late ones (01:00)
        var nights = (0..<8).map { i in i % 2 == 0 ? night(i, hours: 6, bed: 210, wake: 660) : night(i, hours: 4.5, bed: 420, wake: 660) }
        nights.append(night(30, hours: 8, bed: 240))                // too old
        nights.append(night(9, hours: 0, bed: nil))                // not tracked
        let s = Coach.sleepInsights(HealthData(nights: nights), settings: UserSettings(sleepNeedHours: 7.5), today: today)
        #expect(s.nightsTracked == 8 && s.need == 7.5 && s.averageHours == 5.25)
        #expect(s.debtHours == 15)
        #expect(s.bedtime == 315 && s.bedtimeSpread == 105)
        #expect(s.wake == 660 && s.wakeSpread == 0)
        let text = s.tips.joined(separator: " ")
        #expect(text.contains("2h 15m less than your 7h 30m target"))
        #expect(text.contains("sleep debt of about 15h 00m"))
        #expect(text.contains("bedtime moves around: usually 23:15"))
        #expect(text.contains("You slept 1h 30m longer on nights you went to bed before 23:15."))
    }

    @Test func steadySleep() {
        let s = Coach.sleepInsights(HealthData(nights: (0..<5).map { night($0, hours: 8, bed: 270) }), settings: UserSettings(), today: today)
        #expect(s.debtHours == 0)
        let text = s.tips.joined(separator: " ")
        #expect(text.contains("right around your 8h 00m target"))
        #expect(text.contains("bedtime is steady, usually around 22:30 (give or take 0 min)"))
        #expect(!text.contains("sleep debt"))
        #expect(s.wake == nil)
    }

    @Test func longSleepFewNights() {
        let s = Coach.sleepInsights(HealthData(nights: [night(0, hours: 10, bed: nil), night(1, hours: 10, bed: nil)]),
                                    settings: UserSettings(), today: today)
        #expect(s.tips[0].contains("more than your 8h 00m target"))
        #expect(s.bedtime == nil)
    }

    @Test func noNights() {
        let s = Coach.sleepInsights(HealthData(), settings: UserSettings(), today: today)
        #expect(s.nightsTracked == 0 && s.tips[0].contains("Wear your watch to bed"))
    }
}

@Suite struct SnapshotTests {
    @Test func demoDataMakesACompleteSnapshot() {
        let data = DemoData.make(today: today)
        #expect(data == DemoData.make(today: today))            // same today, same data
        #expect(data.days.count == 120 && data.nights.count == 120)
        #expect(data.workouts.contains { $0.sport == .run } && data.workouts.contains { $0.sport == .strength })
        let s = Coach.snapshot(data, settings: UserSettings(name: "Varun"), today: today, now: today.date, isDemo: true)
        #expect(s.name == "Varun" && s.isDemo && s.today == today)
        #expect(s.readiness.level != nil)
        #expect(s.stats.steps != nil && s.stats.sleepHours != nil && s.stats.workouts >= 1)
        #expect(s.trends.days.count == 7 && s.trends.days.last == today && s.trends.steps.allSatisfy { $0 != nil })
        #expect(s.milestones.reachedCount >= 3)
        #expect(!s.records.bests.isEmpty && s.lastWorkout?.day == today)
        #expect(s.todaysWorkouts.count == s.stats.workouts)
        #expect(s.newBests.allSatisfy { $0.isNew })
        #expect(s.sleep.nightsTracked == 14)
        #expect(Sport.allCases.allSatisfy { !$0.name.isEmpty && !$0.symbol.isEmpty })
        #expect(data.workouts.first { $0.sport == .strength }?.speed == nil)
    }

    @Test func storeRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SnapshotStore(folder: folder)
        #expect(store.loadSnapshot() == nil)
        #expect(store.loadSettings() == UserSettings())
        let snap = Coach.snapshot(DemoData.make(today: today, days: 30), settings: UserSettings(), today: today, now: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(snap)
        try store.save(UserSettings(name: "V", goalType: .runs, goalValue: 4))
        #expect(store.loadSnapshot() == snap)
        #expect(store.loadSettings().goalType == .runs)
        #expect(SnapshotStore.shared.folder.lastPathComponent.isEmpty == false)
    }
}
