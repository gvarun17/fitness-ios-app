import SwiftUI
import SwiftData
import RunCore

/// Builds a warm-up / repeats / cool-down workout.
struct IntervalBuilderView: View {
    var onSave: (IntervalWorkout) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedWorkout.createdDate, order: .reverse) private var saved: [SavedWorkout]
    @AppStorage(SettingsKey.unit) private var unit: DistanceUnit = .localeDefault

    @State private var warmupMinutes: Int
    @State private var cooldownMinutes: Int
    @State private var repeats: Int
    @State private var runByDistance: Bool
    @State private var runMeters: Double
    @State private var runSeconds: Double
    @State private var recoverByDistance: Bool
    @State private var recoverMeters: Double
    @State private var recoverSeconds: Double

    init(initial: IntervalWorkout, onSave: @escaping (IntervalWorkout) -> Void) {
        self.onSave = onSave
        let values = Self.values(from: initial)
        _warmupMinutes = State(initialValue: values.warmup)
        _cooldownMinutes = State(initialValue: values.cooldown)
        _repeats = State(initialValue: values.repeats)
        _runByDistance = State(initialValue: values.runByDistance)
        _runMeters = State(initialValue: values.runMeters)
        _runSeconds = State(initialValue: values.runSeconds)
        _recoverByDistance = State(initialValue: values.recoverByDistance)
        _recoverMeters = State(initialValue: values.recoverMeters)
        _recoverSeconds = State(initialValue: values.recoverSeconds)
    }

    private struct Values {
        var warmup = 10
        var cooldown = 10
        var repeats = 6
        var runByDistance = true
        var runMeters = 400.0
        var runSeconds = 120.0
        var recoverByDistance = false
        var recoverMeters = 200.0
        var recoverSeconds = 90.0
    }

    private static func values(from workout: IntervalWorkout) -> Values {
        var v = Values()
        v.warmup = 0
        v.cooldown = 0
        for step in workout.steps {
            switch (step.kind, step.measure) {
            case (.warmup, .time(let t)): v.warmup = Int(t / 60)
            case (.cooldown, .time(let t)): v.cooldown = Int(t / 60)
            case (.run, .distance(let d)): v.runByDistance = true; v.runMeters = d
            case (.run, .time(let t)): v.runByDistance = false; v.runSeconds = t
            case (.recover, .distance(let d)): v.recoverByDistance = true; v.recoverMeters = d
            case (.recover, .time(let t)): v.recoverByDistance = false; v.recoverSeconds = t
            default: break
            }
        }
        v.repeats = max(1, workout.runStepCount)
        return v
    }

    private var workout: IntervalWorkout {
        let run: StepMeasure = runByDistance ? .distance(runMeters) : .time(runSeconds)
        let recover: StepMeasure = recoverByDistance ? .distance(recoverMeters) : .time(recoverSeconds)
        let name = "\(repeats) x \(Describe.measure(run, unit: unit))"
        return IntervalWorkout.make(name: name,
                                    warmup: warmupMinutes > 0 ? Double(warmupMinutes) * 60 : nil,
                                    repeats: repeats, run: run, recover: recover,
                                    cooldown: cooldownMinutes > 0 ? Double(cooldownMinutes) * 60 : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Warm-up") {
                    Stepper(warmupMinutes == 0 ? "None" : "\(warmupMinutes) min", value: $warmupMinutes, in: 0...30)
                }

                Section("Intervals") {
                    Stepper("\(repeats) repeats", value: $repeats, in: 1...30)
                    measureRow(title: "Run", byDistance: $runByDistance, meters: $runMeters, seconds: $runSeconds)
                    measureRow(title: "Recover", byDistance: $recoverByDistance, meters: $recoverMeters, seconds: $recoverSeconds)
                }

                Section("Cool-down") {
                    Stepper(cooldownMinutes == 0 ? "None" : "\(cooldownMinutes) min", value: $cooldownMinutes, in: 0...30)
                }

                Section("Summary") {
                    Text(Describe.workout(workout, unit: unit))
                        .font(.subheadline)
                    Button("Save as preset") {
                        context.insert(SavedWorkout(workout: workout))
                        try? context.save()
                    }
                }

                if !saved.isEmpty {
                    Section("Presets") {
                        ForEach(saved) { preset in
                            Button {
                                if let stored = preset.workout { apply(stored) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .foregroundStyle(.primary)
                                    if let stored = preset.workout {
                                        Text(Describe.workout(stored, unit: unit))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(saved[index]) }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Interval Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onSave(workout)
                        dismiss()
                    }
                }
            }
        }
    }

    private func apply(_ stored: IntervalWorkout) {
        let v = Self.values(from: stored)
        warmupMinutes = v.warmup
        cooldownMinutes = v.cooldown
        repeats = v.repeats
        runByDistance = v.runByDistance
        runMeters = v.runMeters
        runSeconds = v.runSeconds
        recoverByDistance = v.recoverByDistance
        recoverMeters = v.recoverMeters
        recoverSeconds = v.recoverSeconds
    }

    private func measureRow(title: String, byDistance: Binding<Bool>, meters: Binding<Double>, seconds: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Picker(title, selection: byDistance) {
                    Text("Distance").tag(true)
                    Text("Time").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            if byDistance.wrappedValue {
                Stepper("\(Int(meters.wrappedValue)) m", value: meters, in: 100...5000, step: 100)
            } else {
                Stepper(Fmt.duration(seconds.wrappedValue), value: seconds, in: 15...1800, step: 15)
            }
        }
    }
}
