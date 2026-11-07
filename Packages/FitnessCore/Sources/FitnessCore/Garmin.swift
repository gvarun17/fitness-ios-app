import Foundation

// The Garmin Personal API, read-only, straight from the phone. Same endpoints,
// limits and workarounds as the web dashboard's garmin_api.py and pull.py.

public enum GarminError: Error, Equatable, LocalizedError {
    case refused(Int)
    case unreachable(String)
    case http(Int)
    case emptyToken

    public var errorDescription: String? {
        switch self {
        case .refused(let c): "Garmin refused the key (HTTP \(c)). It may be mistyped or expired: check it, or create a new one in Garmin Connect."
        case .unreachable(let why): "Could not reach Garmin: \(why)"
        case .http(let c): "Garmin returned HTTP \(c)."
        case .emptyToken: "Garmin returned an empty token."
        }
    }
}

/// Sends one request. URLSession in the app; a fake in tests.
public protocol GarminTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: GarminTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, resp) = try await URLSession.shared.data(for: request)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public actor GarminClient {
    public static let base = URL(string: "https://personal.connectapi.garmin.com")!
    static let tokenPath = "/personalapitoken-service/personal-api/personal-api-key/token"
    static let tokenMaxAge: TimeInterval = 20 * 3600       // tokens last 24 hours

    let key: String
    let transport: GarminTransport
    let pause: @Sendable (Double) async -> Void
    var token: (value: String, at: Date)?

    public init(key: String, transport: GarminTransport = URLSessionTransport(),
                pause: @escaping @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }) {
        self.key = key
        self.transport = transport
        self.pause = pause
    }

    /// Swaps the key for a token: also how a key is checked before saving it.
    @discardableResult
    public func newToken() async throws -> String {
        var req = URLRequest(url: Self.base.appendingPathComponent(Self.tokenPath))
        req.httpMethod = "POST"
        req.setValue("ApiKey \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("fitness-coach-ios/1.0", forHTTPHeaderField: "User-Agent")
        let data: Data, code: Int
        do { (data, code) = try await transport.send(req) } catch { throw GarminError.unreachable(error.localizedDescription) }
        guard (200..<300).contains(code) else { throw GarminError.refused(code) }
        let t = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard !t.isEmpty else { throw GarminError.emptyToken }
        token = (t, Date())
        return t
    }

    func currentToken() async throws -> String {
        if let t = token, Date().timeIntervalSince(t.at) < Self.tokenMaxAge { return t.value }
        return try await newToken()
    }

    /// GET a path; returns parsed JSON or nil for an empty body. Renews the
    /// token once on 401 and retries when Garmin is busy (429, 502, 503).
    public func get(_ path: String, retries: Int = 4) async throws -> Any? {
        var renewed = false
        var attempt = 0
        while true {
            let tok = try await currentToken()
            var req = URLRequest(url: URL(string: Self.base.absoluteString + path)!)
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("fitness-coach-ios/1.0", forHTTPHeaderField: "User-Agent")
            let data: Data, code: Int
            do {
                (data, code) = try await transport.send(req)
            } catch {
                if attempt < retries { attempt += 1; await pause(3 * Double(attempt)); continue }
                throw GarminError.unreachable(error.localizedDescription)
            }
            if (200..<300).contains(code) {
                if data.isEmpty || String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
                return try? JSONSerialization.jsonObject(with: data)
            }
            if code == 401, !renewed { renewed = true; token = nil; continue }
            if [429, 502, 503].contains(code), attempt < retries { attempt += 1; await pause(3 * Double(attempt)); continue }
            throw GarminError.http(code)
        }
    }
}

// MARK: - Parsing Garmin's JSON into the app's models

typealias JSON = [String: Any]

func num(_ v: Any?) -> Double? {
    switch v {
    case let n as NSNumber where !(n === kCFBooleanTrue || n === kCFBooleanFalse): n.doubleValue
    case let d as Double: d
    case let i as Int: Double(i)
    default: nil
    }
}

func at(_ o: Any?, _ path: String...) -> Any? {
    var cur = o
    for k in path { cur = (cur as? JSON)?[k] }
    return cur
}

public enum GarminParse {
    /// Garmin's activity type -> the app's sports (same rules as the web dashboard)
    public static func sport(_ typeKey: String?) -> Sport {
        let k = (typeKey ?? "").lowercased()
        if k.contains("run") { return .run }
        if k.contains("walk") { return .walk }
        if ["cycl", "bik", "ride", "spin"].contains(where: k.contains) { return .cycle }
        if k.contains("swim") { return .swim }
        if k.contains("hik") { return .hike }
        if ["strength", "hiit", "fitness", "yoga", "pilates", "cardio"].contains(where: k.contains) { return .strength }
        return .other
    }

    public static func daily(_ v: Any) -> DaySummary? {
        guard let s = at(v, "calendarDate") as? String else { return nil }
        let steps = num(at(v, "movement", "steps", "value")), rhr = num(at(v, "heartRate", "restingValue"))
        let mod = num(at(v, "intensityMinutes", "moderate")), vig = num(at(v, "intensityMinutes", "vigorous"))
        guard steps != nil || rhr != nil || (mod ?? 0) + (vig ?? 0) > 0 else { return nil }   // watch off that day
        var d = DaySummary(day: Day(String(s.prefix(10))), steps: steps.map { Int($0) }, restingHR: rhr,
                           activeKcal: num(at(v, "calories", "burnedActive")),
                           exerciseMinutes: (mod != nil || vig != nil) ? (mod ?? 0) + 2 * (vig ?? 0) : nil)
        d.stepsGoal = num(at(v, "movement", "steps", "goal")).map { Int($0) }
        d.totalKcal = num(at(v, "calories", "burnedTotal"))
        d.minHR = num(at(v, "heartRate", "minValue")); d.maxHR = num(at(v, "heartRate", "maxValue"))
        d.moderateMinutes = mod; d.vigorousMinutes = vig
        if let st = num(at(v, "stress", "avgLevel")), st > 0 { d.stressAvg = st }
        d.stressMax = num(at(v, "stress", "maxLevel"))
        let mix = ["restProportion", "lowStressProportion", "mediumStressProportion", "highStressProportion"].map { num(at(v, "stress", $0)) ?? 0 }
        if mix.reduce(0, +) > 0 { d.stressMix = mix }
        d.bbHigh = num(at(v, "bodyBattery", "maxValue")); d.bbLow = num(at(v, "bodyBattery", "minValue"))
        d.bbLatest = num(at(v, "bodyBattery", "latestValue"))
        d.bbCharged = num(at(v, "bodyBattery", "chargedValue")); d.bbDrained = num(at(v, "bodyBattery", "drainedValue"))
        d.floors = num(at(v, "movement", "floorsAscended", "value")); d.floorsGoal = num(at(v, "movement", "floorsAscended", "goal"))
        d.respiration = num(at(v, "respiration", "avgValue"))
        if let end = at(v, "wellnessChronology", "endTimestampLocal") as? String, end.count >= 16 {
            d.syncedAt = String(end.dropFirst(11).prefix(5))
        }
        return d
    }

    /// Garmin's "local" timestamps are local clock time written as if UTC.
    static func afterSix(_ ms: Double?) -> Int? {
        guard let ms else { return nil }
        let minute = Int(ms / 60000) % 1440
        return (minute - 18 * 60 + 1440) % 1440
    }

    public static func sleep(_ v: Any) -> SleepNight? {
        guard let s = at(v, "calendarDate") as? String, let secs = num(at(v, "sleepTimeSeconds")), secs > 0 else { return nil }
        let h = { (k: String) in (num(at(v, k)) ?? 0) / 3600 }
        var n = SleepNight(day: Day(String(s.prefix(10))), asleepHours: secs / 3600, deep: h("deepSleepSeconds"),
                           rem: h("remSleepSeconds"), core: h("lightSleepSeconds"), awake: h("awakeSleepSeconds"),
                           bedtime: afterSix(num(at(v, "sleepStartTimestampLocal"))), wake: afterSix(num(at(v, "sleepEndTimestampLocal"))))
        n.score = num(at(v, "sleepScores", "overall", "value"))
        n.stressAvg = num(at(v, "avgSleepStress"))
        n.needHours = num(at(v, "sleepNeed", "actual")).map { $0 / 60 }
        return n
    }

    /// (day, last night's average, 7-day average, status)
    public static func hrv(_ v: Any) -> (Day, Double, Double?, String?)? {
        guard let s = at(v, "calendarDate") as? String, let avg = num(at(v, "lastNightAvg")) else { return nil }
        return (Day(String(s.prefix(10))), avg, num(at(v, "weeklyAvg")), at(v, "status") as? String)
    }

    static let localTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public static func activity(_ v: Any, timeZone: TimeZone = .current) -> Workout? {
        guard let id = num(at(v, "activityId")), let when = at(v, "startTimeLocal") as? String, when.count >= 10 else { return nil }
        let typeKey = at(v, "activityType", "typeKey") as? String
        let f = localTime.copy() as! DateFormatter
        f.timeZone = timeZone
        let start = f.date(from: String(when.prefix(19))) ?? Day(String(when.prefix(10))).date
        let sport = sport(typeKey)
        let type = (typeKey ?? "activity").replacingOccurrences(of: "_", with: " ")
        var w = Workout(id: "garmin-\(Int64(id))", day: Day(String(when.prefix(10))), start: start, sport: sport,
                        name: (at(v, "activityName") as? String) ?? type.capitalized,
                        km: (num(at(v, "distance")) ?? 0) / 1000, minutes: (num(at(v, "duration")) ?? 0) / 60,
                        avgHR: num(at(v, "averageHR")), maxHR: num(at(v, "maxHR")), kcal: num(at(v, "calories")),
                        cadence: num(at(v, "averageRunningCadenceInStepsPerMinute")),
                        strideM: num(at(v, "avgStrideLength")).flatMap { $0 > 0 ? $0 / 100 : nil })
        w.source = "garmin"
        w.typeName = type
        w.load = num(at(v, "activityTrainingLoad"))
        w.aerobicTE = num(at(v, "aerobicTrainingEffect"))
        w.anaerobicTE = num(at(v, "anaerobicTrainingEffect"))
        let z = (1...5).map { (num(at(v, "hrTimeInZone_\($0)")) ?? 0) / 60 }
        w.zones = z.reduce(0, +) > 0 ? z : nil
        w.elevationM = num(at(v, "elevationGain"))
        w.steps = num(at(v, "steps")).map { Int($0) }
        w.fastest1k = num(at(v, "fastestSplit_1000"))
        w.fastest5k = num(at(v, "fastestSplit_5000"))
        return w
    }

    /// The numeric Garmin ID back from a workout's ID
    public static func activityID(_ w: Workout) -> String? {
        w.id.hasPrefix("garmin-") ? String(w.id.dropFirst(7)) : nil
    }

    /// Per-second graphs from /details plus the run/walk/stand split from the summary
    public static func detail(_ raw: Any?, summary: Any?) -> WorkoutDetail {
        var d = WorkoutDetail()
        if let raw, let rows = at(raw, "activityDetailMetrics") as? [JSON], let desc = at(raw, "metricDescriptors") as? [JSON] {
            var idx: [String: Int] = [:]
            for m in desc { if let k = m["key"] as? String, let i = num(m["metricsIndex"]) { idx[k] = Int(i) } }
            let metrics = rows.map { ($0["metrics"] as? [Any]) ?? [] }
            func column(_ key: String) -> [Double?] {
                guard let i = idx[key] else { return [] }
                return metrics.map { i < $0.count ? num($0[i]) : nil }
            }
            let t = column("sumElapsedDuration")
            if t.contains(where: { $0 != nil }) {
                let keep = t.indices.filter { t[$0] != nil }
                func pick(_ c: [Double?]) -> [Double?] { c.isEmpty ? [] : keep.map { c[$0] } }
                d.t = keep.map { t[$0]! }
                d.hr = pick(column("directHeartRate")); d.speed = pick(column("directSpeed"))
                d.cadence = pick(column("directDoubleCadence")); d.elevation = pick(column("directElevation"))
                d.power = pick(column("directPower"))
            }
        }
        for s in (at(summary, "splitSummaries") as? [JSON]) ?? [] {
            let m = (num(s["duration"]) ?? 0) / 60
            switch s["splitType"] as? String {
            case "RWD_RUN": d.runMin = m
            case "RWD_WALK": d.walkMin = m
            case "RWD_STAND": d.standMin = m
            default: break
            }
        }
        return d
    }

    /// Heart rate through the day: [[GMT ms, bpm]] -> [[minutes after local midnight, bpm]]
    public static func dayHeartRate(_ v: Any?) -> (points: [[Double]], offsetMs: Double, rhr7: Double?) {
        guard let v else { return ([], 0, nil) }
        let parse = { (s: String) -> Date? in
            let f = localTime.copy() as! DateFormatter
            f.timeZone = TimeZone(identifier: "UTC")
            return f.date(from: String(s.replacingOccurrences(of: "T", with: " ").prefix(19)))
        }
        let local = (at(v, "startTimestampLocal") as? String).flatMap(parse)
        let gmt = (at(v, "startTimestampGMT") as? String).flatMap(parse)
        let off = (local != nil && gmt != nil) ? local!.timeIntervalSince(gmt!) * 1000 : 0
        var pts: [[Double]] = []
        if let start = local {
            for p in (at(v, "heartRateValues") as? [[Any]]) ?? [] {
                guard p.count >= 2, let ts = num(p[0]), let bpm = num(p[1]), bpm > 0 else { continue }
                let minute = ((ts + off) / 1000 - start.timeIntervalSince1970) / 60
                pts.append([(minute * 10).rounded() / 10, bpm])
            }
        }
        return (pts, off, num(at(v, "lastSevenDaysAvgRestingHeartRate")))
    }

    public static func dayBodyBattery(_ v: Any?, offsetMs: Double, midnightUTC: Date) -> [[Double]] {
        guard let first = (v as? [Any])?.first, let arr = at(first, "bodyBatteryValuesArray") as? [[Any]] else { return [] }
        return arr.compactMap { p in
            guard p.count >= 2, let ts = num(p[0]), let val = num(p[1]) else { return nil }
            return [(((ts + offsetMs) / 1000 - midnightUTC.timeIntervalSince1970) / 60 * 10).rounded() / 10, val]
        }
    }
}

// MARK: - Downloading

/// What's been downloaded from Garmin, kept on the phone between syncs.
public struct GarminCache: Codable, Sendable, Equatable {
    public var start: Day?
    public var through: Day?
    public var days: [String: DaySummary] = [:]
    public var nights: [String: SleepNight] = [:]
    public var hrv: [String: [String: String]] = [:]       // day -> avg, weekly, status
    public var workouts: [String: Workout] = [:]
    public var dayDetails: [String: DayDetail] = [:]
    public var workoutDetails: [String: WorkoutDetail] = [:]
    public var lastSync: Date?

    public init() {}

    /// As HealthData, with HRV merged into the days
    public var data: HealthData {
        var ds = days
        for (k, h) in hrv {
            var d = ds[k] ?? DaySummary(day: Day(k))
            d.hrv = h["avg"].flatMap(Double.init)
            d.hrvWeekly = h["weekly"].flatMap(Double.init)
            d.hrvStatus = h["status"]
            ds[k] = d
        }
        return HealthData(days: Array(ds.values), nights: Array(nights.values), workouts: Array(workouts.values),
                          dayDetails: Dictionary(uniqueKeysWithValues: dayDetails.map { (Day($0.key), $0.value) }),
                          workoutDetails: workoutDetails)
    }
}

public struct GarminSync {
    public static let refetchDays = 3        // the last few days, which Garmin may still be filling in
    public static let detailDays = 7         // graphs through the day are kept for a week
    public static let maxSkips = 5

    let client: GarminClient
    let pause: Double

    public init(client: GarminClient, pause: Double = 0.3) {
        self.client = client
        self.pause = pause
    }

    func breathe() async { if pause > 0 { try? await Task.sleep(nanoseconds: UInt64(pause * 1e9)) } }

    /// Downloads what's new since the last sync (a year of history the first time).
    public func run(_ cache: GarminCache, today: Day, history: Int = 365,
                    progress: @Sendable (String) -> Void = { _ in }) async throws -> GarminCache {
        var c = cache
        let start = c.start ?? today.adding(-history)
        let from = c.through.map { max($0.adding(-Self.refetchDays), start) } ?? start
        progress("Workouts")
        try await activities(&c, since: start, backfill: c.start == nil)
        progress("Daily summaries")
        try await ranges(from: from, to: today, chunk: 60, path: { "/usersummary-service/v2/dailysummaries?startDate=\($0)&endDate=\($1)" },
                         items: { at($0, "data") as? [Any] ?? [] }) { for i in $0 { if let d = GarminParse.daily(i) { c.days[d.day.iso] = d } } }
        progress("Sleep")
        try await ranges(from: from, to: today, chunk: 31, path: { "/sleep-service/sleep/dailySleepSummariesByDate?startDate=\($0)&endDate=\($1)" },
                         items: { $0 as? [Any] ?? [] }) { for i in $0 { if let n = GarminParse.sleep(i) { c.nights[n.day.iso] = n } } }
        progress("HRV")
        try await ranges(from: from, to: today, chunk: 365, path: { "/hrv-service/hrv/daily/\($0)/\($1)" },
                         items: { at($0, "hrvSummaries") as? [Any] ?? [] }) {
            for i in $0 {
                if let (d, avg, weekly, status) = GarminParse.hrv(i) {
                    c.hrv[d.iso] = ["avg": "\(avg)", "weekly": weekly.map { "\($0)" } ?? "", "status": status ?? ""].filter { !$0.value.isEmpty }
                }
            }
        }
        progress("Today")
        try await recentDays(&c, today: today)
        c.start = min(c.start ?? start, start)
        c.through = today
        c.lastSync = Date()
        return c
    }

    func activities(_ c: inout GarminCache, since start: Day, backfill: Bool) async throws {
        var page = 0, skipped = 0
        while true {
            var batch: [Any]?
            var used = 20
            for limit in [20, 10, 5, 1] {               // shrink the page if a response is too big
                used = limit
                do {
                    batch = try await client.get("/activitylist-service/activities/search/activities?start=\(page)&limit=\(limit)") as? [Any] ?? []
                    break
                } catch GarminError.http(500) { continue }
            }
            guard let batch else {
                skipped += 1
                if skipped >= Self.maxSkips { return }       // Garmin keeps failing: stop instead of looping forever
                page += 1
                continue
            }
            skipped = 0
            await breathe()
            var stop = false
            for a in batch {
                guard let w = GarminParse.activity(a) else { continue }
                if w.day < start { stop = true; break }
                if c.workouts[w.id] != nil, !backfill { stop = true; break }
                c.workouts[w.id] = w
            }
            page += batch.count
            if stop || batch.count < used { return }
        }
    }

    /// Fetches [from, to] in chunks, halving a chunk when Garmin says 500
    /// (its ~256 KB response limit) and skipping a day it can't return.
    func ranges(from: Day, to: Day, chunk: Int, path: (String, String) -> String,
                items: (Any?) -> [Any], store: ([Any]) -> Void) async throws {
        var cur = from, size = chunk
        while cur <= to {
            let end = min(cur.adding(size - 1), to)
            var resp: Any?
            do {
                resp = try await client.get(path(cur.iso, end.iso))
            } catch GarminError.http(let code) where [500, 404, 204].contains(code) {
                if code == 500, size > 1 { size = max(size / 2, 1); continue }
                resp = nil
            }
            await breathe()
            store(items(resp))
            cur = end.adding(1)
            size = chunk
        }
    }

    /// Heart rate and Body Battery through each of the last 7 days, plus full
    /// detail for those days' workouts. Past days are fetched once.
    func recentDays(_ c: inout GarminCache, today: Day) async throws {
        let keep = Set((0..<Self.detailDays).map { today.adding(-$0).iso })
        c.dayDetails = c.dayDetails.filter { keep.contains($0.key) }
        for back in 0..<Self.detailDays {
            let day = today.adding(-back)
            if back > 0, c.dayDetails[day.iso] != nil { continue }
            do {
                let hr = try await client.get("/wellness-service/wellness/dailyHeartRate?date=\(day.iso)")
                let parsed = GarminParse.dayHeartRate(hr)
                await breathe()
                let bb = try await client.get("/wellness-service/wellness/bodyBattery/reports/daily?startDate=\(day.iso)&endDate=\(day.iso)")
                await breathe()
                c.dayDetails[day.iso] = DayDetail(day: day, hr: parsed.points,
                                                  bb: GarminParse.dayBodyBattery(bb, offsetMs: parsed.offsetMs, midnightUTC: day.date))
                if let r7 = parsed.rhr7, var d = c.days[day.iso] { d.restingHR7 = r7; c.days[day.iso] = d }
            } catch GarminError.http { continue }        // try again next time
            for w in c.workouts.values where w.day == day && c.workoutDetails[w.id] == nil {
                if let d = try? await workoutDetail(w), !d.isEmpty { c.workoutDetails[w.id] = d }
            }
        }
    }

    /// Second-by-second graphs for one workout, asking for fewer points when
    /// the response would be too big.
    public func workoutDetail(_ w: Workout) async throws -> WorkoutDetail? {
        guard let id = GarminParse.activityID(w) else { return nil }
        var raw: Any?
        for size in [1000, 500, 250, 120] {
            do {
                raw = try await client.get("/activity-service/activity/\(id)/details?maxChartSize=\(size)&maxPolylineSize=0")
                break
            } catch GarminError.http(500) { continue }
        }
        await breathe()
        let summary = try? await client.get("/activity-service/activity/\(id)")
        await breathe()
        return GarminParse.detail(raw, summary: summary ?? nil)
    }
}
