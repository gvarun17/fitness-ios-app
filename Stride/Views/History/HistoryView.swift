import SwiftUI
import SwiftData
import RunCore

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(SettingsKey.unit) private var unit: DistanceUnit = .localeDefault

    private struct MonthGroup: Identifiable {
        var id: Date
        var runs: [Run]
    }

    private var groups: [MonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: runs) { run in
            calendar.dateInterval(of: .month, for: run.startDate)?.start ?? run.startDate
        }
        return grouped.keys.sorted(by: >).map { MonthGroup(id: $0, runs: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if runs.isEmpty {
                    ContentUnavailableView("No runs yet",
                                           systemImage: "figure.run",
                                           description: Text("Your runs will show up here once you finish one."))
                } else {
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.runs) { run in
                                    NavigationLink {
                                        RunDetailView(run: run)
                                    } label: {
                                        RunRow(run: run, unit: unit)
                                    }
                                }
                                .onDelete { offsets in
                                    for index in offsets {
                                        RunStore.delete(group.runs[index], in: context)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(group.id.formatted(.dateTime.month(.wide).year()))
                                    Spacer()
                                    let total = group.runs.reduce(0) { $0 + $1.distance }
                                    Text("\(group.runs.count) runs · \(Fmt.distance(total, unit: unit, decimals: 1)) \(unit.abbreviation)")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activity")
        }
    }
}

struct RunRow: View {
    var run: Run
    var unit: DistanceUnit

    var body: some View {
        HStack(spacing: 12) {
            RouteThumbnailView(points: run.thumbnail)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(run.title.isEmpty ? "Run" : run.title)
                        .font(.headline)
                        .lineLimit(1)
                    TagBadge(tag: run.tag)
                }
                Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text("\(Fmt.distance(run.distance, unit: unit)) \(unit.abbreviation)")
                        .fontWeight(.semibold)
                    Text(Fmt.duration(run.duration))
                    Text("\(Fmt.pace(secondsPerMeter: run.secondsPerMeter, unit: unit)) /\(unit.abbreviation)")
                }
                .font(.subheadline)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}
