import FitnessCore
import SwiftUI
import WidgetKit

@main
struct FitnessWidgets: WidgetBundle {
    var body: some Widget {
        TodayCallWidget()
        MetricWidget()
        WeeklyGoalWidget()
        PlanWidget()
        SleepWidget()
        OverviewWidget()
        MilestoneWidget()
        LastWorkoutWidget()
    }
}

// MARK: - Shared pieces

/// Shown before the app has saved anything
struct SetUpView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "figure.run.circle")
            Text("Open Fitness Coach to set up").font(.caption).multilineTextAlignment(.center)
        }
    }
}

struct Small: View {
    var info: MetricInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(info.title, systemImage: info.symbol).font(.caption.weight(.semibold)).foregroundStyle(info.color).lineLimit(1)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(info.value).font(.title.bold()).minimumScaleFactor(0.5).lineLimit(1)
                Text(info.unit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if !info.note.isEmpty { Text(info.note).font(.caption2).foregroundStyle(.secondary) }
            if let v = info.values { MiniBars(values: v, color: info.color).frame(height: 24) }
            else if let p = info.progress { ProgressView(value: p).tint(info.color) }
        }
    }
}

extension View {
    func widgetCard(_ url: String) -> some View {
        containerBackground(.fill.tertiary, for: .widget).widgetURL(URL(string: "fitnesscoach://\(url)"))
    }
}

// MARK: - 1. Today's call

struct TodayCallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayCall", provider: Provider()) { e in TodayCallView(entry: e).widgetCard("today") }
            .configurationDisplayName("Today's call")
            .description("Train, take it easy or rest, from your HRV, sleep, resting heart rate and training load.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayCallView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let s = entry.snapshot {
            let r = s.readiness
            switch family {
            case .accessoryInline:
                Label(r.level.map { "\($0.short) today" } ?? "Needs data", systemImage: Theme.symbol(r.level))
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: Theme.symbol(r.level)).font(.title3)
                    Text(r.level?.short ?? "–").font(.caption2.bold())
                }
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Label(r.title, systemImage: Theme.symbol(r.level)).font(.headline).lineLimit(1)
                    Text(r.signals.filter { $0.state != .none }.map { "\($0.label) \($0.value ?? "")" }.joined(separator: " · "))
                        .font(.caption2).lineLimit(2)
                }
            case .systemMedium:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: Theme.symbol(r.level)).font(.title).foregroundStyle(Theme.color(r.level))
                        Text(r.title).font(.headline)
                        Text(r.advice).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(r.signals) { sig in
                            HStack(spacing: 4) {
                                StateIcon(state: sig.state).font(.caption)
                                Text(sig.label).font(.caption2)
                                Spacer(minLength: 0)
                                Text(sig.value ?? "–").font(.caption2.bold())
                            }
                        }
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S CALL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Image(systemName: Theme.symbol(r.level)).font(.largeTitle).foregroundStyle(Theme.color(r.level))
                    Spacer(minLength: 0)
                    Text(r.title).font(.headline).minimumScaleFactor(0.7).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else { SetUpView() }
    }
}

// MARK: - 2. Any single metric (configurable)

struct MetricWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Metric", intent: MetricIntent.self, provider: MetricProvider()) { e in
            MetricView(entry: e).widgetCard("health")
        }
        .configurationDisplayName("Metric")
        .description("Any single number: steps, exercise, calories, resting HR, HRV, sleep, goal, streak, milestone and more.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct MetricView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let s = entry.snapshot {
            let info = MetricInfo.make(entry.metric, s)
            switch family {
            case .accessoryInline:
                Label("\(info.title) \(info.value) \(info.unit)", systemImage: info.symbol)
            case .accessoryCircular:
                if let p = info.progress {
                    Gauge(value: p) { Image(systemName: info.symbol) } currentValueLabel: { Text(info.value).minimumScaleFactor(0.5) }
                        .gaugeStyle(.accessoryCircularCapacity)
                } else {
                    VStack(spacing: 0) {
                        Image(systemName: info.symbol).font(.caption)
                        Text(info.value).font(.headline).minimumScaleFactor(0.5)
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label(info.title, systemImage: info.symbol).font(.caption.bold())
                    Text("\(info.value) \(info.unit)").font(.headline)
                    if let v = info.values { MiniBars(values: v, color: .primary).frame(height: 12) } else { Text(info.note).font(.caption2) }
                }
            default:
                Small(info: info)
            }
        } else { SetUpView() }
    }
}

// MARK: - 3. Weekly goal

struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeeklyGoal", provider: Provider()) { e in WeeklyGoalView(entry: e).widgetCard("training") }
            .configurationDisplayName("Weekly goal")
            .description("Progress on your weekly goal, and your streak.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct WeeklyGoalView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let g = entry.snapshot?.goal {
            switch family {
            case .accessoryCircular:
                Gauge(value: g.progress) { Image(systemName: "target") } currentValueLabel: { Text(WeeklyGoal.text(g.value, g.type)) }
                    .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly goal").font(.caption.bold())
                    Text(g.summary).font(.headline).minimumScaleFactor(0.7)
                    Gauge(value: g.progress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                }
            default:
                VStack(spacing: 6) {
                    Ring(progress: g.progress, color: g.reached ? Theme.good : Theme.accent, lineWidth: 9) {
                        VStack(spacing: 0) {
                            Text(WeeklyGoal.text(g.value, g.type)).font(.title2.bold()).minimumScaleFactor(0.6)
                            Text("of \(WeeklyGoal.text(g.target, g.type)) \(g.type.unit)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    Text(g.streak > 0 ? "\(g.streak)-week streak" : g.reached ? "Goal reached" : "\(g.daysLeft) days left")
                        .font(.caption2.weight(.semibold))
                }
            }
        } else { SetUpView() }
    }
}

// MARK: - 4. This week's plan

struct PlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Plan", provider: Provider()) { e in PlanView(entry: e).widgetCard("training") }
            .configurationDisplayName("Training plan")
            .description("This week's runs toward your next milestone, ticked off as you go.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PlanView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let s = entry.snapshot, let r = s.race {
            // The day-by-day race plan: countdown and this week's days
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(r.goal) plan").font(.headline)
                    Spacer()
                    Text(r.daysToGo == 0 ? "Race day!" : "\(r.daysToGo) days to go").font(.caption.bold()).foregroundStyle(Theme.accent)
                }
                if let t = r.today { Label("Today: \(t.title)", systemImage: t.kind.symbol).font(.caption.bold()) }
                ForEach(r.week.filter { $0.kind != .rest }.prefix(family == .systemLarge ? 7 : 3)) { d in
                    HStack {
                        Image(systemName: r.status[d.day.iso] == .done ? "checkmark.circle.fill" : r.status[d.day.iso] == .missed ? "xmark.circle" : "circle")
                            .foregroundStyle(r.status[d.day.iso] == .done ? Theme.good : r.status[d.day.iso] == .missed ? Theme.bad : .secondary)
                        Text(d.day.text(.weekday)).bold()
                        Text(d.kind.label)
                        Spacer()
                        if d.km > 0 { Text("\(Fmt.km(d.km)) km").foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
                if family == .systemLarge {
                    Divider()
                    Text("\(r.done) of \(r.planned) planned runs done so far · race on \(r.raceDate.text(.short))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        } else if let s = entry.snapshot {
            let p = s.plan
            VStack(alignment: .leading, spacing: 6) {
                Text("Road to \(p.target)").font(.headline)
                if let i = p.week.intervals { Text(i).font(.caption2).foregroundStyle(.secondary) }
                ForEach(p.sessions) { x in
                    HStack {
                        Image(systemName: x.done ? "checkmark.circle.fill" : "circle").foregroundStyle(x.done ? Theme.good : .secondary)
                        Text(x.day).bold()
                        Text(x.kind)
                        Spacer()
                        Text("\(Fmt.km(x.km)) km").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Text("Done: \(p.week.doneRuns) run\(p.week.doneRuns == 1 ? "" : "s") · \(Fmt.km(p.week.doneKm)) km this week")
                    .font(.caption2).foregroundStyle(.secondary)
                if family == .systemLarge {
                    Divider()
                    Text("Coming up").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(p.ahead, id: \.monday) { a in
                        HStack { Text(a.monday.text(.short)); Spacer(); Text("long \(Fmt.km(a.longKm)) km\(a.easier ? " · easier" : "")") }
                            .font(.caption2)
                    }
                    Divider()
                    let m = s.milestones
                    HStack(spacing: 4) {
                        ForEach(m.steps) { st in
                            Capsule().fill(st.reached != nil ? Theme.accent : Theme.accent.opacity(0.2)).frame(height: 6)
                        }
                    }
                    .accessibilityLabel("\(m.reachedCount) of \(m.steps.count) milestones reached")
                    Text(m.nextStep.map { "Next: \($0.label)" + (m.toGoKm.map { ", \(Fmt.km($0)) km to go" } ?? "") } ?? "Ladder complete")
                        .font(.caption.weight(.semibold))
                    Label(m.tip, systemImage: "flag.checkered").font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
        } else { SetUpView() }
    }
}

// MARK: - 5. Sleep

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Sleep", provider: Provider()) { e in SleepWidgetView(entry: e).widgetCard("health") }
            .configurationDisplayName("Sleep")
            .description("Last night, your week of sleep, sleep debt and your usual bedtime.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct SleepWidgetView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let s = entry.snapshot {
            let last = s.stats.sleepHours.map { Fmt.hm(hours: $0) } ?? "–"
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Sleep", systemImage: "bed.double").font(.caption.bold())
                    Text(last).font(.headline)
                    MiniBars(values: s.trends.sleepHours, color: .primary).frame(height: 12)
                }
            case .systemMedium:
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Sleep", systemImage: "bed.double").font(.caption.bold()).foregroundStyle(.indigo)
                        Text(last).font(.title2.bold())
                        Text("target \(Fmt.hm(hours: s.sleep.need))").font(.caption2).foregroundStyle(.secondary)
                        if let d = s.sleep.debtHours, d > 0 { Text("debt \(Fmt.hm(hours: d))").font(.caption2).foregroundStyle(Theme.warn) }
                        if let b = s.sleep.bedtime { Text("usual bedtime \(Fmt.timeOfNight(b))").font(.caption2).foregroundStyle(.secondary) }
                    }
                    MiniBars(values: s.trends.sleepHours, color: .indigo, target: s.sleep.need)
                }
            default:
                Small(info: MetricInfo.make(.sleep, s))
            }
        } else { SetUpView() }
    }
}

// MARK: - 6. Overview

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Overview", provider: Provider()) { e in OverviewView(entry: e).widgetCard("today") }
            .configurationDisplayName("Overview")
            .description("Today's call, your key numbers and your weekly goal at a glance.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct OverviewView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let s = entry.snapshot {
            let kinds: [MetricKind] = family == .systemLarge
                ? [.steps, .exercise, .activeEnergy, .restingHR, .hrv, .sleep]
                : [.steps, .exercise, .sleep]
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: Theme.symbol(s.readiness.level)).foregroundStyle(Theme.color(s.readiness.level))
                    Text(s.readiness.title).font(.headline).lineLimit(1)
                    Spacer()
                    Label("\(s.goal.streak)", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(Theme.warn)
                        .accessibilityLabel("\(s.goal.streak)-week streak")
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: kinds.count, by: 3)), id: \.self) { i in
                        GridRow {
                            ForEach(kinds[i..<min(i + 3, kinds.count)], id: \.self) { k in
                                let info = MetricInfo.make(k, s)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(info.title).font(.caption2).foregroundStyle(.secondary)
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(info.value).font(.subheadline.bold())
                                        Text(info.unit).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .minimumScaleFactor(0.6).lineLimit(1)
                                    if let v = info.values { MiniBars(values: v, color: info.color).frame(height: family == .systemLarge ? 18 : 14) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                if family == .systemLarge {
                    Divider()
                    Label(s.goal.summary + " this week", systemImage: "target").font(.caption)
                    Label(s.milestones.nextStep.map { "Next: \($0.label)" + (s.milestones.toGoKm.map { ", \(Fmt.km($0)) km to go" } ?? "") } ?? "Ladder complete",
                          systemImage: "flag.checkered").font(.caption)
                    if let w = s.lastWorkout {
                        Label("\(w.name) · \(w.day.text(.short))\(w.km > 0 ? " · \(Fmt.km(w.km)) km" : "")", systemImage: w.sport.symbol).font(.caption)
                    }
                    Divider()
                    Text("This week's runs · road to \(s.plan.target)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(s.plan.sessions) { x in
                            Label("\(x.day) \(Fmt.km(x.km))", systemImage: x.done ? "checkmark.circle.fill" : "circle")
                                .font(.caption2).foregroundStyle(x.done ? Theme.good : .secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        } else { SetUpView() }
    }
}

// MARK: - 7. Next milestone

struct MilestoneWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Milestone", provider: Provider()) { e in MilestoneView(entry: e).widgetCard("training") }
            .configurationDisplayName("Next milestone")
            .description("Your next step from first run to Ironman.")
            .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct MilestoneView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let m = entry.snapshot?.milestones {
            let title = m.nextStep.map { "Next: \($0.label)" } ?? "Ladder complete"
            let detail = m.toGoKm.map { "\(Fmt.km($0)) km to go" + (m.weeks.map { " · ~\($0) wk" } ?? "") } ?? "\(m.reachedCount) of \(m.steps.count) done"
            if family == .accessoryRectangular {
                VStack(alignment: .leading) {
                    Label(title, systemImage: "flag.checkered").font(.headline).lineLimit(1)
                    Text(detail).font(.caption)
                    Gauge(value: Double(m.reachedCount), in: 0...Double(m.steps.count)) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Milestones", systemImage: "flag.checkered").font(.caption.bold()).foregroundStyle(Theme.accent)
                    Spacer(minLength: 0)
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(m.reachedCount), total: Double(m.steps.count)).tint(Theme.accent)
                }
            }
        } else { SetUpView() }
    }
}

// MARK: - 8. Last workout

struct LastWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LastWorkout", provider: Provider()) { e in LastWorkoutView(entry: e).widgetCard("today") }
            .configurationDisplayName("Last workout")
            .description("Your latest workout and its key numbers.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LastWorkoutView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let s = entry.snapshot, let w = s.lastWorkout {
            let best = s.records.bests.filter { $0.workoutID == w.id }
            VStack(alignment: .leading, spacing: 4) {
                Label(w.name, systemImage: w.sport.symbol).font(.caption.bold()).foregroundStyle(Theme.sport(w.sport)).lineLimit(1)
                Text(w.day.text(.short)).font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(w.km > 0 ? "\(Fmt.km(w.km)) km" : Fmt.hm(hours: w.minutes / 60)).font(.title2.bold())
                HStack(spacing: 10) {
                    if w.km > 0 { Text(Fmt.hm(hours: w.minutes / 60)) }
                    if let hr = w.avgHR { Text("\(Int(hr)) bpm") }
                    if family == .systemMedium, w.sport == .run, let v = w.speed { Text("\(Fmt.pace(speed: v)) /km") }
                    if family == .systemMedium, let k = w.kcal { Text("\(Int(k)) kcal") }
                }
                .font(.caption2).foregroundStyle(.secondary)
                if !best.isEmpty { Label(best.count == 1 ? best[0].label : "\(best.count) personal bests", systemImage: "star.fill").font(.caption2).foregroundStyle(Theme.warn) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if entry.snapshot != nil {
            Text("No workouts yet").font(.caption)
        } else { SetUpView() }
    }
}
