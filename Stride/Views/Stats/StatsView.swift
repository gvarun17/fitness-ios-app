import SwiftUI
import SwiftData
import Charts
import RunCore

struct StatsView: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(SettingsKey.unit) private var unit: DistanceUnit = .localeDefault
    @AppStorage(SettingsKey.weeklyGoalMeters) private var weeklyGoal = 20_000.0
    @State private var period: StatsPeriod = .week

    private struct Record: Identifiable {
        var distance: RecordDistance
        var time: Double
        var run: Run
        var id: Int { distance.id }
    }

    private var summaries: [RunSummary] { runs.map(\.summary) }

    private var bucketCount: Int {
        switch period {
        case .week: return 12
        case .month: return 12
        case .year: return 5
        }
    }

    private var chartUnit: Calendar.Component {
        switch period {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    private var periodTitle: String {
        switch period {
        case .week: return "This week"
        case .month: return "This month"
        case .year: return "This year"
        }
    }

    private var records: [Record] {
        var best: [Int: Record] = [:]
        for run in runs {
            for (id, time) in run.bestEfforts {
                guard let distance = RecordDistance.all.first(where: { $0.id == id }) else { continue }
                if let current = best[id], current.time <= time { continue }
                best[id] = Record(distance: distance, time: time, run: run)
            }
        }
        return RecordDistance.all.compactMap { best[$0.id] }
    }

    var body: some View {
        NavigationStack {
            Group {
                if runs.isEmpty {
                    ContentUnavailableView("Nothing to show yet",
                                           systemImage: "chart.bar.fill",
                                           description: Text("Finish a run to start building your stats."))
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Picker("Period", selection: $period) {
                                Text("Week").tag(StatsPeriod.week)
                                Text("Month").tag(StatsPeriod.month)
                                Text("Year").tag(StatsPeriod.year)
                            }
                            .pickerStyle(.segmented)

                            currentCard
                            chartCard
                            streakCard
                            recordsCard
                            allTimeCard
                        }
                        .padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Progress")
        }
    }

    private var currentCard: some View {
        let current = Stats.current(summaries, period: period, now: Date(), calendar: .current)
        return Card {
            VStack(spacing: 14) {
                SectionTitle(periodTitle)
                HStack {
                    MetricView(value: Fmt.distance(current.distance, unit: unit, decimals: 1), label: unit.abbreviation, size: 32)
                    MetricView(value: "\(current.runCount)", label: current.runCount == 1 ? "Run" : "Runs", size: 32)
                }
                HStack {
                    MetricView(value: Fmt.duration(current.duration), label: "Time")
                    MetricView(value: Fmt.pace(distance: current.distance, duration: current.duration, unit: unit), label: "Avg pace")
                }
                if period == .week && weeklyGoal > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: min(1, current.distance / weeklyGoal))
                        Text(current.distance >= weeklyGoal
                             ? "Weekly goal reached"
                             : "\(Fmt.distance(weeklyGoal - current.distance, unit: unit, decimals: 1)) \(unit.abbreviation) to your weekly goal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var chartCard: some View {
        let buckets = Stats.buckets(summaries, period: period, count: bucketCount, now: Date(), calendar: .current)
        return Card {
            VStack(spacing: 10) {
                SectionTitle("Distance")
                Chart(buckets) { bucket in
                    BarMark(x: .value("Period", bucket.start, unit: chartUnit),
                            y: .value("Distance", bucket.distance / unit.meters))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(4)
                }
                .chartYAxisLabel(unit.abbreviation)
                .frame(height: 200)
            }
        }
    }

    private var streakCard: some View {
        let dates = runs.map(\.startDate)
        let calendar = Calendar.current
        return Card {
            VStack(spacing: 14) {
                SectionTitle("Streaks")
                HStack {
                    MetricView(value: "\(Stats.currentDayStreak(dates: dates, today: Date(), calendar: calendar))", label: "Day streak")
                    MetricView(value: "\(Stats.longestDayStreak(dates: dates, calendar: calendar))", label: "Best days")
                    MetricView(value: "\(Stats.currentWeekStreak(dates: dates, today: Date(), calendar: calendar))", label: "Week streak")
                }
            }
        }
    }

    private var recordsCard: some View {
        let records = self.records
        let longest = runs.max { $0.distance < $1.distance }
        return Card {
            VStack(spacing: 12) {
                SectionTitle("Personal Records")
                if records.isEmpty {
                    Text("Run at least 1 km to set your first record.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(records) { record in
                    NavigationLink {
                        RunDetailView(run: record.run)
                    } label: {
                        recordRow(title: record.distance.name,
                                  value: Fmt.duration(record.time),
                                  detail: "\(Fmt.pace(secondsPerMeter: record.time / record.distance.meters, unit: unit)) /\(unit.abbreviation)",
                                  date: record.run.startDate)
                    }
                    .buttonStyle(.plain)
                }
                if let longest {
                    NavigationLink {
                        RunDetailView(run: longest)
                    } label: {
                        recordRow(title: "Longest Run",
                                  value: "\(Fmt.distance(longest.distance, unit: unit)) \(unit.abbreviation)",
                                  detail: Fmt.duration(longest.duration),
                                  date: longest.startDate)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recordRow(title: String, value: String, detail: String, date: Date) -> some View {
        HStack {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var allTimeCard: some View {
        let distance = runs.reduce(0) { $0 + $1.distance }
        let duration = runs.reduce(0) { $0 + $1.duration }
        let climb = runs.reduce(0) { $0 + $1.elevationGain }
        return Card {
            VStack(spacing: 14) {
                SectionTitle("All Time")
                HStack {
                    MetricView(value: Fmt.distance(distance, unit: unit, decimals: 0), label: unit.abbreviation)
                    MetricView(value: "\(runs.count)", label: "Runs")
                    MetricView(value: Fmt.duration(duration), label: "Time")
                    MetricView(value: Fmt.elevation(climb, unit: unit), label: "Climb")
                }
            }
        }
    }
}
