// xcode: set sdk=iOS

import Charts
import FitnessCore
import SwiftUI

struct HealthView: View {
    @EnvironmentObject var model: AppModel
    @State private var range = 30

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let s = model.snapshot { SleepCard(s: s.sleep) }
                    Picker("Range", selection: $range) {
                        Text("1M").tag(30); Text("3M").tag(90); Text("6M").tag(180); Text("1Y").tag(365)
                    }
                    .pickerStyle(.segmented)
                    let days = model.data.days.filter { $0.day >= model.today.adding(-range + 1) }
                    let nights = model.data.nights.filter { $0.day >= model.today.adding(-range + 1) }
                    TrendCard(title: "Steps", points: days.compactMap { d in d.steps.map { (d.day, Double($0)) } }, bars: true, color: Theme.accent)
                    TrendCard(title: "Resting heart rate", unit: "bpm", points: days.compactMap { d in d.restingHR.map { (d.day, $0) } }, color: Theme.bad,
                              note: "Lower over time usually means a fitter heart.")
                    TrendCard(title: "HRV", unit: "ms", points: days.compactMap { d in d.hrv.map { (d.day, $0) } }, color: Theme.accent,
                              note: "Compare with your own trend, not other people's.")
                    TrendCard(title: "Sleep", unit: "h", points: nights.map { ($0.day, $0.asleepHours) }, bars: true, color: .indigo)
                    TrendCard(title: "Exercise minutes", unit: "min", points: days.compactMap { d in d.exerciseMinutes.map { (d.day, $0) } }, bars: true, color: Theme.good)
                    TrendCard(title: "Active calories", unit: "kcal", points: days.compactMap { d in d.activeKcal.map { (d.day, $0) } }, bars: true, color: Theme.run)
                }
                .padding()
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Health")
        }
    }
}

struct SleepCard: View {
    var s: SleepInsights
    var body: some View {
        Card {
            Text("Sleep, last 2 weeks").font(.headline)
            Text("\(s.nightsTracked) nights tracked. Your target: \(Fmt.hm(hours: s.need)).").font(.caption).foregroundStyle(.secondary)
            if s.nightsTracked > 0 {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    stat("Average", s.averageHours.map { Fmt.hm(hours: $0) })
                    stat("Sleep debt", s.debtHours.map { $0 > 0 ? Fmt.hm(hours: $0) : "none" })
                    stat("Bedtime", s.bedtime.map { "\(Fmt.timeOfNight($0)) ±\(s.bedtimeSpread ?? 0)m" })
                }
                let shown = s.nights.filter { $0.bedtime != nil && $0.wake != nil }
                if !shown.isEmpty {
                    Chart(shown, id: \.day) { n in
                        BarMark(x: .value("Night", n.day.text(.short)), yStart: .value("Asleep", n.bedtime!), yEnd: .value("Awake", n.wake!), width: 10)
                            .foregroundStyle(Color.indigo).cornerRadius(4)
                    }
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let m = v.as(Int.self) { Text(Fmt.timeOfNight(m)) } } } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .frame(height: 170)
                    .accessibilityLabel("When you slept, each night")
                }
            }
            ForEach(s.tips, id: \.self) { t in Label(t, systemImage: "lightbulb").font(.caption) }
        }
    }

    func stat(_ label: String, _ v: String?) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(v ?? "–").font(.subheadline.bold()).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrendCard: View {
    var title: String
    var unit = ""
    var points: [(Day, Double)]
    var bars = false
    var color: Color
    var note: String? = nil

    var body: some View {
        Card {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let last = points.last {
                    Text("\(Fmt.number(last.1))\(unit.isEmpty ? "" : " \(unit)")").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if points.isEmpty {
                Text("No data in this range.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(points.indices, id: \.self) { i in
                    if bars {
                        BarMark(x: .value("Day", points[i].0.date, unit: .day), y: .value(title, points[i].1)).foregroundStyle(color)
                    } else {
                        LineMark(x: .value("Day", points[i].0.date, unit: .day), y: .value(title, points[i].1))
                            .foregroundStyle(color).interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: bars))
                .frame(height: 150)
            }
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
