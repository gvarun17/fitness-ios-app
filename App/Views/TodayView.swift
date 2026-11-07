import FitnessCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = model.snapshot {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(s.today.text(.long)).font(.subheadline).foregroundStyle(.secondary)
                        if s.isDemo { DemoBanner() }
                        ReadinessCard(r: s.readiness)
                        MetricsGrid(s: s)
                        if !s.newBests.isEmpty { NewBestsCard(bests: s.newBests) }
                        WorkoutsCard(workouts: s.todaysWorkouts, bests: s.records.bests)
                    }
                    .padding()
                } else {
                    ContentUnavailableView("No data yet", systemImage: "heart.text.square",
                                           description: Text("Pull to refresh once Apple Health has some data."))
                }
            }
            .refreshable { await model.refresh() }
            .navigationTitle(model.settings.name.isEmpty ? "Today" : "Hi, \(model.settings.name)")
        }
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Demo data. Connect Apple Health in Settings to see yours.", systemImage: "info.circle")
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

struct MetricsGrid: View {
    var s: Snapshot
    var body: some View {
        let t = s.stats
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            Metric(label: "Steps", value: t.steps.map { Fmt.number(Double($0)) }, values: s.trends.steps)
            Metric(label: "Exercise", value: t.exerciseMinutes.map { "\(Int($0)) min" }, values: s.trends.exerciseMinutes, color: Theme.good)
            Metric(label: "Active", value: t.activeKcal.map { "\(Int($0)) kcal" }, values: s.trends.activeKcal, color: Theme.run)
            Metric(label: "Resting HR", value: t.restingHR.map { "\(Int($0)) bpm" }, values: s.trends.restingHR, color: Theme.bad)
            Metric(label: "HRV", value: t.hrv.map { "\(Int($0)) ms" }, values: s.trends.hrv)
            Metric(label: "Sleep", value: t.sleepHours.map { Fmt.hm(hours: $0) }, values: s.trends.sleepHours, color: .indigo)
        }
    }
}

struct Metric: View {
    var label: String
    var value: String?
    var values: [Double?]
    var color: Color = Theme.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value ?? "–").font(.headline).minimumScaleFactor(0.7).lineLimit(1)
            MiniBars(values: values, color: color).frame(height: 22)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
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
    var body: some View {
        Card {
            Text("Today's workouts").font(.headline)
            if workouts.isEmpty {
                Text("No workouts yet today. They show up here after your watch syncs to Apple Health.")
                    .font(.subheadline).foregroundStyle(.secondary)
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

struct WorkoutDetailView: View {
    var w: Workout
    var bests: [Best]
    var body: some View {
        List {
            Section {
                row("Distance", w.km > 0 ? "\(Fmt.km(w.km)) km" : nil)
                row("Time", Fmt.hm(hours: w.minutes / 60))
                row("Average pace", w.sport == .run || w.sport == .walk ? w.speed.map { "\(Fmt.pace(speed: $0)) /km" } : nil)
                row("Average speed", w.sport == .cycle ? w.speed.map { String(format: "%.1f km/h", $0 * 3.6) } : nil)
                row("Average heart rate", w.avgHR.map { "\(Int($0)) bpm" })
                row("Max heart rate", w.maxHR.map { "\(Int($0)) bpm" })
                row("Calories", w.kcal.map { "\(Int($0)) kcal" })
                row("Cadence", w.cadence.map { "\(Int($0)) spm" })
                row("Stride length", w.strideM.map { String(format: "%.2f m", $0) })
            }
            if !bests.isEmpty {
                Section("Personal bests") {
                    ForEach(bests) { b in Label("\(b.label): \(b.text)", systemImage: "star.fill") }
                }
            }
        }
        .navigationTitle(w.name)
    }

    @ViewBuilder func row(_ label: String, _ value: String?) -> some View {
        if let value { LabeledContent(label, value: value) }
    }
}
