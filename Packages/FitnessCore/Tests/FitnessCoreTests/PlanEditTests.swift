import Foundation
import Testing
@testable import FitnessCore

let mon = Day("2026-11-09")          // a Monday

@Suite struct PlanSettingsTests {
    func plan(_ ps: PlanSettings, runs: [Workout] = []) -> TrainingPlan {
        let data = HealthData(workouts: runs)
        return Coach.trainingPlan(data, ladder: Coach.milestones(data), settings: UserSettings(plan: ps), today: mon.adding(2))
    }

    @Test func yourDaysRunsAndTarget() {
        let p = plan(PlanSettings(runsPerWeek: 4, days: [2, 4, 6, 7], target: "10k"))
        #expect(p.perWeek == 4 && p.sessions.map(\.day) == ["Tue", "Thu", "Sat", "Sun"])
        #expect(p.sessions.last?.kind == "Long run" && p.target == "10K" && p.goalKm == 10)
        // days that don't match the number of runs fall back to the suggested days
        #expect(plan(PlanSettings(runsPerWeek: 2, days: [1, 2, 3])).sessions.map(\.day) == ["Wed", "Sat"])
        #expect(plan(PlanSettings(runsPerWeek: 6)).sessions.count == 6)
        #expect(plan(PlanSettings(runsPerWeek: 1)).perWeek == 2)
    }

    @Test func growthAndEasierWeeks() {
        let runs = [run(mon.adding(-3).iso, 5)]
        let slow = plan(PlanSettings(growth: 0.05, easierEvery: 0, target: "half"), runs: runs)
        let fast = plan(PlanSettings(growth: 0.15, easierEvery: 0, target: "half"), runs: runs)
        #expect(slow.week.longKm == 5.3 && fast.week.longKm == 5.8)
        #expect(!slow.ahead.contains { $0.easier })        // never easier
        let every2 = plan(PlanSettings(easierEvery: 2, target: "half"), runs: runs)
        #expect(every2.ahead.filter { $0.easier }.count == 2)
        #expect(PlanSettings.targets.map { $0.id } == ["5k", "10k", "half", "full"] && PlanSettings.weekdayNames.count == 7)
    }

    @Test func oldSettingsStillLoad() throws {
        let old = #"{"name":"V","goalType":"runs","goalValue":3,"sleepNeedHours":8}"#
        let s = try JSONDecoder().decode(UserSettings.self, from: Data(old.utf8))
        #expect(s.name == "V" && s.plan == nil && s.race == nil)
    }
}

@Suite struct RacePlanTests {
    func settings(_ goal: RaceGoal, weeks: Int, per: Int = 3, long: Double = 2, strength: Bool = false) -> RaceSettings {
        RaceSettings(goal: goal, raceDate: mon.adding(7 * (weeks - 1) + 5), startDate: mon, runsPerWeek: per,
                     longRunDay: 6, strengthDay: strength, startLongKm: long)
    }

    @Test func fiveKInTenWeeks() {
        let p = Coach.racePlan(settings(.fiveK, weeks: 10))
        #expect(p.days.first?.day == mon && p.days.last?.kind == .race && p.days.last?.km == 5)
        #expect(p.weeks == 10 && p.peakLongKm == 3.5)
        #expect(p.warning?.contains("short of the 5.0 km") == true)     // 2 km to 5K takes longer than 10 weeks
        #expect(Coach.racePlan(settings(.fiveK, weeks: 16, long: 3)).warning == nil)
        let w1 = p.week(of: mon)
        #expect(w1.filter { $0.kind.isRun }.count == 3)
        #expect(w1.first { $0.day.weekday == 6 }?.kind == .long)
        #expect(w1.first { $0.day.weekday == 7 }?.kind == .rest)            // never the day after the long run
        #expect(w1.first { $0.kind == .long }?.detail.hasPrefix("Run 2 min, walk 1 min") == true)
        // quality sessions from week 3, alternating intervals and tempo, none in easier weeks
        let w3 = p.week(of: mon.adding(14)), w4 = p.week(of: mon.adding(21))
        #expect(w3.contains { $0.kind == .intervals })
        #expect(!w4.contains { $0.kind == .intervals || $0.kind == .tempo })
        #expect(p.week(of: mon.adding(35)).contains { $0.kind == .tempo })
        // race week: short runs, rest the two days before
        let rw = p.week(of: p.settings.raceDate)
        #expect(!rw.contains { $0.kind == .long })
        #expect(p.day(p.settings.raceDate.adding(-1))?.kind == .rest && p.day(p.settings.raceDate.adding(-2))?.kind == .rest)
        #expect(p.totalKm > 40)
    }

    @Test func marathonTooSoonWarnsAndSuggestsADate() {
        let p = Coach.racePlan(settings(.marathon, weeks: 8, per: 4))
        #expect(p.warning?.hasPrefix("Tight timeline") == true)
        #expect(p.suggestedDate > p.settings.raceDate && p.suggestedDate.weekday == 6)
        #expect(p.days.contains { $0.kind == .tempo } && p.week(of: mon).filter { $0.kind.isRun }.count == 4)
        let ok = Coach.racePlan(settings(.marathon, weeks: 40, per: 4, long: 8))
        #expect(ok.warning == nil && ok.peakLongKm == 32)
        let longs = ok.days.filter { $0.kind == .long }.map(\.km)
        #expect(longs.suffix(2).allSatisfy { $0 < 32 })                    // taper (race week has no long run)
        #expect(Coach.racePlan(RaceSettings(goal: .fiveK, raceDate: mon.adding(-3), startDate: mon)).warning == "The race date is before the plan starts.")
    }

    @Test func strengthDayEditsAndStatus() {
        var s = settings(.tenK, weeks: 6, per: 2, strength: true)
        let p = Coach.racePlan(s)
        #expect(p.week(of: mon).contains { $0.kind == .strength })
        #expect(Coach.runDays(longDay: 6, count: 2) == [3, 6] && Coach.runDays(longDay: 7, count: 4).count == 4)
        // your edits replace a day
        s.edits[mon.adding(2).iso] = PlanDay(day: mon.adding(2), kind: .rest, edited: true)
        s.edits[mon.adding(5).iso] = PlanDay(day: mon.adding(5), kind: .long, km: 3, edited: true, skipped: true)
        let e = Coach.racePlan(s)
        #expect(e.day(mon.adding(2))?.kind == .rest && e.day(mon.adding(2))?.edited == true && e.day(mon.adding(5))?.skipped == true)
        // done / missed / today / upcoming
        let data = HealthData(workouts: [run(mon.iso, 2), run(mon.adding(2).iso, 0.5), workout(mon.adding(4).iso, .strength)])
        let today = mon.adding(3)
        #expect(Coach.status(PlanDay(day: mon, kind: .easy, km: 2), data: data, today: today) == .done)
        #expect(Coach.status(PlanDay(day: mon.adding(2), kind: .easy, km: 2), data: data, today: today) == .missed)
        #expect(Coach.status(PlanDay(day: mon.adding(2), kind: .intervals, km: 2), data: data, today: today) == .done)
        #expect(Coach.status(PlanDay(day: today, kind: .easy, km: 2), data: data, today: today) == .today)
        #expect(Coach.status(PlanDay(day: mon.adding(5), kind: .easy, km: 2), data: data, today: today) == .upcoming)
        #expect(Coach.status(PlanDay(day: mon, kind: .rest), data: data, today: today) == .rest)
        #expect(Coach.status(PlanDay(day: mon.adding(4), kind: .strength), data: data, today: today) == .done)
        #expect(Coach.status(PlanDay(day: mon, kind: .easy, km: 2, skipped: true), data: data, today: today) == .skipped)
        let pr = Coach.progress(Coach.racePlan(settings(.fiveK, weeks: 4)), data: data, today: today)
        #expect(pr.planned >= 1 && pr.done <= pr.planned)
    }

    @Test func labelsAndRoundTrip() throws {
        #expect(RaceGoal.allCases.map { $0.km } == [5, 10, 21.1, 42.2] && RaceGoal.allCases.allSatisfy { !$0.label.isEmpty && $0.id == $0.rawValue })
        #expect(DayKind.allCases.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty && $0.id == $0.rawValue })
        #expect(PlanDay(day: mon, kind: .easy, km: 3).title == "Easy run · 3.0 km" && PlanDay(day: mon, kind: .rest).title == "Rest")
        #expect(Coach.weeksNeeded(from: 5, to: 4) == 0)
        let s = UserSettings(race: settings(.half, weeks: 12))
        #expect(try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(s)) == s)
    }
}
