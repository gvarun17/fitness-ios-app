import SwiftUI
import SwiftData
import MapKit
import Charts
import RunCore

struct RunDetailView: View {
    @Bindable var run: Run
    var isNew = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Shoe.addedDate) private var shoes: [Shoe]
    @AppStorage(SettingsKey.unit) private var unit: DistanceUnit = .localeDefault

    @State private var points: [TrackPoint] = []
    @State private var splits: [Split] = []
    @State private var paceSamples: [ChartSample] = []
    @State private var elevationSamples: [ChartSample] = []
    @State private var heartRates: [HeartRateSample] = []
    @State private var loaded = false
    @State private var confirmDelete = false

    private var shareText: String {
        "\(run.title): \(Fmt.distance(run.distance, unit: unit)) \(unit.abbreviation) in \(Fmt.duration(run.duration)) " +
        "(\(Fmt.pace(secondsPerMeter: run.secondsPerMeter, unit: unit)) /\(unit.abbreviation))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isNew {
                    Label("Run saved", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                header
                if points.count > 1 { map }
                statsCard
                detailsCard
                if !splits.isEmpty { splitsCard }
                if paceSamples.count > 2 { paceChart }
                if elevationSamples.count > 2 { elevationChart }
                if heartRates.count > 2 { heartRateChart }
                if !run.bestEfforts.isEmpty { bestEffortsCard }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isNew ? "Summary" : "Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if isNew {
                    Button("Discard", role: .destructive) { confirmDelete = true }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if !isNew {
                    ShareLink(item: shareText)
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete run")
                }
            }
        }
        .confirmationDialog("Delete this run?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Run", role: .destructive) {
                RunStore.delete(run, in: context)
                dismiss()
            }
        } message: {
            Text("This can't be undone.")
        }
        .task {
            guard !loaded else { return }
            loaded = true
            load()
        }
        .onChange(of: unit) {
            splits = SplitCalculator.splits(points: points, splitLength: unit.meters)
        }
    }

    private func load() {
        let decoded = run.points
        points = decoded
        splits = SplitCalculator.splits(points: decoded, splitLength: unit.meters)
        elevationSamples = ChartSeries.elevation(points: decoded)
        heartRates = run.heartRates

        // Cap slow outliers (walk breaks, stops) so they don't flatten the rest of the chart.
        let raw = ChartSeries.pace(points: decoded)
        let sorted = raw.map(\.value).sorted()
        if !sorted.isEmpty {
            let median = sorted[sorted.count / 2]
            paceSamples = raw.map { ChartSample(distance: $0.distance, value: min($0.value, median * 1.8)) }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $run.title)
                .font(.title2.weight(.bold))
            HStack(spacing: 8) {
                Text(run.startDate.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if run.savedToHealth {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                        .accessibilityLabel("Saved to Apple Health")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var map: some View {
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: points.map(\.coordinate))
                .stroke(Color.accentColor, lineWidth: 4)
            if let first = points.first {
                Annotation("Start", coordinate: first.coordinate) {
                    Circle().fill(.green).stroke(.white, lineWidth: 2).frame(width: 14, height: 14)
                }
            }
            if let last = points.last {
                Annotation("Finish", coordinate: last.coordinate) {
                    Circle().fill(.red).stroke(.white, lineWidth: 2).frame(width: 14, height: 14)
                }
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statsCard: some View {
        Card {
            VStack(spacing: 18) {
                HStack {
                    MetricView(value: Fmt.distance(run.distance, unit: unit), label: unit.abbreviation, size: 34)
                    MetricView(value: Fmt.duration(run.duration), label: "Time", size: 34)
                }
                HStack {
                    MetricView(value: Fmt.pace(secondsPerMeter: run.secondsPerMeter, unit: unit), label: "Avg pace")
                    MetricView(value: Fmt.elevation(run.elevationGain, unit: unit), label: "Climb")
                    MetricView(value: "\(Int(run.calories.rounded()))", label: "Kcal")
                }
                if let average = run.averageHeartRate, let maximum = run.maxHeartRate {
                    HStack {
                        MetricView(value: "\(Int(average.rounded()))", label: "Avg BPM")
                        MetricView(value: "\(Int(maximum.rounded()))", label: "Max BPM")
                    }
                }
            }
        }
    }

    private var detailsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Type")
                    Spacer()
                    Picker("Type", selection: $run.tagRaw) {
                        ForEach(RunTag.allCases) { tag in
                            Text(tag.title).tag(tag.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Divider()
                HStack {
                    Text("Shoes")
                    Spacer()
                    Picker("Shoes", selection: $run.shoe) {
                        Text("None").tag(nil as Shoe?)
                        ForEach(shoes) { shoe in
                            Text(shoe.displayName).tag(shoe as Shoe?)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Effort")
                        Spacer()
                        Text(run.effort == 0 ? "Not rated" : "\(run.effort) / 10")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(run.effort) }, set: { run.effort = Int($0.rounded()) }),
                           in: 0...10, step: 1)
                        .accessibilityLabel("Effort")
                }
                Divider()
                TextField("How did it feel?", text: $run.notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
    }

    private var splitsCard: some View {
        let fastest = splits.filter { !$0.isPartial }.compactMap(\.secondsPerMeter).min()
        let slowest = splits.compactMap(\.secondsPerMeter).max() ?? 1
        return Card {
            VStack(spacing: 10) {
                SectionTitle("Splits")
                ForEach(splits) { split in
                    let pace = split.secondsPerMeter ?? 0
                    HStack(spacing: 10) {
                        Text(split.isPartial ? Fmt.distance(split.distance, unit: unit) : "\(split.index)")
                            .frame(width: 40, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(Fmt.pace(secondsPerMeter: split.secondsPerMeter, unit: unit))
                            .fontWeight(.semibold)
                            .frame(width: 56, alignment: .leading)
                        GeometryReader { proxy in
                            // Faster splits get longer bars.
                            let fraction = pace > 0 ? min(1, (fastest ?? pace) / pace) : 0
                            let base = (fastest ?? pace) / slowest
                            let scaled = base < 1 ? 0.25 + 0.75 * (fraction - base) / (1 - base) : 1
                            Capsule()
                                .fill(pace == fastest ? Color.accentColor : Color.accentColor.opacity(0.45))
                                .frame(width: max(6, proxy.size.width * max(0, scaled)))
                        }
                        .frame(height: 10)
                        Text(Fmt.elevation(split.elevationChange, unit: unit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                }
            }
        }
    }

    private var paceChart: some View {
        Card {
            VStack(spacing: 10) {
                SectionTitle("Pace")
                Chart(paceSamples) { sample in
                    LineMark(x: .value("Distance", sample.distance / unit.meters),
                             y: .value("Pace", sample.value * unit.meters))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.accentColor)
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(Fmt.duration(seconds))
                            }
                        }
                    }
                }
                .chartXAxisLabel(unit.abbreviation)
                .frame(height: 180)
            }
        }
    }

    private var elevationChart: some View {
        let values = elevationSamples.map { unit.elevation(fromMeters: $0.value) }
        let low = (values.min() ?? 0) - 2
        let high = max((values.max() ?? 0) + 2, low + 10)
        return Card {
            VStack(spacing: 10) {
                SectionTitle("Elevation")
                Chart(elevationSamples) { sample in
                    AreaMark(x: .value("Distance", sample.distance / unit.meters),
                             yStart: .value("Base", low),
                             yEnd: .value("Elevation", unit.elevation(fromMeters: sample.value)))
                        .foregroundStyle(Color.green.opacity(0.3))
                    LineMark(x: .value("Distance", sample.distance / unit.meters),
                             y: .value("Elevation", unit.elevation(fromMeters: sample.value)))
                        .foregroundStyle(Color.green)
                }
                .chartYScale(domain: low...high)
                .chartXAxisLabel(unit.abbreviation)
                .chartYAxisLabel(unit.elevationAbbreviation)
                .frame(height: 150)
            }
        }
    }

    private var heartRateChart: some View {
        Card {
            VStack(spacing: 10) {
                SectionTitle("Heart Rate")
                Chart(heartRates) { sample in
                    LineMark(x: .value("Minutes", sample.t / 60),
                             y: .value("BPM", sample.bpm))
                        .foregroundStyle(Color.pink)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxisLabel("min")
                .frame(height: 150)
            }
        }
    }

    private var bestEffortsCard: some View {
        let efforts = run.bestEfforts
        return Card {
            VStack(spacing: 10) {
                SectionTitle("Best Efforts")
                ForEach(RecordDistance.all.filter { efforts[$0.id] != nil }) { record in
                    HStack {
                        Text(record.name)
                        Spacer()
                        Text(Fmt.duration(efforts[record.id] ?? 0))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}
