import Charts
import FitnessCore
import SwiftUI

// The web dashboard's sections, for the Training and Health screens.

/// Two-column grid of tiles, each with a comparison and a 12-week sparkline
struct TilesGrid: View {
    var title: String
    var tiles: [Tile]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(tiles) { t in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(t.value).font(.title3.bold()).minimumScaleFactor(0.6).lineLimit(1)
                            Text(t.unit).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(t.delta.isEmpty ? " " : t.delta).font(.caption2).lineLimit(2)
                            .foregroundStyle(t.deltaGood == nil ? Color.secondary : t.deltaGood! ? Theme.good : Theme.bad)
                        Sparkline(values: t.weeks).frame(height: 26)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct Sparkline: View {
    var values: [Double?]
    var body: some View {
        let pts = values.enumerated().compactMap { i, v in v.map { (i, $0) } }
        if pts.count >= 2 {
            Chart {
                ForEach(pts, id: \.0) { p in
                    LineMark(x: .value("Week", p.0), y: .value("Value", p.1)).foregroundStyle(Color.gray)
                }
                if let last = pts.last {
                    PointMark(x: .value("Week", last.0), y: .value("Value", last.1)).foregroundStyle(Theme.accent)
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
        } else {
            Color.clear
        }
    }
}

/// Distance, time or sessions by sport for the last 12 weeks, plus this week vs the 4 before
struct SportWeeksCard: View {
    var weeks: [SportWeek]
    var today: Day
    @State private var measure = 0
    private let names = ["Distance", "Time", "Sessions"]

    func value(_ w: SportWeek) -> Double { [w.km, w.minutes / 60, Double(w.count)][measure] }

    var body: some View {
        Card {
            Text("\(names[measure]) by sport, last 12 weeks").font(.headline)
            Text("Am I doing more than I usually do?").font(.caption).foregroundStyle(.secondary)
            Picker("Measure", selection: $measure) { ForEach(names.indices, id: \.self) { Text(names[$0]).tag($0) } }
                .pickerStyle(.segmented)
            let shown = weeks.filter { measure != 0 || $0.km > 0 }
            if shown.isEmpty {
                Text("No workouts yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(shown, id: \.self.id) { w in
                    BarMark(x: .value("Week", w.monday.date, unit: .weekOfYear), y: .value(names[measure], value(w)))
                        .foregroundStyle(by: .value("Sport", w.sport.name))
                }
                .sportScale(shown)
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let y = v.as(Double.self) { Text(measure == 1 ? "\(Int(y))h" : "\(Int(y))") } } } }
                .frame(height: 190)
                table
            }
        }
    }

    var table: some View {
        let this = today.monday
        let cur = weeks.filter { $0.monday == this }
        let prev = weeks.filter { $0.monday >= this.adding(-28) && $0.monday < this }
        let sports = Sport.allCases.filter { s in weeks.contains { $0.sport == s && $0.monday >= this.adding(-28) } }
        return Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                Text("This wk"); Text("4-wk avg"); Text("km"); Text("avg")
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(sports, id: \.self) { s in
                let c = cur.filter { $0.sport == s }, p = prev.filter { $0.sport == s }
                GridRow {
                    Label(s.name, systemImage: "circle.fill").labelStyle(DotLabel(color: Theme.sport(s)))
                    Text("\(c.map(\.count).reduce(0, +))")
                    Text(String(format: "%.1f", Double(p.map(\.count).reduce(0, +)) / 4))
                    Text(Fmt.km(c.map(\.km).reduce(0, +)))
                    Text(Fmt.km(p.map(\.km).reduce(0, +) / 4))
                }
                .font(.caption)
            }
        }
    }
}

extension SportWeek {
    var id: String { monday.iso + sport.rawValue }
}

struct DotLabel: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 8, height: 8); configuration.title }
    }
}

/// Exercise minutes per week with the 150-minute line health guidelines recommend
struct ExerciseWeeksCard: View {
    var weeks: [(Day, Double)]
    var goal: Double
    var body: some View {
        Card {
            Text("Exercise minutes per week").font(.headline)
            Text("Am I hitting the \(Int(goal)) minutes a week that health guidelines recommend?").font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(weeks, id: \.0) { w in
                    BarMark(x: .value("Week", w.0.date, unit: .weekOfYear), y: .value("Minutes", w.1))
                        .foregroundStyle(w.1 >= goal ? Theme.good : Theme.accent)
                }
                RuleMark(y: .value("Goal", goal)).foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) { Text("\(Int(goal)) goal").font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(height: 160)
        }
    }
}

/// Garmin training load per week, by sport
struct LoadWeeksCard: View {
    var weeks: [SportWeek]
    var body: some View {
        let shown = weeks.filter { $0.load > 0 }
        if !shown.isEmpty {
            Card {
                Text("Training load per week").font(.headline)
                Text("How much is my training asking of my body?").font(.caption).foregroundStyle(.secondary)
                Chart(shown, id: \.id) { w in
                    BarMark(x: .value("Week", w.monday.date, unit: .weekOfYear), y: .value("Load", w.load))
                        .foregroundStyle(by: .value("Sport", w.sport.name))
                }
                .sportScale(shown)
                .frame(height: 170)
            }
        }
    }
}

/// Time in each heart rate zone over the last 4 weeks
struct ZonesCard: View {
    var zones: [Double]?
    var body: some View {
        if let z = zones, z.reduce(0, +) > 0 {
            let total = z.reduce(0, +)
            let easy = (z[0] + z[1]) / total
            Card {
                Text("How hard were the last 4 weeks?").font(.headline)
                Text("\(Int((easy * 100).rounded()))% of your time was easy (zones 1–2). Most of a beginner's training should be easy.")
                    .font(.caption).foregroundStyle(.secondary)
                SegmentBar(parts: z.enumerated().map { (WorkoutDetailView.zoneColors[$0.offset], $0.element) })
                HStack(spacing: 8) {
                    ForEach(z.indices, id: \.self) { i in
Label("Z\(i + 1) \(Fmt.hm(hours: z[i] / 60))", systemImage: "circle.fill").font(.caption2)
                                        .labelStyle(DotLabel(color: WorkoutDetailView.zoneColors[i]))
                    }
                }
            }
        }
    }
}

/// The five longest sessions
struct BiggestDaysCard: View {
    var workouts: [Workout]
    var body: some View {
        if !workouts.isEmpty {
            Card {
                Text("Biggest days").font(.headline)
                Text("Your five longest sessions.").font(.caption).foregroundStyle(.secondary)
                ForEach(workouts) { w in
                    NavigationLink { WorkoutDetailView(w: w, bests: []) } label: {
                        HStack {
                            Image(systemName: w.sport.symbol).foregroundStyle(Theme.sport(w.sport)).frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(w.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(w.day.text(.short) + (w.avgHR.map { " · \(Int($0)) bpm" } ?? "") + (w.load.map { " · load \(Int($0))" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(w.km > 0 ? "\(Fmt.km(w.km)) km" : Fmt.hm(hours: w.minutes / 60)).font(.subheadline.bold())
                                if w.km > 0, [.run, .walk, .hike].contains(w.sport), let v = w.speed {
                                    Text("\(Fmt.pace(speed: v)) /km").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Steps every day as a calendar heatmap (Monday at the top)
struct StepsHeatmap: View {
    var days: [DaySummary]
    var today: Day
    var weeks = 26
    static let bands: [(Int, Color)] = [(2500, Color(red: 0.09, green: 0.31, blue: 0.58)), (5000, Color(red: 0.15, green: 0.42, blue: 0.75)),
                                        (7500, Color(red: 0.22, green: 0.53, blue: 0.90)), (10000, Color(red: 0.43, green: 0.65, blue: 0.93)),
                                        (Int.max, Color(red: 0.72, green: 0.83, blue: 0.96))]

    static func color(_ steps: Int?) -> Color {
        guard let s = steps, s > 0 else { return Color(.tertiarySystemGroupedBackground) }
        return bands.first { s < $0.0 }!.1
    }

    var body: some View {
        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0.steps) })
        let first = today.monday.adding(-7 * (weeks - 1))
        Card {
            Text("Steps, every day").font(.headline)
            Text("How consistent have I been over the last 6 months?").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(0..<weeks, id: \.self) { c in
                    VStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { r in
                            let d = first.adding(c * 7 + r)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(d > today ? Color.clear : Self.color(byDay[d] ?? nil))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .accessibilityLabel("Steps each day for the last \(weeks) weeks")
            HStack(spacing: 4) {
                Text("Steps").font(.caption2).foregroundStyle(.secondary)
                ForEach(Array(["<2.5k", "<5k", "<7.5k", "<10k", "10k+"].enumerated()), id: \.offset) { i, l in
                    RoundedRectangle(cornerRadius: 2).fill(Self.bands[i].1).frame(width: 10, height: 10)
                    Text(l).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Sleep stages per night
struct SleepStagesCard: View {
    var nights: [SleepNight]
    var body: some View {
        if !nights.isEmpty {
            Card {
                Text("Sleep stages").font(.headline)
                Chart {
                    ForEach(nights, id: \.day) { n in
                        ForEach([("Deep", n.deep, Color.blue), ("REM", n.rem, Color.orange), ("Light", n.core, Color.green), ("Awake", n.awake, Color.yellow)], id: \.0) { s in
                            BarMark(x: .value("Night", n.day.date, unit: .day), y: .value("Hours", s.1))
                                .foregroundStyle(by: .value("Stage", s.0))
                        }
                    }
                }
                .chartForegroundStyleScale(["Deep": Color.blue, "REM": Color.orange, "Light": Color.green, "Awake": Color.yellow])
                .frame(height: 170)
            }
        }
    }
}

/// Body Battery: each day's highest and lowest
struct BodyBatteryCard: View {
    var days: [DaySummary]
    var body: some View {
        let shown = days.filter { $0.bbHigh != nil }
        if !shown.isEmpty {
            Card {
                Text("Body Battery").font(.headline)
                Text("How well do I recharge? Each day's highest and lowest.").font(.caption).foregroundStyle(.secondary)
                Chart {
                    ForEach(shown, id: \.day) { d in
                        LineMark(x: .value("Day", d.day.date, unit: .day), y: .value("Highest", d.bbHigh!), series: .value("S", "Highest"))
                            .foregroundStyle(Theme.accent)
                        if let lo = d.bbLow {
                            LineMark(x: .value("Day", d.day.date, unit: .day), y: .value("Lowest", lo), series: .value("S", "Lowest"))
                                .foregroundStyle(Color.gray)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 160)
                HStack(spacing: 12) {
                    Label("Highest", systemImage: "circle.fill").labelStyle(DotLabel(color: Theme.accent))
                    Label("Lowest", systemImage: "circle.fill").labelStyle(DotLabel(color: .gray))
                }
                .font(.caption2)
            }
        }
    }
}

/// Workouts other than running: hours per week by type, and the latest sessions
struct OtherWorkoutsCard: View {
    var weeks: [SportWeek]
    var workouts: [Workout]
    var body: some View {
        let other = weeks.filter { $0.sport != .run }
        let recent = Array(workouts.filter { $0.sport != .run }.suffix(8).reversed())
        Card {
            Text("Workouts other than running").font(.headline)
            Text("Where does my time go outside running? Hours per week.").font(.caption).foregroundStyle(.secondary)
            if other.isEmpty {
                Text("No workouts other than runs in the last 12 weeks.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(other, id: \.id) { w in
                    BarMark(x: .value("Week", w.monday.date, unit: .weekOfYear), y: .value("Hours", w.minutes / 60))
                        .foregroundStyle(by: .value("Sport", w.sport.name))
                }
                .sportScale(other)
                .frame(height: 160)
            }
            if !recent.isEmpty {
                Divider()
                Text("Recent workouts").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(recent) { w in
                    HStack {
                        Image(systemName: w.sport.symbol).foregroundStyle(Theme.sport(w.sport)).frame(width: 22)
                        Text(w.name).lineLimit(1)
                        Spacer()
                        Text(w.day.text(.short) + " · " + Fmt.hm(hours: w.minutes / 60) + (w.avgHR.map { " · \(Int($0)) bpm" } ?? ""))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

extension View {
    /// Fixed colour per sport, with only the sports in the chart in its legend
    func sportScale(_ weeks: [SportWeek]) -> some View {
        let used = Sport.allCases.filter { s in weeks.contains { $0.sport == s } }
        return chartForegroundStyleScale(domain: used.map(\.name), range: used.map(Theme.sport))
    }
}
