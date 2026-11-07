import Foundation
import Testing
@testable import FitnessCore

/// Answers like Garmin, from made-up data. Records every request.
final class FakeGarmin: GarminTransport, @unchecked Sendable {
    var calls: [String] = []
    var tokenCode = 200
    /// path prefix -> HTTP status to fail with
    var fail: [String: Int] = [:]
    /// path prefix -> how many times to fail before answering
    var failTimes: [String: Int] = [:]
    var tokens = 0
    var throwNetwork = 0
    let today: Day
    let lock = NSLock()

    init(today: Day) { self.today = today }

    func send(_ r: URLRequest) async throws -> (Data, Int) {
        let url = r.url!.absoluteString.replacingOccurrences(of: GarminClient.base.absoluteString, with: "")
        lock.lock(); calls.append(url); lock.unlock()
        if throwNetwork > 0 { throwNetwork -= 1; throw URLError(.notConnectedToInternet) }
        if url.hasPrefix(GarminClient.tokenPath) {
            #expect(r.value(forHTTPHeaderField: "Authorization") == "ApiKey test-key")
            tokens += 1
            return (Data("\"tok-\(tokens)\"\n".utf8), tokenCode)
        }
        #expect(r.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer tok-") == true)
        for (p, n) in failTimes where url.hasPrefix(p) && n > 0 {
            failTimes[p] = n - 1
            return (Data(), p.contains("401") ? 401 : 500)
        }
        for (p, code) in fail where url.hasPrefix(p) { return (Data(), code) }
        let body: Any
        func days(_ q: String) -> [Day] {
            let parts = q.split(separator: "&").map { $0.split(separator: "=").last.map(String.init) ?? "" }
            var out: [Day] = [], d = Day(parts[0])
            while d <= Day(parts[1]) { out.append(d); d = d.adding(1) }
            return out
        }
        if url.hasPrefix("/activitylist-service") {
            let q = Dictionary(uniqueKeysWithValues: url.split(separator: "?")[1].split(separator: "&").map {
                ($0.split(separator: "=")[0], Int($0.split(separator: "=")[1])!) })
            let all = (0..<30).map { i -> [String: Any] in
                let d = today.adding(-i * 3)
                return ["activityId": 1000 - i, "activityName": i % 2 == 0 ? "Easy Run" : "Walk",
                        "startTimeLocal": "\(d.iso) 07:30:00",
                        "activityType": ["typeKey": i % 2 == 0 ? "running" : "walking"],
                        "distance": 3000 + i * 100, "duration": 1200 + i * 30, "averageHR": 140, "maxHR": 170,
                        "calories": 250, "activityTrainingLoad": 60, "aerobicTrainingEffect": 2.8,
                        "hrTimeInZone_1": 60, "hrTimeInZone_2": 300, "hrTimeInZone_3": 600, "hrTimeInZone_4": 200, "hrTimeInZone_5": 40,
                        "averageRunningCadenceInStepsPerMinute": 160, "avgStrideLength": 95.0, "averageSpeed": 2.5,
                        "elevationGain": 20, "fastestSplit_1000": 330, "steps": 3200]
            }
            body = Array(all.dropFirst(q["start"]!).prefix(q["limit"]!))
        } else if url.hasPrefix("/usersummary-service") {
            body = ["data": days(String(url.split(separator: "?")[1])).map { d -> [String: Any] in
                ["calendarDate": d.iso,
                 "movement": ["steps": ["value": 8000, "goal": 7000, "distanceInMeters": 6000], "floorsAscended": ["value": 8, "goal": 10]],
                 "heartRate": ["restingValue": 58, "minValue": 50, "maxValue": 150],
                 "intensityMinutes": ["moderate": 20, "vigorous": 10, "goal": 150],
                 "stress": ["avgLevel": 30, "maxLevel": 80, "restProportion": 0.3, "lowStressProportion": 0.4,
                            "mediumStressProportion": 0.2, "highStressProportion": 0.1],
                 "bodyBattery": ["maxValue": 85, "minValue": 20, "latestValue": 50, "chargedValue": 60, "drainedValue": 55],
                 "calories": ["burnedActive": 500, "burnedTotal": 2400], "respiration": ["avgValue": 15],
                 "wellnessChronology": ["endTimestampLocal": "\(d.iso)T18:45:00.0"]]
            }]
        } else if url.hasPrefix("/sleep-service") {
            body = days(String(url.split(separator: "?")[1])).map { d -> [String: Any] in
                ["calendarDate": d.iso, "sleepTimeSeconds": 7 * 3600, "deepSleepSeconds": 3600, "lightSleepSeconds": 14400,
                 "remSleepSeconds": 5400, "awakeSleepSeconds": 600, "sleepScores": ["overall": ["value": 78]],
                 "avgSleepStress": 20, "sleepNeed": ["actual": 480],
                 "sleepStartTimestampLocal": d.adding(-1).date.timeIntervalSince1970 * 1000 + 23 * 3600_000,
                 "sleepEndTimestampLocal": d.date.timeIntervalSince1970 * 1000 + 6 * 3600_000]
            }
        } else if url.hasPrefix("/hrv-service") {
            let p = url.split(separator: "/")
            var out: [[String: Any]] = [], d = Day(String(p[p.count - 2]))
            while d <= Day(String(p.last!)) { out.append(["calendarDate": d.iso, "lastNightAvg": 45, "weeklyAvg": 44, "status": "BALANCED"]); d = d.adding(1) }
            body = ["hrvSummaries": out]
        } else if url.hasPrefix("/wellness-service/wellness/dailyHeartRate") {
            let d = Day(String(url.split(separator: "=").last!))
            let midnight = d.date.timeIntervalSince1970 * 1000 - 5.5 * 3600_000       // GMT ms of local midnight in India
            body = ["startTimestampLocal": "\(d.iso)T00:00:00.0", "startTimestampGMT": "\(d.adding(-1).iso)T18:30:00.0",
                    "lastSevenDaysAvgRestingHeartRate": 59,
                    "heartRateValues": (0..<10).map { [midnight + Double($0) * 120_000, $0 == 0 ? NSNull() : 70 + $0] as [Any] }]
        } else if url.hasPrefix("/wellness-service/wellness/bodyBattery") {
            let d = Day(String(url.split(separator: "=").last!))
            let midnight = d.date.timeIntervalSince1970 * 1000 - 5.5 * 3600_000
            body = [["bodyBatteryValuesArray": (0..<5).map { [midnight + Double($0) * 3600_000, 20 + $0 * 10] }]]
        } else if url.contains("/details?") {
            let keys = ["sumElapsedDuration", "sumDistance", "directHeartRate", "directSpeed", "directDoubleCadence", "directElevation"]
            body = ["metricDescriptors": keys.enumerated().map { ["metricsIndex": $0.offset, "key": $0.element] },
                    "activityDetailMetrics": (0..<20).map { i in ["metrics": [i * 10, i * 25, 130 + i, 2.5, 160, 100 + i % 3]] }]
        } else if url.hasPrefix("/activity-service/activity/") {
            body = ["splitSummaries": [["splitType": "RWD_RUN", "duration": 600], ["splitType": "RWD_WALK", "duration": 300],
                                       ["splitType": "RWD_STAND", "duration": 30], ["splitType": "INTERVAL_ACTIVE", "duration": 9]]]
        } else {
            return (Data(), 404)
        }
        return (try JSONSerialization.data(withJSONObject: body), 200)
    }
}

let gToday = Day("2026-11-06")

func client(_ fake: FakeGarmin) -> GarminClient { GarminClient(key: "test-key", transport: fake, pause: { _ in }) }

@Suite struct GarminClientTests {
    @Test func tokenIsReusedAndRenewedOn401() async throws {
        let fake = FakeGarmin(today: gToday)
        let c = client(fake)
        _ = try await c.get("/hrv-service/hrv/daily/2026-11-01/2026-11-02")
        _ = try await c.get("/hrv-service/hrv/daily/2026-11-01/2026-11-02")
        #expect(fake.tokens == 1)
        fake.failTimes["/hrv-service/401"] = 1
        _ = try? await c.get("/hrv-service/401")
        #expect(fake.tokens == 2)                             // renewed once
    }

    @Test func refusedKeyAndEmptyToken() async {
        let fake = FakeGarmin(today: gToday)
        fake.tokenCode = 401
        await #expect(throws: GarminError.refused(401)) { try await client(fake).newToken() }
        #expect(GarminError.refused(401).errorDescription!.contains("mistyped or expired"))
        #expect(GarminError.emptyToken.errorDescription != nil && GarminError.http(500).errorDescription != nil)
    }

    @Test func busyServerIsRetriedThenErrorsSurface() async throws {
        let fake = FakeGarmin(today: gToday)
        fake.fail["/busy"] = 503
        await #expect(throws: GarminError.http(503)) { try await client(fake).get("/busy", retries: 2) }
        #expect(fake.calls.filter { $0 == "/busy" }.count == 3)
        let c = client(fake)
        try await c.newToken()
        fake.throwNetwork = 1
        #expect(try await c.get("/hrv-service/hrv/daily/2026-11-01/2026-11-01") != nil)    // retried after a network blip
        fake.throwNetwork = 10
        await #expect(throws: GarminError.self) { try await client(fake).get("/x", retries: 1) }
        #expect(GarminError.unreachable("offline").errorDescription == "Could not reach Garmin: offline")
    }
}

@Suite struct GarminSyncTests {
    @Test func firstSyncDownloadsEverything() async throws {
        let fake = FakeGarmin(today: gToday)
        let c = try await GarminSync(client: client(fake), pause: 0).run(GarminCache(), today: gToday, history: 90)
        #expect(c.workouts.count == 30 && c.start == gToday.adding(-90) && c.through == gToday && c.lastSync != nil)
        let d = c.data
        let today = try #require(d.day(gToday))
        #expect(today.steps == 8000 && today.exerciseMinutes == 40 && today.stressAvg == 30 && today.bbHigh == 85)
        #expect(today.hrv == 45 && today.hrvStatus == "BALANCED" && today.syncedAt == "18:45" && today.restingHR7 == 59)
        #expect(today.stressMix?.count == 4 && today.floors == 8)
        let n = try #require(d.night(gToday))
        #expect(n.asleepHours == 7 && n.score == 78 && n.needHours == 8 && n.bedtime == 300 && n.wake == 720)
        let run = try #require(d.workouts.last { $0.sport == .run })
        #expect(run.isGarmin && run.load == 60 && run.zones?.count == 5 && run.strideM == 0.95 && run.fastest1k == 330)
        #expect(run.typeName == "running" && GarminParse.activityID(run) == "1000")
        // graphs through the day: India is GMT+5:30, first reading has no value
        let detail = try #require(d.dayDetails[gToday])
        #expect(detail.hr.first == [2, 71] && detail.bb.first == [0, 20] && detail.bb.count == 5)
        #expect(c.dayDetails.count == 7)
        let wd = try #require(c.workoutDetails[run.id])
        #expect(wd.t.count == 20 && wd.hr.first == 130 && wd.runMin == 10 && wd.walkMin == 5 && wd.standMin == 0.5 && !wd.isEmpty)
    }

    @Test func laterSyncsOnlyFetchWhatsNew() async throws {
        let fake = FakeGarmin(today: gToday)
        let sync = GarminSync(client: client(fake), pause: 0)
        let first = try await sync.run(GarminCache(), today: gToday, history: 30)
        fake.calls = []
        _ = try await sync.run(first, today: gToday, history: 30)
        #expect(fake.calls.filter { $0.hasPrefix("/activitylist") }.count == 1)          // stops at a known workout
        #expect(fake.calls.contains { $0.contains("startDate=\(gToday.adding(-3).iso)&endDate=\(gToday.iso)") })
        #expect(fake.calls.filter { $0.contains("dailyHeartRate") }.count == 1)           // only today again
    }

    @Test func tooBigResponsesAreSplitAndBadDaysSkipped() async throws {
        let fake = FakeGarmin(today: gToday)
        fake.failTimes["/usersummary-service"] = 1                  // first 60-day chunk too big: halved
        fake.failTimes["/activitylist-service/activities/search/activities?start=0&limit=20"] = 1
        fake.fail["/sleep-service"] = 404                           // skipped
        fake.fail["/wellness-service/wellness/dailyHeartRate?date=\(gToday.adding(-1).iso)"] = 503
        let c = try await GarminSync(client: client(fake), pause: 0).run(GarminCache(), today: gToday, history: 60)
        #expect(fake.calls.contains { $0.contains("limit=10") })
        #expect(c.days.count == 61 && c.nights.isEmpty && c.workouts.count == 21)
        #expect(c.dayDetails[gToday.adding(-1).iso] == nil)        // tried again next time
    }

    @Test func activityListThatKeepsFailingStops() async throws {
        let fake = FakeGarmin(today: gToday)
        fake.fail["/activitylist-service"] = 500
        let c = try await GarminSync(client: client(fake), pause: 0).run(GarminCache(), today: gToday, history: 10)
        #expect(c.workouts.isEmpty)
        #expect(fake.calls.filter { $0.hasPrefix("/activitylist") }.count == 4 * GarminSync.maxSkips)
    }
}

@Suite struct GarminParseTests {
    @Test func sportsAndOddInput() {
        #expect(["treadmill_running", "walking", "road_biking", "lap_swimming", "hiking", "strength_training", "golf"].map(GarminParse.sport)
                == [.run, .walk, .cycle, .swim, .hike, .strength, .other])
        #expect(GarminParse.daily(["calendarDate": "2026-11-01"]) == nil)       // watch off
        #expect(GarminParse.daily([:]) == nil)
        #expect(GarminParse.sleep(["calendarDate": "2026-11-01", "sleepTimeSeconds": 0]) == nil)
        #expect(GarminParse.hrv(["calendarDate": "2026-11-01"]) == nil)
        #expect(GarminParse.activity(["activityId": 1]) == nil)
        let w = GarminParse.activity(["activityId": 5, "startTimeLocal": "2026-11-01 07:00:00", "activityType": NSNull()])!
        #expect(w.name == "Activity" && w.sport == .other && w.zones == nil && w.strideM == nil)
        #expect(GarminParse.dayHeartRate(nil).points.isEmpty && GarminParse.dayBodyBattery(nil, offsetMs: 0, midnightUTC: Date()).isEmpty)
        #expect(GarminParse.detail(nil, summary: nil).isEmpty)
        #expect(num(true as Any) == nil && num(3) == 3)
        #expect(GarminParse.activityID(Workout(id: "x", day: gToday, start: Date(), sport: .run, name: "", km: 0, minutes: 0)) == nil)
    }
}

@Suite struct MergeTests {
    @Test func garminFirstAppleFillsGaps() {
        let start = gToday.date.addingTimeInterval(8 * 3600)
        var g = Workout(id: "garmin-1", day: gToday, start: start, sport: .run, name: "Run", km: 5, minutes: 30)
        g.source = "garmin"
        let dup = Workout(id: "hk-1", day: gToday, start: start.addingTimeInterval(120), sport: .run, name: "Run", km: 5, minutes: 30)
        let other = Workout(id: "hk-2", day: gToday, start: start.addingTimeInterval(7200), sport: .swim, name: "Swim", km: 1, minutes: 30)
        var gd = DaySummary(day: gToday, steps: 9000); gd.bbHigh = 80
        let apple = HealthData(days: [DaySummary(day: gToday, steps: 8000, hrv: 40, activeKcal: 300), DaySummary(day: gToday.adding(-1), steps: 5000)],
                               nights: [SleepNight(day: gToday, asleepHours: 6)], workouts: [dup, other])
        let garmin = HealthData(days: [gd], nights: [SleepNight(day: gToday, asleepHours: 7)], workouts: [g])
        let m = HealthData.merge(apple: apple, garmin: garmin)
        #expect(m.day(gToday)?.steps == 9000 && m.day(gToday)?.hrv == 40 && m.day(gToday)?.activeKcal == 300 && m.day(gToday)?.bbHigh == 80)
        #expect(m.day(gToday.adding(-1))?.steps == 5000)
        #expect(m.night(gToday)?.asleepHours == 7)
        #expect(m.workouts.map(\.id) == ["garmin-1", "hk-2"])
        #expect(HealthData.merge(apple: apple, garmin: nil) == apple)
    }
}

@Suite struct InsightTests {
    let data = DemoData.make(today: gToday)

    @Test func readinessUsesGarminSignals() {
        let r = Coach.readiness(data, settings: UserSettings(), today: gToday)
        #expect(r.signals.map(\.id) == ["hrv", "sleep", "rhr", "bb", "load"])
        #expect(r.signals[0].note.contains("Garmin") || r.signals[0].note.contains("average"))
        #expect(r.signals[1].note.hasPrefix("Sleep score"))
        #expect(Coach.bodyBatterySignal(nil) == nil && Coach.bodyBatterySignal(40)?.state == .poor && Coach.bodyBatterySignal(60)?.state == .ok)
        #expect(Coach.hrvSignal(today: 40, previous: [], status: "LOW").state == .poor)
        #expect(Coach.hrvSignal(today: 40, previous: [], status: "UNBALANCED").state == .ok)
        #expect(Coach.sleepSignal({ var n = SleepNight(day: gToday, asleepHours: 7); n.score = 55; return n }(), need: 8).state == .poor)
    }

    @Test func tilesWeeksZonesAndBiggest() {
        let t = Coach.trainingTiles(data, today: gToday)
        #expect(t.map(\.id) == ["km", "steps", "rhr", "hrv", "sleep", "load"])
        #expect(t.allSatisfy { $0.weeks.count == 12 })
        #expect(t[5].label == "Training load, 7-day" && t[1].delta.contains("goal"))
        let plain = Coach.trainingTiles(DemoData.make(today: gToday, garmin: false), today: gToday)
        #expect(plain[5].label == "Exercise, 7-day" && plain[1].delta == "")
        let h = Coach.healthTiles(data, today: gToday)
        #expect(h.map(\.id) == ["stress", "bb", "kcal"])
        #expect(Coach.healthTiles(DemoData.make(today: gToday, garmin: false), today: gToday).map(\.id) == ["kcal"])
        let sw = Coach.sportWeeks(data, today: gToday)
        #expect(Set(sw.map(\.monday)).count == 12 && sw.contains { $0.sport == .run && $0.load > 0 })
        #expect(Coach.exerciseWeeks(data, today: gToday).count == 12)
        #expect(Coach.zones(data, today: gToday)?.count == 5)
        #expect(Coach.zones(HealthData(), today: gToday) == nil)
        let big = Coach.biggest(data)
        #expect(big.count == 5 && big[0].km >= big[4].km)
        let v = Coach.dayView(data, day: gToday)
        #expect(v.detail != nil && v.summary?.bbHigh != nil && !v.workouts.isEmpty && v.weekMinutes > 0)
        #expect(Coach.delta(nil, 1, upGood: true, word: "x") { "\($0)" } == ("", nil))
        #expect(Coach.delta(1, 1, upGood: true, word: "x") { "\($0)" }.0 == "level with x")
    }

    @Test func bestsAndSleepWithGarmin() {
        let r = Coach.records(data, today: gToday)
        let ids = Set(r.bests.map(\.id))
        #expect(ids.isSuperset(of: ["run_1k", "climb", "load", "im_week", "sleep_score"]))
        #expect(r.bests.first { $0.id == "run_1k" }?.note == "fastest split")
        let s = Coach.sleepInsights(data, settings: UserSettings(), today: gToday)
        #expect(s.stress != nil && s.score != nil && s.tips.contains { $0.contains("Overnight stress") })
        let snap = Coach.snapshot(data, settings: UserSettings(), today: gToday)
        #expect(snap.stats.bodyBattery != nil && snap.trends.stress.count == 7)
    }

    @Test func cacheRoundTrip() throws {
        var c = GarminCache()
        c.days["2026-11-01"] = DaySummary(day: Day("2026-11-01"), steps: 1)
        c.hrv["2026-11-02"] = ["avg": "40", "status": "LOW"]
        c.dayDetails["2026-11-01"] = DayDetail(day: Day("2026-11-01"), hr: [[1, 60]])
        let back = try JSONDecoder().decode(GarminCache.self, from: try JSONEncoder().encode(c))
        #expect(back == c)
        #expect(back.data.day(Day("2026-11-02"))?.hrvStatus == "LOW" && back.data.dayDetails[Day("2026-11-01")] != nil)
    }
}
