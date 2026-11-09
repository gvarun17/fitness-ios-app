import Charts
import FitnessCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    /// 0 = today, 1 = yesterday ... up to 89
    @State private var back = 0
    static let historyDays = 90

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = model.snapshot {
                    let day = model.today.adding(-back)
                    let v = Coach.dayView(model.data, day: day)
                    VStack(alignment: .leading, spacing: 16) {
                        DayHeader(day: day, back: $back, synced: back == 0 ? v.summary?.syncedAt : nil)
                        if s.isDemo { DemoBanner() }
                        if back == 0 { ReadinessCard(r: s.readiness) }
                        if back == 0, let r = s.race, let t = r.today {
                            Card {
                                Text("TODAY'S PLAN · \(r.goal.uppercased()) IN \(r.daysToGo) DAYS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                Label(t.title, systemImage: t.kind.symbol).font(.headline)
                                if !t.detail.isEmpty { Text(t.detail).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        DayMetrics(v: v, today: back == 0)
                        DayCharts(v: v, today: back == 0)
                        if back == 0, !s.newBests.isEmpty { NewBestsCard(bests: s.newBests) }
                        WorkoutsCard(workouts: v.workouts, bests: s.records.bests, today: back == 0)
                    }
                    .padding()
                } else {
                    ContentUnavailableView("No data yet", systemImage: "heart.text.square",
                                           description: Text("Pull to refresh once Apple Health or Garmin has some data."))
                }
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await model.refresh(forceGarmin: true) }
            .navigationTitle(model.settings.name.isEmpty ? "Today" : "Hi, \(model.settings.name)")
        }
    }
}

/// The date with ‹ Today › to step back through the last 90 days
struct DayHeader: View {
    var day: Day
    @Binding var back: Int
    var synced: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(back == 0 ? "TODAY" : back == 1 ? "YESTERDAY" : "\(back) DAYS AGO")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(day.text(.long)).font(.headline)
                if let synced { Text("Watch last synced \(synced)").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            HStack(spacing: 6) {
                Button { back += 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(back >= TodayView.historyDays - 1).accessibilityLabel("Previous day")
                Button("Today") { back = 0 }.disabled(back == 0)
                Button { back -= 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(back == 0).accessibilityLabel("Next day")
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Demo data. Connect Apple Health or Garmin in Settings to see yours.", systemImage: "info.circle")
            .font(.footnote).foregroundStyle(.secondary)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ReadinessCard: View {
    var r: Readiness
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: Theme.symbol(r.level)).font(.system(size: 36)).foregroundStyle(Theme.color(r.level))
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S CALL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(r.title).font(.title3.bold())
                    Text(r.advice).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(r.signals) { sig in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) { StateIcon(state: sig.state); Text(sig.label).font(.caption.weight(.semibold)) }
                        Text(sig.value ?? "–").font(.headline)
                        Text(sig.note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("A guide from your watch data, not medical advice.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Everything known about one day, as in the web dashboard's Today panel
struct DayMetrics: View {
    var v: DayView
    var today: Bool

    struct Cell: Identifiable {
        var id: String { label }
        var label: String
        var value: String
        var sub: String
        var progress: Double? = nil
        var mix: [(Double, Color)]? = nil
    }

    var cells: [Cell] {
        let d = v.summary, n = v.night
        var c: [Cell] = []
        if let st = d?.steps {
            c.append(Cell(label: "Steps", value: Fmt.number(Double(st)), sub: d?.stepsGoal.map { "goal \(Fmt.number(Double($0)))" } ?? "",
                          progress: d?.stepsGoal.map { Double(st) / Double($0) }))
        }
        if let ex = d?.exerciseMinutes {
            let parts = (d?.moderateMinutes).map { "\(Int($0)) mod · \(Int(d?.vigorousMinutes ?? 0)) vig ×2" } ?? "this week \(Int(v.weekMinutes))"
            c.append(Cell(label: "Exercise", value: "\(Int(ex)) min", sub: parts, progress: v.weekMinutes / 150))
        }
        if let k = d?.activeKcal { c.append(Cell(label: "Calories", value: "\(Int(k)) active", sub: d?.totalKcal.map { "\(Int($0)) total" } ?? "")) }
        if let r = d?.restingHR { c.append(Cell(label: "Resting HR", value: "\(Int(r)) bpm", sub: d?.restingHR7.map { "7-day avg \(Int($0))" } ?? "")) }
        if let lo = d?.minHR, let hi = d?.maxHR { c.append(Cell(label: "Heart rate range", value: "\(Int(lo))–\(Int(hi))", sub: "bpm, low – high")) }
        if let bb = d?.bbLatest ?? d?.bbHigh {
            c.append(Cell(label: "Body Battery", value: "\(Int(bb)) \(today ? "now" : "at day end")",
                          sub: d?.bbCharged.map { "+\(Int($0)) / −\(Int(d?.bbDrained ?? 0))" } ?? "", progress: bb / 100))
        }
        if let st = d?.stressAvg {
            let mix = d?.stressMix ?? []
            let calm = mix.count == 4 ? Int(((mix[0] + mix[1]) / max(mix.reduce(0, +), 0.01) * 100).rounded()) : nil
            c.append(Cell(label: "Stress", value: "\(Int(st)) avg", sub: (calm.map { "\($0)% calm · " } ?? "") + "peak \(d?.stressMax.map { "\(Int($0))" } ?? "–")",
                          mix: mix.count == 4 ? zip(mix, [Color.blue, .cyan, .orange, .red]).map { ($0, $1) } : nil))
        }
        let night = today ? "last night" : "night before"
        if let n {
            c.append(Cell(label: "Sleep \(night)", value: Fmt.hm(hours: n.asleepHours), sub: n.score.map { "score \(Int($0))" } ?? "",
                          mix: [(n.deep, Color.blue), (n.rem, Color.orange), (n.core, Color.green), (n.awake, Color.yellow)]))
        }
        if let h = d?.hrv {
            let st = d?.hrvStatus.flatMap { $0 == "NONE" ? nil : $0.lowercased() }
            c.append(Cell(label: "HRV \(night)", value: "\(Int(h)) ms", sub: st ?? d?.hrvWeekly.map { "7-day avg \(Int($0))" } ?? ""))
        }
        if let r = d?.respiration { c.append(Cell(label: "Breathing", value: "\(Int(r)) brpm", sub: "average")) }
        if let f = d?.floors {
            c.append(Cell(label: "Floors climbed", value: "\(Int(f))", sub: d?.floorsGoal.map { "goal \(Int($0))" } ?? "",
                          progress: d?.floorsGoal.map { f / $0 }))
        }
        return c
    }

    var body: some View {
        if cells.isEmpty {
            Card { Text("No data for this day.").font(.subheadline).foregroundStyle(.secondary) }
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(cells) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        Text(c.value).font(.subheadline.bold()).minimumScaleFactor(0.6).lineLimit(1)
                        if !c.sub.isEmpty { Text(c.sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
                        if let p = c.progress {
                            ProgressView(value: min(max(p, 0), 1)).tint(p >= 1 ? Theme.good : Theme.accent)
                        } else if let mix = c.mix {
                            GeometryReader { g in
                                let total = max(mix.map(\.0).reduce(0, +), 0.001)
                                HStack(spacing: 1) {
                                    ForEach(mix.indices, id: \.self) { i in
                                        mix[i].1.frame(width: max(0, g.size.width * mix[i].0 / total - 1))
                                    }
                                }
                                .clipShape(Capsule())
                            }
                            .frame(height: 4)
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Heart rate and Body Battery through the day (Garmin, last 7 days)
struct DayCharts: View {
    var v: DayView
    var today: Bool

    var body: some View {
        if let d = v.detail, !d.hr.isEmpty || !d.bb.isEmpty {
            Card {
                Text("Heart rate through the day").font(.headline)
                dayChart(d.hr, color: Theme.bad, unit: "bpm")
                Text("Body Battery").font(.headline).padding(.top, 6)
                dayChart(d.bb, color: Theme.accent, unit: "", step: true, domain: 0...100)
                if !v.workouts.isEmpty {
                    Text("Shaded: your workouts").font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else if v.summary?.bbHigh != nil {
            Card { Text("Graphs through the day are kept for the last 7 days.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    func minuteOfDay(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return Double(c.hour! * 60 + c.minute!)
    }

    @ViewBuilder func dayChart(_ pts: [[Double]], color: Color, unit: String, step: Bool = false, domain: ClosedRange<Double>? = nil) -> some View {
        if pts.isEmpty {
            Text("No data for this day.").font(.caption).foregroundStyle(.secondary)
        } else {
            let end = today ? max(60, ((pts.last?[0] ?? 60) / 60).rounded(.up) * 60) : 1440
            let lo = domain?.lowerBound ?? ((pts.map { $0[1] }.min() ?? 0) - 5)
            let hi = domain?.upperBound ?? ((pts.map { $0[1] }.max() ?? 100) + 5)
            Chart {
                ForEach(v.workouts) { w in
                    let s = minuteOfDay(w.start)
                    RectangleMark(xStart: .value("Start", s), xEnd: .value("End", s + w.minutes))
                        .foregroundStyle(Color.primary.opacity(0.08))
                }
                ForEach(pts.indices, id: \.self) { i in
                    LineMark(x: .value("Time", pts[i][0]), y: .value(unit, pts[i][1]))
                        .foregroundStyle(color).interpolationMethod(step ? .stepEnd : .linear)
                }
            }
            .chartXScale(domain: 0...end)
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                AxisMarks(values: Array(stride(from: 0, through: end, by: end > 720 ? 360 : 180))) { v in
                    AxisGridLine()
                    AxisValueLabel { if let m = v.as(Double.self) { Text(String(format: "%02d:00", Int(m) / 60 % 24)) } }
                }
            }
            .frame(height: 140)
        }
    }
}

struct NewBestsCard: View {
    var bests: [Best]
    var body: some View {
        Card {
            Label("New personal bests this week", systemImage: "star.fill").font(.headline).foregroundStyle(Theme.warn)
            ForEach(bests) { b in
                HStack { Text(b.label); Spacer(); Text(b.text).bold() }.font(.subheadline)
            }
        }
    }
}

struct WorkoutsCard: View {
    var workouts: [Workout]
    var bests: [Best]
    var today = true
    var body: some View {
        Card {
            Text(today ? "Today's workouts" : "Workouts").font(.headline)
            if workouts.isEmpty {
                Text(today ? "No workouts yet today. They show up here after your watch syncs."
                           : "No workouts on this day.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Tap one to see its stats and graphs.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(workouts) { w in
                NavigationLink { WorkoutDetailView(w: w, bests: bests.filter { $0.workoutID == w.id }) } label: {
                    WorkoutRow(w: w, best: bests.contains { $0.workoutID == w.id })
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct WorkoutRow: View {
    var w: Workout
    var best = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: w.sport.symbol).foregroundStyle(Theme.sport(w.sport)).frame(width: 28)
            VStack(alignment: .leading) {
                Text(w.name).font(.subheadline.weight(.semibold))
                Text("\(w.start.formatted(date: .omitted, time: .shortened))\(w.km > 0 ? " · \(Fmt.km(w.km)) km" : "") · \(Fmt.hm(hours: w.minutes / 60))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if best { Image(systemName: "star.fill").foregroundStyle(Theme.warn).accessibilityLabel("personal best") }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// One workout: key stats, zones, run/walk split and synced graphs
struct WorkoutDetailView: View {
    @EnvironmentObject var model: AppModel
    var w: Workout
    var bests: [Best]
    @State private var detail: WorkoutDetail?
    @State private var loaded = false

    var onFoot: Bool { [.run, .walk, .hike].contains(w.sport) }
    static let zoneColors: [Color] = [Color(red: 0.11, green: 0.36, blue: 0.67), Color(red: 0.16, green: 0.47, blue: 0.84),
                                      Color(red: 0.33, green: 0.60, blue: 0.91), Color(red: 0.53, green: 0.71, blue: 0.94),
                                      Color(red: 0.72, green: 0.83, blue: 0.96)]

    var stats: [(String, String)] {
        let s: [(String, String?)] = [
            ("Distance", w.km > 0 ? "\(Fmt.km(w.km)) km" : nil),
            ("Time", Fmt.hm(hours: w.minutes / 60)),
            (onFoot ? "Avg pace" : "Avg speed", w.speed.map { onFoot ? "\(Fmt.pace(speed: $0)) /km" : String(format: "%.1f km/h", $0 * 3.6) }),
            ("Heart rate", w.avgHR.map { "\(Int($0)) avg" + (w.maxHR.map { " · max \(Int($0))" } ?? "") }),
            ("Calories", w.kcal.map { "\(Int($0)) kcal" }),
            ("Training load", w.load.map { "\(Int($0))" }),
            ("Aerobic effect", w.aerobicTE.map { String(format: "%.1f / 5", $0) }),
            ("Cadence", w.cadence.map { "\(Int($0)) spm" }),
            ("Stride", w.strideM.map { String(format: "%.2f m", $0) }),
            ("Elevation gain", w.elevationM.map { "\(Int($0)) m" }),
        ]
        return s.compactMap { p in p.1.map { (p.0, $0) } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(w.typeName ?? w.sport.name.lowercased()).font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    Text(w.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                Card {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(stats, id: \.0) { s in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.0).font(.caption2).foregroundStyle(.secondary)
                                Text(s.1).font(.subheadline.bold())
                            }
                        }
                    }
                }
                if !bests.isEmpty {
                    Card { ForEach(bests) { b in Label("\(b.label): \(b.text)", systemImage: "star.fill").foregroundStyle(Theme.warn) } }
                }
                if let z = w.zones, z.reduce(0, +) > 0 {
                    Card {
                        Text("Time in heart rate zones").font(.headline)
                        SegmentBar(parts: z.enumerated().map { (Self.zoneColors[$0.offset], $0.element) })
                        HStack(spacing: 8) {
                            ForEach(z.indices, id: \.self) { i in
                                if z[i] > 0 {
Label("Z\(i + 1) \(Fmt.hm(hours: z[i] / 60))", systemImage: "circle.fill").font(.caption2)
                                        .labelStyle(DotLabel(color: Self.zoneColors[i]))
                                }
                            }
                        }
                    }
                }
                if let d = detail, let run = d.runMin, let walk = d.walkMin {
                    Card {
                        Text("Run, walk and stand").font(.headline)
                        SegmentBar(parts: [(Theme.run, run), (Theme.accent, walk), (.gray, d.standMin ?? 0)])
                        Text("Running \(Fmt.hm(hours: run / 60)) · walking \(Fmt.hm(hours: walk / 60))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let d = detail, !d.isEmpty {
                    WorkoutCharts(d: d, onFoot: onFoot)
                } else if loaded {
                    Card {
                        Text(w.isGarmin ? "Garmin has no detailed graphs for this workout yet."
                                        : "Detailed graphs come from Garmin. Connect Garmin in Settings to see them.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(w.name)
        .task {
            detail = await model.detail(for: w)
            loaded = true
        }
    }
}

struct SegmentBar: View {
    var parts: [(Color, Double)]
    var body: some View {
        GeometryReader { g in
            let total = max(parts.map(\.1).reduce(0, +), 0.001)
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { i in
                    if parts[i].1 > 0 {
                        RoundedRectangle(cornerRadius: 4).fill(parts[i].0)
                            .frame(width: max(2, g.size.width * parts[i].1 / total - 2))
                            .overlay(Text(parts[i].1 / total >= 0.12 ? "\(Int((parts[i].1 / total * 100).rounded()))%" : "")
                                .font(.caption2.bold()).foregroundStyle(.white))
                    }
                }
            }
        }
        .frame(height: 26)
    }
}

/// Second-by-second graphs, each with its own scale
struct WorkoutCharts: View {
    var d: WorkoutDetail
    var onFoot: Bool

    struct Series: Identifiable {
        var id: String { name }
        var name: String
        var unit: String
        var color: Color
        var values: [Double?]
        var invert = false
    }

    static func smooth(_ a: [Double?], _ k: Int) -> [Double?] {
        a.indices.map { i in
            let w = a[max(0, i - k)...min(a.count - 1, i + k)].compactMap { $0 }
            return w.isEmpty ? nil : w.reduce(0, +) / Double(w.count)
        }
    }

    var series: [Series] {
        let moving = d.speed.map { v -> Double? in v.flatMap { $0 > (onFoot ? 0.8 : 0.3) ? $0 : nil } }
        var out = [Series(name: "Heart rate", unit: "bpm", color: Theme.bad, values: d.hr.map { $0.flatMap { $0 > 0 ? $0 : nil } })]
        if onFoot {
            out.append(Series(name: "Pace", unit: "min/km, faster is higher", color: Theme.accent,
                              values: Self.smooth(moving, 6).map { $0.map { 1000 / $0 / 60 } }, invert: true))
        } else {
            out.append(Series(name: "Speed", unit: "km/h", color: Theme.accent, values: Self.smooth(moving, 6).map { $0.map { $0 * 3.6 } }))
        }
        out.append(Series(name: "Cadence", unit: "steps/min", color: Theme.good, values: Self.smooth(d.cadence.map { $0.flatMap { $0 > 0 ? $0 : nil } }, 3)))
        out.append(Series(name: "Power", unit: "W", color: Theme.warn, values: Self.smooth(d.power.map { $0.flatMap { $0 > 0 ? $0 : nil } }, 3)))
        out.append(Series(name: "Elevation", unit: "m", color: Color(red: 0, green: 0.5, blue: 0), values: d.elevation))
        return out.filter { $0.values.compactMap { $0 }.count > 5 }
    }

    var body: some View {
        ForEach(series) { s in
            let vals = s.values.compactMap { $0 }.sorted()
            let lo = vals[Int(Double(vals.count - 1) * 0.02)], hi = max(vals[Int(Double(vals.count - 1) * 0.98)], lo + 1)
            Card {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.name).font(.headline)
                    Text(s.unit).font(.caption).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(d.t.indices, id: \.self) { i in
                        if i < s.values.count, let v = s.values[i] {
                            LineMark(x: .value("Minutes", d.t[i] / 60), y: .value(s.name, min(max(v, lo), hi)))
                                .foregroundStyle(s.color)
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: s.invert))   // pace: faster is higher
                .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let m = v.as(Double.self) { Text("\(Int(m))m") } } } }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel { if let y = v.as(Double.self) { Text(s.invert ? Fmt.clock(seconds: y * 60) : "\(Int(y))") } }
                    }
                }
                .frame(height: 130)
            }
        }
    }
}
