import SwiftUI
import SwiftData
import RunCore

struct PlanView: View {
    var start: (RunSetup) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \PlanRecord.createdDate, order: .reverse) private var records: [PlanRecord]
    @Query(sort: \Shoe.addedDate) private var shoes: [Shoe]
    @AppStorage(SettingsKey.unit) private var unit: DistanceUnit = .localeDefault
    @AppStorage(SettingsKey.defaultShoeID) private var defaultShoeID = ""
    @State private var confirmEnd = false

    var body: some View {
        NavigationStack {
            Group {
                if let record = records.first, let plan = record.plan {
                    planList(record: record, plan: plan)
                } else {
                    PlanSetupView()
                }
            }
            .navigationTitle("Plan")
        }
    }

    private func planList(record: PlanRecord, plan: TrainingPlan) -> some View {
        let completed = record.completed
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let total = plan.allWorkouts.count
        let daysLeft = calendar.dateComponents([.day], from: today, to: plan.raceDate).day ?? 0
        let next = plan.nextWorkout(after: Date(), calendar: calendar, excluding: completed)

        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(plan.race.title) · \(plan.level.title)")
                        .font(.title3.weight(.bold))
                    Text(daysLeft > 0
                         ? "\(daysLeft) days to race day, \(plan.raceDate.formatted(date: .abbreviated, time: .omitted))"
                         : (daysLeft == 0 ? "Race day is today. Good luck!" : "Race day has passed"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: total > 0 ? Double(completed.count) / Double(total) : 0)
                    Text("\(completed.count) of \(total) workouts done")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ForEach(plan.weeks) { week in
                Section {
                    ForEach(week.workouts) { workout in
                        WorkoutRow(workout: workout,
                                   unit: unit,
                                   isDone: completed.contains(workout.id),
                                   isNext: workout.id == next?.id,
                                   isToday: calendar.isDate(workout.date, inSameDayAs: today),
                                   onStart: {
                                       let shoe = shoes.first { !$0.retired && $0.uuid.uuidString == defaultShoeID }
                                       start(PlanLauncher.setup(for: workout, shoeID: shoe?.uuid))
                                   },
                                   onToggle: {
                                       var updated = record.completed
                                       if updated.contains(workout.id) {
                                           updated.remove(workout.id)
                                       } else {
                                           updated.insert(workout.id)
                                       }
                                       record.completed = updated
                                       try? context.save()
                                   })
                    }
                } header: {
                    HStack {
                        Text("Week \(week.number)")
                        Spacer()
                        if week.plannedDistance > 0 {
                            Text("\(Fmt.distance(week.plannedDistance, unit: unit, decimals: 0)) \(unit.abbreviation) + sessions")
                        }
                    }
                }
            }

            Section {
                Button("End Plan", role: .destructive) { confirmEnd = true }
            }
        }
        .confirmationDialog("End this training plan?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Plan", role: .destructive) {
                for record in records { context.delete(record) }
                try? context.save()
            }
        } message: {
            Text("Your recorded runs are kept. The plan and its progress are removed.")
        }
    }
}

private struct WorkoutRow: View {
    var workout: PlannedWorkout
    var unit: DistanceUnit
    var isDone: Bool
    var isNext: Bool
    var isToday: Bool
    var onStart: () -> Void
    var onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(workout.kind.title)
                        .font(.headline)
                        .foregroundStyle(workout.kind.color)
                    if isToday {
                        Text("TODAY")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                Text(workout.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let meters = workout.distance {
                    Text("\(Fmt.distance(meters, unit: unit, decimals: 1)) \(unit.abbreviation)")
                        .font(.subheadline.weight(.semibold))
                }
                Text(workout.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !isDone && (isNext || isToday) {
                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.vertical, 4)
        .opacity(isDone ? 0.6 : 1)
    }
}

/// Collects what the generator needs and creates the plan.
struct PlanSetupView: View {
    @Environment(\.modelContext) private var context
    @State private var race: RaceDistance = .fiveK
    @State private var level: RunnerLevel = .beginner
    @State private var runsPerWeek = 3
    @State private var raceDate = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date()

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let earliest = calendar.date(byAdding: .day, value: PlanGenerator.minimumWeeks * 7 - 6, to: today) ?? today
        let latest = calendar.date(byAdding: .day, value: PlanGenerator.maximumWeeks * 7 - 1, to: today) ?? today
        return earliest...latest
    }

    private var weeks: Int {
        PlanGenerator.weekCount(start: Date(), raceDate: raceDate, calendar: .current)
    }

    private var plan: TrainingPlan? {
        PlanGenerator.generate(race: race, level: level, runsPerWeek: runsPerWeek,
                               start: Date(), raceDate: raceDate, calendar: .current)
    }

    var body: some View {
        Form {
            Section {
                Text("Pick a race and a date. Stride builds a week-by-week plan with easy runs, long runs and speed sessions, tapering into race day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Race") {
                Picker("Distance", selection: $race) {
                    ForEach(RaceDistance.allCases, id: \.self) { race in
                        Text(race.title).tag(race)
                    }
                }
                DatePicker("Race day", selection: $raceDate, in: dateRange, displayedComponents: .date)
            }

            Section {
                Picker("Level", selection: $level) {
                    ForEach(RunnerLevel.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                Stepper("\(runsPerWeek) runs per week", value: $runsPerWeek, in: 3...5)
            } header: {
                Text("You")
            } footer: {
                Text(level.summary)
            }

            Section {
                Button {
                    guard let plan else { return }
                    context.insert(PlanRecord(plan: plan))
                    try? context.save()
                } label: {
                    Text("Create \(weeks)-Week Plan")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(plan == nil)
            } footer: {
                if plan == nil {
                    Text("Choose a race day between \(PlanGenerator.minimumWeeks) and \(PlanGenerator.maximumWeeks) weeks away.")
                }
            }
        }
    }
}
