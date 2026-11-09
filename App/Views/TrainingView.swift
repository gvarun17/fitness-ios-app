import Charts
import FitnessCore
import SwiftUI

/// The Running screen: goal, plans (all editable), milestones and running stats
struct TrainingView: View {
    @EnvironmentObject var model: AppModel
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case goal, plan, race
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = model.snapshot {
                    VStack(alignment: .leading, spacing: 16) {
                        GoalCard(g: s.goal, edit: { sheet = .goal })
                        if let r = s.race {
                            RacePlanCard(r: r, rest: s.readiness.level == .rest)
                        } else {
                            PlanCard(p: s.plan, rest: s.readiness.level == .rest, edit: { sheet = .plan })
                            Button { sheet = .race } label: {
                                Label("Make a day-by-day plan for a race (5K to marathon)", systemImage: "calendar.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        MilestonesCard(m: s.milestones)
                        let data = model.data, today = model.today
                        let weeks = Coach.sportWeeks(data, today: today)
                        TilesGrid(title: "This week vs recent weeks", tiles: Coach.trainingTiles(data, today: today))
                        SportWeeksCard(weeks: weeks, today: today)
                        ExerciseWeeksCard(weeks: Coach.exerciseWeeks(data, today: today), goal: 150)
                        LoadWeeksCard(weeks: weeks)
                        ZonesCard(zones: Coach.zones(data, today: today))
                        FormCard(runs: data.workouts.filter { $0.sport == .run })
                        BestsCard(r: s.records)
                        BiggestDaysCard(workouts: Coach.biggest(data))
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await model.refresh(forceGarmin: true) }
            .navigationTitle("Running")
            .sheet(item: $sheet) { which in
                switch which {
                case .goal: GoalEditor()
                case .plan: PlanEditor()
                case .race: RaceEditor()
                }
            }
        }
    }
}

struct GoalCard: View {
    var g: WeeklyGoal
    var edit: () -> Void = {}
    var body: some View {
        Card {
            HStack {
                Text("THIS WEEK · \(g.type.label.uppercased())").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Edit", action: edit).font(.subheadline)
            }
            HStack(spacing: 18) {
                Ring(progress: g.progress, color: g.reached ? Theme.good : Theme.accent, lineWidth: 12) {
                    VStack(spacing: 0) {
                        Text(WeeklyGoal.text(g.value, g.type)).font(.title.bold())
                        Text("of \(WeeklyGoal.text(g.target, g.type)) \(g.type.unit)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    if g.reached {
                        Text("Goal reached this week. Nice work.").font(.subheadline.bold())
                    } else {
                        Text(g.type == .runs ? "\(Int(g.need)) more run\(g.need == 1 ? "" : "s")"
                                             : "\(WeeklyGoal.text(g.need, g.type)) \(g.type.unit) to go").font(.subheadline.bold())
                        Text("\(g.daysLeft) day\(g.daysLeft == 1 ? "" : "s") left").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(g.streak > 0 ? "\(g.streak)-week streak\(g.best > g.streak ? " (best \(g.best))" : "")" : "Hit it this week to start a streak")
                        .font(.subheadline)
                    if g.of > 0 { Text("Hit in \(g.hits) of the last \(g.of) weeks").font(.caption).foregroundStyle(.secondary) }
                    if g.suggested { Text("Suggested goal. Tap Edit to set your own.").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct PlanCard: View {
    var p: TrainingPlan
    var rest: Bool
    var edit: () -> Void = {}
    var body: some View {
        Card {
            HStack {
                Text("YOUR WEEKLY PLAN\(p.week.easier ? " · EASIER WEEK" : "")").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Edit", action: edit).font(.subheadline)
            }
            Text("Road to \(p.target) · \(p.perWeek) runs a week").font(.headline)
            Text(p.week.intervals.map { "\($0), for the distance below." } ?? "Easy runs at a pace where you can talk in full sentences.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(p.sessions) { x in
                HStack {
                    Image(systemName: x.done ? "checkmark.circle.fill" : "circle").foregroundStyle(x.done ? Theme.good : .secondary)
                        .accessibilityLabel(x.done ? "done" : "to do")
                    Text(x.day).bold()
                    Text(x.kind)
                    Spacer()
                    Text("\(Fmt.km(x.km)) km").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            if p.ready {
                Text("You're ready for your \(p.target). Pick a day this week, start easy and enjoy it.").font(.subheadline.bold())
            } else if rest {
                Text("Today's call says rest. If a run is planned today, move it to tomorrow.").font(.caption)
            }
            Divider()
            Text("Coming up").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(p.ahead, id: \.monday) { a in
                HStack {
                    Text(a.monday.text(.short)).frame(width: 64, alignment: .leading)
                    Text("Long \(Fmt.km(a.longKm)) km")
                    Spacer()
                    Text(a.easier ? "easier" : "\(p.perWeek - 1) × \(Fmt.km(a.easyKm)) km").foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

struct MilestonesCard: View {
    var m: Milestones
    var body: some View {
        Card {
            Text("FROM FIRST RUN TO IRONMAN").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(m.steps.enumerated()), id: \.element.id) { i, st in
                HStack(spacing: 10) {
                    Image(systemName: st.reached != nil ? "checkmark.circle.fill" : i == m.next ? "circle.circle" : "circle")
                        .foregroundStyle(st.reached != nil || i == m.next ? Theme.accent : .secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(st.label).font(.subheadline.weight(st.reached != nil || i == m.next ? .semibold : .regular))
                        Text(st.reached.map { "Reached \($0.text(.short))" }
                             ?? (i == m.next && m.toGoKm != nil ? "Next · \(Fmt.km(m.toGoKm!)) km to go" : st.detail))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text(m.tip).font(.caption).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct FormCard: View {
    var runs: [Workout]
    @State private var metric = 0
    private let metrics = ["Pace", "Cadence", "Stride", "Per beat"]

    func value(_ w: Workout) -> Double? {
        switch metric {
        case 0: w.speed.map { 1000 / $0 / 60 }                      // min per km
        case 1: w.cadence
        case 2: w.strideM
        default: (w.speed != nil && w.avgHR != nil) ? w.speed! * 60 / w.avgHR! : nil   // metres per heartbeat
        }
    }

    var body: some View {
        Card {
            Text("Running form and fitness").font(.headline)
            Picker("Measure", selection: $metric) {
                ForEach(metrics.indices, id: \.self) { Text(metrics[$0]).tag($0) }
            }
            .pickerStyle(.segmented)
            let pts = runs.compactMap { w in value(w).map { (w.start, $0) } }
            if pts.count < 2 {
                Text("Shows up after a couple of runs.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(pts.indices, id: \.self) { i in
                        PointMark(x: .value("Date", pts[i].0), y: .value(metrics[metric], pts[i].1)).foregroundStyle(Theme.run)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: metric == 0))
                .frame(height: 170)
            }
            Text(["Minutes per km: lower (higher on the chart) is faster.", "Steps per minute: a little higher usually means lighter strides.",
                  "Metres per step: grows naturally as you get fitter.", "Metres per heartbeat: rising means your fitness is improving."][metric])
                .font(.caption2).foregroundStyle(.secondary)
            if runs.count < 15 {
                Text("Trends become meaningful after about 15–20 runs. You have \(runs.count).").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct BestsCard: View {
    var r: Records
    var body: some View {
        Card {
            Text("Personal bests").font(.headline)
            if r.bests.isEmpty { Text("Your bests show up here after your first workouts.").font(.caption).foregroundStyle(.secondary) }
            ForEach(r.bests) { b in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(b.label).font(.subheadline)
                            if b.isNew { Text("NEW").font(.caption2.bold()).padding(.horizontal, 5).background(Theme.warn, in: Capsule()).foregroundStyle(.black) }
                        }
                        Text((b.note == "week" ? "Week of " : "") + b.day.text(.short) + (b.name.isEmpty ? "" : " · \(b.name)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(b.text).font(.subheadline.bold())
                }
            }
            if !r.firsts.isEmpty {
                Divider()
                Text("Firsts").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(r.firsts) { f in
                    Label("First \(f.sport.name.lowercased()) · \(f.day.text(.short))", systemImage: f.sport.symbol).font(.caption)
                }
            }
        }
    }
}
