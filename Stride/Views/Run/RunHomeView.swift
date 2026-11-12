import SwiftUI
import SwiftData
import MapKit
import RunCore

struct RunHomeView: View {
    var start: (RunSetup) -> Void

    @Environment(\.openURL) private var openURL
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query(sort: \Shoe.addedDate) private var shoes: [Shoe]
    @Query private var plans: [PlanRecord]

    @AppStorage(SettingsKey.unit) private var unit: DistanceUnit = .localeDefault
    @AppStorage(SettingsKey.weeklyGoalMeters) private var weeklyGoal = 20_000.0
    @AppStorage(SettingsKey.defaultShoeID) private var defaultShoeID = ""
    @AppStorage(SettingsKey.goalType) private var goalType = "distance"
    @AppStorage(SettingsKey.goalDistanceMeters) private var goalDistance = 5000.0
    @AppStorage(SettingsKey.goalTimeSeconds) private var goalTime = 1800.0
    @AppStorage(SettingsKey.goalPaceSecondsPerKm) private var goalPacePerKm = 360.0
    @AppStorage(SettingsKey.lastIntervalWorkout) private var intervalData = Data()

    @StateObject private var location = LocationService()
    @State private var mode = 0
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showBuilder = false

    private var activeShoes: [Shoe] { shoes.filter { !$0.retired } }

    private var selectedShoe: Shoe? {
        activeShoes.first { $0.uuid.uuidString == defaultShoeID }
    }

    private var intervalWorkout: IntervalWorkout {
        if let saved = try? JSONDecoder().decode(IntervalWorkout.self, from: intervalData) {
            return saved
        }
        return IntervalWorkout.make(name: "6 x 400 m", warmup: 600, repeats: 6,
                                    run: .distance(400), recover: .time(90), cooldown: 600)
    }

    private var goal: RunGoal {
        switch goalType {
        case "time": return .time(goalTime)
        case "pace": return .pace(goalPacePerKm / 1000)
        default: return .distance(goalDistance)
        }
    }

    private var weekDistance: Double {
        Stats.current(runs.map(\.summary), period: .week, now: Date(), calendar: .current).distance
    }

    private var todaysWorkout: PlannedWorkout? {
        guard let record = plans.first, let plan = record.plan,
              let workout = plan.workout(on: Date(), calendar: .current),
              !record.completed.contains(workout.id) else { return nil }
        return workout
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    mapHeader
                    if location.isDenied { locationWarning }
                    weekCard
                    if let workout = todaysWorkout { todayCard(workout) }
                    setupCard
                    startButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stride")
            .onAppear { location.requestPermission() }
            .sheet(isPresented: $showBuilder) {
                IntervalBuilderView(initial: intervalWorkout) { workout in
                    intervalData = (try? JSONEncoder().encode(workout)) ?? Data()
                }
            }
        }
    }

    // MARK: Sections

    private var mapHeader: some View {
        Map(position: $camera) {
            UserAnnotation()
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
    }

    private var locationWarning: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Location access is off", systemImage: "location.slash.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Stride needs your location to measure distance and pace. Turn it on in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var weekCard: some View {
        Card {
            HStack(spacing: 16) {
                ProgressRing(fraction: weeklyGoal > 0 ? weekDistance / weeklyGoal : 0, lineWidth: 8) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 2) {
                    Text("THIS WEEK")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Fmt.distance(weekDistance, unit: unit, decimals: 1))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("/ \(Fmt.distance(weeklyGoal, unit: unit, decimals: 0)) \(unit.abbreviation)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func todayCard(_ workout: PlannedWorkout) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("TODAY'S PLAN")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.kind.title)
                            .font(.headline)
                        if let meters = workout.distance {
                            Text("\(Fmt.distance(meters, unit: unit, decimals: 1)) \(unit.abbreviation)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(workout.kind.color)
                        }
                        Text(workout.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Start") {
                        start(PlanLauncher.setup(for: workout, shoeID: selectedShoe?.uuid))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }
        }
    }

    private var setupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Run type", selection: $mode) {
                    Text("Free").tag(0)
                    Text("Goal").tag(1)
                    Text("Intervals").tag(2)
                }
                .pickerStyle(.segmented)

                switch mode {
                case 1: goalControls
                case 2: intervalControls
                default:
                    Text("Just run. Distance, pace and splits are tracked automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()
                shoePicker
            }
        }
    }

    private var goalControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Goal", selection: $goalType) {
                Text("Distance").tag("distance")
                Text("Time").tag("time")
                Text("Pace").tag("pace")
            }
            .pickerStyle(.segmented)

            switch goalType {
            case "time":
                Stepper(value: $goalTime, in: 300...21_600, step: 300) {
                    goalLabel(Fmt.duration(goalTime), "duration")
                }
            case "pace":
                // Stored per km; shown and stepped in the runner's unit.
                Stepper {
                    goalLabel(Fmt.pace(secondsPerMeter: goalPacePerKm / 1000, unit: unit), "per \(unit.abbreviation)")
                } onIncrement: {
                    goalPacePerKm = min(900, goalPacePerKm + 5 * 1000 / unit.meters)
                } onDecrement: {
                    goalPacePerKm = max(150, goalPacePerKm - 5 * 1000 / unit.meters)
                }
            default:
                Stepper {
                    goalLabel(Fmt.distance(goalDistance, unit: unit, decimals: 1), unit.abbreviation)
                } onIncrement: {
                    goalDistance = min(100 * unit.meters, snapped(goalDistance) + unit.meters / 2)
                } onDecrement: {
                    goalDistance = max(unit.meters / 2, snapped(goalDistance) - unit.meters / 2)
                }
            }
        }
    }

    /// Rounds a distance to the nearest half unit so stepping stays on tidy values.
    private func snapped(_ meters: Double) -> Double {
        (meters / (unit.meters / 2)).rounded() * (unit.meters / 2)
    }

    private func goalLabel(_ value: String, _ suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(suffix)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var intervalControls: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(intervalWorkout.name)
                    .font(.headline)
                Text(Describe.workout(intervalWorkout, unit: unit))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit") { showBuilder = true }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }

    private var shoePicker: some View {
        HStack {
            Label("Shoes", systemImage: "shoe.fill")
                .font(.subheadline)
            Spacer()
            if activeShoes.isEmpty {
                Text("Add shoes in Settings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Shoes", selection: $defaultShoeID) {
                    Text("None").tag("")
                    ForEach(activeShoes) { shoe in
                        Text(shoe.displayName).tag(shoe.uuid.uuidString)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var startButton: some View {
        Button {
            var setup = RunSetup()
            setup.shoeID = selectedShoe?.uuid
            switch mode {
            case 1:
                setup.mode = .goal(goal)
            case 2:
                setup.mode = .intervals(intervalWorkout)
                setup.tag = .intervals
            default:
                break
            }
            start(setup)
        } label: {
            Text("START")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 132, height: 132)
                .background(Color.accentColor, in: Circle())
                .shadow(color: Color.accentColor.opacity(0.45), radius: 16, y: 6)
        }
        .padding(.top, 8)
        .accessibilityLabel("Start run")
    }
}

/// Turns a planned workout into a ready-to-start run.
enum PlanLauncher {
    static func setup(for workout: PlannedWorkout, shoeID: UUID?) -> RunSetup {
        var setup = RunSetup()
        setup.tag = workout.kind.runTag
        setup.plannedWorkoutID = workout.id
        setup.shoeID = shoeID
        if let intervals = workout.intervals {
            setup.mode = .intervals(intervals)
        } else if let meters = workout.distance {
            setup.mode = .goal(.distance(meters))
        }
        return setup
    }
}
