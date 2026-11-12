import XCTest
@testable import RunCore

/// Roughly one meter of latitude in degrees.
private let degPerMeter = 1.0 / 111_195.0
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func sample(meters: Double, at seconds: TimeInterval, altitude: Double = 100, accuracy: Double = 5, speed: Double = -1) -> LocationSample {
    LocationSample(latitude: 40 + meters * degPerMeter, longitude: -74, altitude: altitude,
                   horizontalAccuracy: accuracy, verticalAccuracy: 4, speed: speed,
                   timestamp: t0.addingTimeInterval(seconds))
}

/// Runs at a steady speed for `seconds`, one fix per second, starting at `startMeters`.
@discardableResult
private func feed(_ tracker: inout RunTracker, from startSecond: Int, seconds: Int, speed: Double, startMeters: Double) -> [RunTracker.Event] {
    var events: [RunTracker.Event] = []
    for i in 0...seconds {
        events += tracker.add(sample(meters: startMeters + Double(i) * speed, at: Double(startSecond + i)))
    }
    return events
}

final class FormattingTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(Fmt.duration(0), "0:00")
        XCTAssertEqual(Fmt.duration(754), "12:34")
        XCTAssertEqual(Fmt.duration(3723), "1:02:03")
    }

    func testPace() {
        XCTAssertEqual(Fmt.pace(secondsPerMeter: 0.3, unit: .kilometers), "5:00")
        XCTAssertEqual(Fmt.pace(secondsPerMeter: 0.3, unit: .miles), "8:03")
        XCTAssertEqual(Fmt.pace(secondsPerMeter: nil, unit: .kilometers), "--:--")
        XCTAssertEqual(Fmt.pace(secondsPerMeter: 10, unit: .kilometers), "--:--")
        XCTAssertEqual(Fmt.pace(distance: 0, duration: 100, unit: .kilometers), "--:--")
    }

    func testDistanceTruncates() {
        XCTAssertEqual(Fmt.distance(5239, unit: .kilometers), "5.23")
        XCTAssertEqual(Fmt.distance(1609.344, unit: .miles), "1.00")
        XCTAssertEqual(Fmt.distance(999.9, unit: .kilometers), "0.99")
        XCTAssertEqual(Fmt.distance(10000, unit: .kilometers, decimals: 1), "10.0")
    }

    func testSpeech() {
        XCTAssertEqual(SpeechText.duration(307), "5 minutes 7 seconds")
        XCTAssertEqual(SpeechText.duration(3600), "1 hour")
        XCTAssertEqual(SpeechText.duration(0), "0 seconds")
        XCTAssertEqual(SpeechText.distance(1000, unit: .kilometers), "1 kilometer")
        XCTAssertEqual(SpeechText.distance(3000, unit: .kilometers), "3 kilometers")
        XCTAssertEqual(SpeechText.distance(2500, unit: .kilometers), "2.5 kilometers")
        XCTAssertEqual(SpeechText.measure(.distance(400), unit: .miles), "400 meters")
        let split = Split(index: 2, distance: 1000, duration: 300, elevationChange: 0, isPartial: false)
        let text = SpeechText.split(totalDistance: 2000, elapsed: 620, split: split, unit: .kilometers, targetPace: 0.3)
        XCTAssertTrue(text.contains("2 kilometers"))
        XCTAssertTrue(text.contains("Last kilometer, 5 minutes."))
        XCTAssertTrue(text.contains("Average pace, 5 minutes 10 seconds per kilometer."))
        XCTAssertTrue(text.contains("10 seconds per kilometer behind target."))
    }
}

final class RunTrackerTests: XCTestCase {
    func testSteadyRunDistanceTimeAndSplits() {
        var tracker = RunTracker()
        tracker.start(at: t0)
        // 4 m/s for 600 s = 2400 m.
        let events = feed(&tracker, from: 0, seconds: 600, speed: 4, startMeters: 0)
        XCTAssertEqual(tracker.distance, 2400, accuracy: 3)
        XCTAssertEqual(tracker.elapsed(at: t0.addingTimeInterval(600)), 600, accuracy: 0.001)
        XCTAssertEqual(tracker.splits.count, 2)
        XCTAssertEqual(tracker.splits[0].duration, 250, accuracy: 1)
        XCTAssertEqual(tracker.splits[1].duration, 250, accuracy: 1)
        XCTAssertEqual(events.filter { if case .split = $0 { return true } else { return false } }.count, 2)
        XCTAssertEqual(tracker.averagePace(at: t0.addingTimeInterval(600))!, 0.25, accuracy: 0.005)
        XCTAssertEqual(tracker.currentPace(at: t0.addingTimeInterval(600))!, 0.25, accuracy: 0.005)
    }

    func testRejectsInaccurateAndJumpingFixes() {
        var tracker = RunTracker()
        tracker.start(at: t0)
        feed(&tracker, from: 0, seconds: 10, speed: 3, startMeters: 0)
        let before = tracker.distance
        tracker.add(sample(meters: 500, at: 11))               // 470 m in one second: a jump
        tracker.add(sample(meters: 36, at: 12, accuracy: 80))  // too inaccurate
        XCTAssertEqual(tracker.distance, before, accuracy: 0.001)
        tracker.add(sample(meters: 39, at: 13))
        XCTAssertEqual(tracker.distance, 39, accuracy: 0.5)
    }

    func testJitterWhileStandingAddsNoDistance() {
        var config = RunTracker.Config()
        config.autoPause = false
        var tracker = RunTracker(config: config)
        tracker.start(at: t0)
        for i in 0..<120 {
            tracker.add(sample(meters: Double(i % 3) - 1, at: Double(i)))
        }
        XCTAssertEqual(tracker.distance, 0, accuracy: 0.001)
        XCTAssertEqual(tracker.state, .running)
    }

    func testManualPauseExcludesTimeAndDistance() {
        var tracker = RunTracker()
        tracker.start(at: t0)
        feed(&tracker, from: 0, seconds: 100, speed: 3, startMeters: 0)      // 300 m
        tracker.pause(at: t0.addingTimeInterval(100))
        // Walk 200 m while paused.
        for i in 101...200 { tracker.add(sample(meters: 300 + Double(i - 100) * 2, at: Double(i))) }
        XCTAssertEqual(tracker.distance, 300, accuracy: 1)
        XCTAssertEqual(tracker.elapsed(at: t0.addingTimeInterval(200)), 100, accuracy: 0.001)
        tracker.resume(at: t0.addingTimeInterval(200))
        feed(&tracker, from: 200, seconds: 100, speed: 3, startMeters: 500)  // another 300 m
        XCTAssertEqual(tracker.distance, 600, accuracy: 2)
        XCTAssertEqual(tracker.elapsed(at: t0.addingTimeInterval(300)), 200, accuracy: 0.001)
        tracker.finish(at: t0.addingTimeInterval(300))
        XCTAssertEqual(tracker.state, .finished)
        XCTAssertEqual(tracker.pauseIntervals.count, 1)
        XCTAssertEqual(tracker.pauseIntervals[0].duration, 100, accuracy: 0.001)
        // Elapsed never decreases along the track.
        XCTAssertTrue(zip(tracker.points, tracker.points.dropFirst()).allSatisfy { $0.e <= $1.e && $0.d <= $1.d })
    }

    func testAutoPauseAndResume() {
        var tracker = RunTracker()
        tracker.start(at: t0)
        feed(&tracker, from: 0, seconds: 60, speed: 3, startMeters: 0)       // 180 m
        var events: [RunTracker.Event] = []
        // Stand still for 30 s.
        for i in 61...90 { events += tracker.add(sample(meters: 180, at: Double(i))) }
        XCTAssertEqual(events, [.autoPaused])
        XCTAssertEqual(tracker.state, .autoPaused)
        let pausedElapsed = tracker.elapsed(at: t0.addingTimeInterval(90))
        XCTAssertEqual(pausedElapsed, 66, accuracy: 1.5)
        // Start running again.
        events = feed(&tracker, from: 91, seconds: 30, speed: 3, startMeters: 183)
        XCTAssertEqual(events.first, .autoResumed)
        XCTAssertEqual(tracker.state, .running)
        XCTAssertEqual(tracker.distance, 180 + 90, accuracy: 12)
        XCTAssertLessThan(tracker.elapsed(at: t0.addingTimeInterval(121)), 100)
    }

    func testLostSignalDoesNotAutoPause() {
        var tracker = RunTracker()
        tracker.start(at: t0)
        feed(&tracker, from: 0, seconds: 10, speed: 3, startMeters: 0)
        // No fixes at all, then only inaccurate ones: the clock keeps running.
        XCTAssertEqual(tracker.tick(at: t0.addingTimeInterval(20)), [])
        for i in 21...60 { tracker.add(sample(meters: 30, at: Double(i), accuracy: 90)) }
        XCTAssertEqual(tracker.tick(at: t0.addingTimeInterval(60)), [])
        XCTAssertEqual(tracker.state, .running)
        XCTAssertEqual(tracker.elapsed(at: t0.addingTimeInterval(60)), 60, accuracy: 0.001)
        // Signal returns 150 m further on: the gap is bridged in a straight line.
        tracker.add(sample(meters: 180, at: 61))
        XCTAssertEqual(tracker.distance, 180, accuracy: 1)
    }

    func testTickAutoPausesWhenFixesShowNoMovement() {
        var tracker = RunTracker()
        tracker.start(at: t0)
        feed(&tracker, from: 0, seconds: 10, speed: 3, startMeters: 0)
        XCTAssertEqual(tracker.tick(at: t0.addingTimeInterval(12)), [])
        var events: [RunTracker.Event] = []
        for i in 11...20 { events += tracker.add(sample(meters: 30, at: Double(i))) }
        XCTAssertEqual(events, [.autoPaused])
    }

    func testManualPauseDuringAutoPauseIsNotAutoResumed() {
        var tracker = RunTracker()
        tracker.start(at: t0)
        feed(&tracker, from: 0, seconds: 10, speed: 3, startMeters: 0)
        for i in 11...20 { tracker.add(sample(meters: 30, at: Double(i))) }
        XCTAssertEqual(tracker.state, .autoPaused)
        tracker.pause(at: t0.addingTimeInterval(21))
        feed(&tracker, from: 22, seconds: 20, speed: 3, startMeters: 30)
        XCTAssertEqual(tracker.state, .paused)
        XCTAssertEqual(tracker.distance, 30, accuracy: 1)
    }

    func testElevationGainIgnoresNoise() {
        var tracker = RunTracker()
        tracker.start(at: t0)
        // Flat with +-1 m noise for 200 s, then a steady 30 m climb over 300 s.
        for i in 0...200 {
            tracker.add(sample(meters: Double(i) * 3, at: Double(i), altitude: 100 + (i % 2 == 0 ? 1 : -1)))
        }
        XCTAssertEqual(tracker.elevationGain, 0, accuracy: 0.001)
        for i in 201...500 {
            tracker.add(sample(meters: Double(i) * 3, at: Double(i), altitude: 100 + Double(i - 200) * 0.1))
        }
        XCTAssertEqual(tracker.elevationGain, 30, accuracy: 4)
    }

    func testMileSplits() {
        var config = RunTracker.Config()
        config.splitLength = DistanceUnit.miles.meters
        var tracker = RunTracker(config: config)
        tracker.start(at: t0)
        feed(&tracker, from: 0, seconds: 1000, speed: 3.5, startMeters: 0)   // 3500 m
        XCTAssertEqual(tracker.splits.count, 2)
        XCTAssertEqual(tracker.splits[0].duration, 1609.344 / 3.5, accuracy: 1.5)
    }
}

final class SplitAndRecordTests: XCTestCase {
    /// `segments` are (meters, seconds) run back to back at a steady speed, sampled every 5 s.
    private func track(_ segments: [(Double, Double)]) -> [TrackPoint] {
        var points = [TrackPoint(lat: 0, lon: 0, alt: 0, time: t0, d: 0, e: 0)]
        var d = 0.0, e = 0.0
        for (meters, seconds) in segments {
            let steps = Int(seconds / 5)
            for _ in 0..<steps {
                d += meters / Double(steps)
                e += seconds / Double(steps)
                points.append(TrackPoint(lat: 0, lon: 0, alt: 0, time: t0.addingTimeInterval(e), d: d, e: e))
            }
        }
        return points
    }

    func testSplitsWithPartial() {
        let points = track([(1000, 300), (1000, 280), (500, 150)])
        let splits = SplitCalculator.splits(points: points, splitLength: 1000)
        XCTAssertEqual(splits.count, 3)
        XCTAssertEqual(splits[0].duration, 300, accuracy: 0.5)
        XCTAssertEqual(splits[1].duration, 280, accuracy: 0.5)
        XCTAssertTrue(splits[2].isPartial)
        XCTAssertEqual(splits[2].distance, 500, accuracy: 0.5)
        XCTAssertEqual(splits.map(\.duration).reduce(0, +), 730, accuracy: 0.5)
    }

    func testFastestEffortFindsQuickSection() {
        // Slow km, fast km (240 s), slow km.
        let points = track([(1000, 360), (1000, 240), (1000, 360)])
        XCTAssertEqual(BestEfforts.fastest(points: points, target: 1000)!, 240, accuracy: 1)
        XCTAssertEqual(BestEfforts.fastest(points: points, target: 2990)!, 960 - 3.6, accuracy: 1)
        XCTAssertNil(BestEfforts.fastest(points: points, target: 5000))
        let all = BestEfforts.all(points: points)
        XCTAssertEqual(Set(all.keys), [1000, 1609])
        // Fastest mile covers the fast km plus 609 m of slow running.
        XCTAssertEqual(all[1609]!, 240 + 609.344 * 0.36, accuracy: 2)
    }

    func testChartSeries() {
        let points = track([(1000, 300), (1000, 250)])
        let pace = ChartSeries.pace(points: points, buckets: 20)
        XCTAssertEqual(pace.count, 20)
        XCTAssertEqual(pace.first!.value, 0.3, accuracy: 0.01)
        XCTAssertEqual(pace.last!.value, 0.25, accuracy: 0.01)
        XCTAssertFalse(ChartSeries.elevation(points: points).isEmpty)
        XCTAssertTrue(ChartSeries.pace(points: []).isEmpty)
    }

    func testThumbnailFitsUnitSquare() {
        var points: [TrackPoint] = []
        for i in 0..<500 {
            points.append(TrackPoint(lat: 40 + Double(i) * 0.0001, lon: -74 + Double(i % 50) * 0.0001, alt: 0, time: t0, d: 0, e: 0))
        }
        let flat = RouteThumbnail.normalized(points, maxPoints: 50)
        XCTAssertFalse(flat.isEmpty)
        XCTAssertEqual(flat.count % 2, 0)
        XCTAssertLessThanOrEqual(flat.count / 2, 52)
        XCTAssertTrue(flat.allSatisfy { $0 >= -1e-9 && $0 <= 1 + 1e-9 })
        XCTAssertTrue(RouteThumbnail.normalized([points[0]]).isEmpty)
    }
}

final class WorkoutTests: XCTestCase {
    func testMakeIntervalWorkout() {
        let w = IntervalWorkout.make(name: "t", warmup: 300, repeats: 3, run: .distance(400), recover: .time(60), cooldown: 300)
        XCTAssertEqual(w.steps.map(\.kind), [.warmup, .run, .recover, .run, .recover, .run, .cooldown])
        XCTAssertEqual(w.runStepCount, 3)
        let bare = IntervalWorkout.make(name: "t", warmup: nil, repeats: 2, run: .time(60), recover: .time(30), cooldown: nil)
        XCTAssertEqual(bare.steps.map(\.kind), [.run, .recover, .run])
    }

    func testIntervalProgression() {
        let w = IntervalWorkout.make(name: "t", warmup: 60, repeats: 2, run: .distance(400), recover: .time(30), cooldown: nil)
        var p = IntervalProgress(workout: w)
        XCTAssertEqual(p.currentStep?.kind, .warmup)
        XCTAssertEqual(p.update(elapsed: 30, distance: 80), [])
        XCTAssertEqual(p.remaining, 30, accuracy: 0.001)
        XCTAssertEqual(p.update(elapsed: 61, distance: 160), [.stepStarted(1)])
        XCTAssertEqual(p.currentRepeat, 1)
        XCTAssertEqual(p.remaining, 400, accuracy: 0.001)
        XCTAssertEqual(p.update(elapsed: 150, distance: 500), [])
        XCTAssertEqual(p.update(elapsed: 170, distance: 565), [.stepStarted(2)])
        // Recovery is timed from when the run step ended.
        XCTAssertEqual(p.update(elapsed: 199, distance: 600), [])
        XCTAssertEqual(p.update(elapsed: 200, distance: 602), [.stepStarted(3)])
        XCTAssertEqual(p.currentRepeat, 2)
        XCTAssertEqual(p.update(elapsed: 320, distance: 1010), [.workoutFinished])
        XCTAssertTrue(p.isFinished)
        XCTAssertEqual(p.update(elapsed: 400, distance: 1200), [])
    }

    func testIntervalSkipAndBigJump() {
        let w = IntervalWorkout.make(name: "t", warmup: 60, repeats: 2, run: .time(10), recover: .time(10), cooldown: nil)
        var p = IntervalProgress(workout: w)
        XCTAssertEqual(p.skip(), [.stepStarted(1)])
        // A long gap between updates walks through several steps at once.
        XCTAssertEqual(p.update(elapsed: 100, distance: 0), [.stepStarted(2), .stepStarted(3), .workoutFinished])
    }

    func testGoalProgress() {
        var g = GoalProgress(goal: .distance(5000))
        XCTAssertEqual(g.update(elapsed: 10, distance: 1000), [])
        XCTAssertEqual(g.update(elapsed: 10, distance: 2500), [.halfway])
        XCTAssertEqual(g.update(elapsed: 10, distance: 3000), [])
        XCTAssertEqual(g.update(elapsed: 10, distance: 5001), [.completed])
        XCTAssertEqual(g.update(elapsed: 10, distance: 6000), [])
        XCTAssertEqual(g.fraction, 1)
        var t = GoalProgress(goal: .time(600))
        XCTAssertEqual(t.update(elapsed: 700, distance: 0), [.completed])
        XCTAssertEqual(GoalProgress.paceDelta(target: 0.3, elapsed: 310, distance: 1000)!, 0.01, accuracy: 1e-9)
    }
}

final class StatsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testWeeklyBuckets() {
        // 2026-11-12 is a Thursday; its week starts Monday 2026-11-09.
        let now = day(2026, 11, 12)
        let runs = [
            RunSummary(date: day(2026, 11, 9), distance: 5000, duration: 1500),
            RunSummary(date: day(2026, 11, 11), distance: 3000, duration: 900),
            RunSummary(date: day(2026, 11, 8), distance: 10000, duration: 3200),
            RunSummary(date: day(2026, 1, 1), distance: 99999, duration: 1)
        ]
        let buckets = Stats.buckets(runs, period: .week, count: 4, now: now, calendar: calendar)
        XCTAssertEqual(buckets.count, 4)
        XCTAssertEqual(buckets[3].start, day(2026, 11, 9, hour: 0))
        XCTAssertEqual(buckets[3].distance, 8000)
        XCTAssertEqual(buckets[3].runCount, 2)
        XCTAssertEqual(buckets[2].distance, 10000)
        XCTAssertEqual(buckets[0].distance, 0)
        XCTAssertEqual(Stats.current(runs, period: .month, now: now, calendar: calendar).distance, 18000)
        XCTAssertEqual(Stats.buckets(runs, period: .year, count: 2, now: now, calendar: calendar).map(\.runCount), [0, 4])
    }

    func testStreaks() {
        let today = day(2026, 11, 12)
        let dates = [day(2026, 11, 11), day(2026, 11, 10), day(2026, 11, 10, hour: 18), day(2026, 11, 9),
                     day(2026, 11, 1), day(2026, 10, 31), day(2026, 10, 30), day(2026, 10, 29)]
        XCTAssertEqual(Stats.currentDayStreak(dates: dates, today: today, calendar: calendar), 3)
        XCTAssertEqual(Stats.currentDayStreak(dates: dates + [today], today: today, calendar: calendar), 4)
        XCTAssertEqual(Stats.currentDayStreak(dates: dates, today: day(2026, 11, 14), calendar: calendar), 0)
        XCTAssertEqual(Stats.longestDayStreak(dates: dates, calendar: calendar), 4)
        XCTAssertEqual(Stats.longestDayStreak(dates: [], calendar: calendar), 0)
        XCTAssertEqual(Stats.currentWeekStreak(dates: dates, today: today, calendar: calendar), 1)
        XCTAssertEqual(Stats.currentWeekStreak(dates: dates + [day(2026, 11, 4)], today: today, calendar: calendar), 3)
    }
}

final class PlanTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testEveryCombinationIsWellFormed() {
        let start = day(2026, 11, 12)
        for race in RaceDistance.allCases {
            for level in RunnerLevel.allCases {
                for perWeek in 3...5 {
                    for weeksAhead in [2, 3, 5, 8, 12, 16, 24] {
                        let raceDate = calendar.date(byAdding: .day, value: weeksAhead * 7 - 1, to: start)!
                        let label = "\(race) \(level) \(perWeek)/wk \(weeksAhead)wk"
                        guard let plan = PlanGenerator.generate(race: race, level: level, runsPerWeek: perWeek,
                                                                start: start, raceDate: raceDate, calendar: calendar) else {
                            XCTFail("no plan for \(label)"); continue
                        }
                        let all = plan.allWorkouts
                        XCTAssertEqual(plan.weeks.count, weeksAhead, label)
                        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "unique ids: \(label)")
                        XCTAssertEqual(all.map(\.date), all.map(\.date).sorted(), "chronological: \(label)")
                        XCTAssertTrue(all.allSatisfy { $0.date >= start && $0.date <= raceDate }, label)
                        XCTAssertEqual(all.last?.kind, .race, label)
                        XCTAssertEqual(all.last?.date, raceDate, label)
                        XCTAssertEqual(all.filter { $0.kind == .race }.count, 1, label)
                        for week in plan.weeks.dropLast() {
                            XCTAssertEqual(week.workouts.count, perWeek, "runs in week \(week.number): \(label)")
                            XCTAssertEqual(week.workouts.filter { $0.kind == .long }.count, 1, label)
                        }
                        for w in all where w.kind == .tempo || w.kind == .intervals {
                            XCTAssertNotNil(w.intervals, label)
                            XCTAssertFalse(w.intervals!.steps.isEmpty, label)
                        }
                        for w in all where w.kind == .easy || w.kind == .long {
                            XCTAssertGreaterThan(w.distance ?? 0, 0, label)
                        }

                        // Long runs build gradually and never exceed the peak.
                        let longs = all.filter { $0.kind == .long }.map { $0.distance! / 1000 }
                        let peak = PlanGenerator.peakLongRun(race, level)
                        XCTAssertLessThanOrEqual(longs.max() ?? 0, peak, label)
                        for (a, b) in zip(longs, longs.dropFirst()) {
                            XCTAssertLessThanOrEqual(b - a, peak * 0.33 + 0.5, "long run jump \(a)->\(b): \(label)")
                        }
                        if weeksAhead >= 8 {
                            XCTAssertEqual(longs.max()!, peak, accuracy: 0.5, label)
                            // Taper: the last long run before race week is shorter than the peak.
                            XCTAssertLessThan(longs.last!, peak, label)
                        }
                    }
                }
            }
        }
    }

    func testPartialFirstWeekAndLimits() {
        // Start Thursday, race on a Sunday 6 weeks + 3 days later: first week is partial.
        let start = day(2026, 11, 12)
        let raceDate = day(2026, 12, 27)
        let plan = PlanGenerator.generate(race: .tenK, level: .intermediate, runsPerWeek: 4,
                                          start: start, raceDate: raceDate, calendar: calendar)!
        XCTAssertEqual(plan.weeks.count, 7)
        XCTAssertLessThan(plan.weeks[0].workouts.count, 4)
        XCTAssertTrue(plan.allWorkouts.allSatisfy { $0.date >= start })
        // Long runs land on the race weekday.
        for w in plan.allWorkouts where w.kind == .long {
            XCTAssertEqual(calendar.component(.weekday, from: w.date), calendar.component(.weekday, from: raceDate))
        }
        XCTAssertNil(PlanGenerator.generate(race: .fiveK, level: .beginner, runsPerWeek: 3,
                                            start: start, raceDate: day(2026, 11, 15), calendar: calendar))
        XCTAssertNil(PlanGenerator.generate(race: .fiveK, level: .beginner, runsPerWeek: 3,
                                            start: start, raceDate: day(2028, 1, 1), calendar: calendar))
        XCTAssertEqual(plan.workout(on: raceDate, calendar: calendar)?.kind, .race)
        let next = plan.nextWorkout(after: start, calendar: calendar, excluding: [plan.allWorkouts[0].id])
        XCTAssertEqual(next?.id, plan.allWorkouts[1].id)
    }

    func testPlanRoundTripsThroughJSON() throws {
        let plan = PlanGenerator.generate(race: .half, level: .advanced, runsPerWeek: 5,
                                          start: day(2026, 11, 12), raceDate: day(2027, 3, 14), calendar: calendar)!
        let data = try JSONEncoder().encode(plan)
        XCTAssertEqual(try JSONDecoder().decode(TrainingPlan.self, from: data), plan)
    }
}
