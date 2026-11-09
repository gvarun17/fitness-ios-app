import FitnessCore
import SwiftUI

// Everything on the Running screen that you can change: the weekly goal, the
// weekly plan, a day-by-day race plan, and any single day of it.

extension Day {
    /// Midnight of this day in the phone's time zone, for date pickers
    var localDate: Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
    }
}

// MARK: - Weekly goal

struct GoalEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var type = GoalType.minutes
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Count", selection: $type) { ForEach(GoalType.allCases) { Text($0.label).tag($0) } }
                    TextField("Suggested: \(Int(type.suggested)) \(type.unit)", text: $text).keyboardType(.decimalPad)
                } footer: {
                    Text("Counted Monday to Sunday. Leave the number empty for the suggested target.")
                }
                if let error { Text(error).foregroundStyle(Theme.bad) }
            }
            .navigationTitle("Weekly goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            var s = model.settings
                            s.goalValue = try UserSettings.cleanGoal(type, text)
                            s.goalType = type
                            model.save(settings: s)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .onAppear {
                type = model.settings.goalType
                text = model.settings.goalValue.map { $0.rounded() == $0 ? "\(Int($0))" : "\($0)" } ?? ""
            }
        }
    }
}

// MARK: - Weekly plan

struct PlanEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var runs = 3
    @State private var days: Set<Int> = []
    @State private var growth = 10.0
    @State private var easierEvery = 4
    @State private var target = "auto"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(runs) runs a week", value: $runs, in: 2...6)
                        .onChange(of: runs) { _, n in days = Set(Coach.planDays[n]!) }
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = days.contains(d)
                            Button(String(PlanSettings.weekdayNames[d - 1].prefix(2))) {
                                if on { days.remove(d) } else { days.insert(d) }
                            }
                            .buttonStyle(.bordered).tint(on ? Theme.accent : .gray)
                            .font(.caption.bold())
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                } header: { Text("When you run") } footer: {
                    Text(days.count == runs ? "Your last running day each week is the long run."
                                            : "Pick \(runs) days (\(days.count) picked). Until then, the suggested days are used.")
                        .foregroundStyle(days.count == runs ? Color.secondary : Theme.warn)
                }
                Section {
                    Picker("Build toward", selection: $target) {
                        Text("My next milestone").tag("auto")
                        ForEach(PlanSettings.targets, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    VStack(alignment: .leading) {
                        Text("Long run grows \(Int(growth))% a week")
                        Slider(value: $growth, in: 5...15, step: 1)
                    }
                    Picker("Easier week", selection: $easierEvery) {
                        Text("Every 3rd week").tag(3); Text("Every 4th week").tag(4); Text("Every 5th week").tag(5); Text("Never").tag(0)
                    }
                } header: { Text("How it builds") } footer: {
                    Text("About 10% a week, with an easier week every 4th, is a common safe pace for beginners. Going faster raises the risk of injury.")
                }
                Section {
                    Button("Back to the suggested plan", role: .destructive) {
                        var s = model.settings
                        s.plan = nil
                        model.save(settings: s)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Weekly plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var s = model.settings
                        s.plan = PlanSettings(runsPerWeek: runs, days: days.count == runs ? days.sorted() : nil,
                                              growth: growth / 100, easierEvery: easierEvery, target: target == "auto" ? nil : target)
                        model.save(settings: s)
                        dismiss()
                    }
                }
            }
            .onAppear {
                let p = model.settings.plan ?? PlanSettings()
                runs = model.snapshot?.plan.perWeek ?? 3
                days = Set(p.days ?? Coach.planDays[runs]!)
                growth = (p.growth ?? 0.10) * 100
                easierEvery = p.easierEvery ?? 4
                target = p.target ?? "auto"
            }
        }
    }
}

// MARK: - Race plan settings

struct RaceEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var goal = RaceGoal.fiveK
    @State private var date = Date()
    @State private var runs = 3
    @State private var longDay = 6
    @State private var strength = false
    @State private var startKm = 1.0
    @State private var keepEdits = true
    @State private var confirmDelete = false

    var existing: RaceSettings? { model.settings.race }

    var settings: RaceSettings {
        RaceSettings(goal: goal, raceDate: Day(date: date), startDate: existing?.startDate ?? model.today, runsPerWeek: runs,
                     longRunDay: longDay, strengthDay: strength, startLongKm: startKm,
                     edits: keepEdits ? existing?.edits ?? [:] : [:])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your goal") {
                    Picker("Race", selection: $goal) { ForEach(RaceGoal.allCases) { Text($0.label).tag($0) } }
                    DatePicker("Race day", selection: $date, in: model.today.adding(7).localDate..., displayedComponents: .date)
                }
                Section {
                    Stepper("\(runs) runs a week", value: $runs, in: 2...6)
                    Picker("Long run on", selection: $longDay) {
                        ForEach(1...7, id: \.self) { Text(PlanSettings.weekdayNames[$0 - 1]).tag($0) }
                    }
                    Toggle("Add a strength day", isOn: $strength)
                    Stepper("Longest recent run: \(Fmt.km(startKm)) km", value: $startKm, in: 0.5...42, step: 0.5)
                } header: { Text("Your week") } footer: {
                    Text("The plan starts from your longest recent run and adds about 10% a week, with an easier week every 4th and a taper before the race.")
                }
                let plan = Coach.racePlan(settings)
                Section("Preview") {
                    LabeledContent("Length", value: "\(plan.weeks) weeks")
                    LabeledContent("Longest run before the race", value: "\(Fmt.km(plan.peakLongKm)) km")
                    LabeledContent("Total", value: "\(Int(plan.totalKm)) km")
                    if let w = plan.warning {
                        Label(w, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.warn)
                        if plan.suggestedDate > Day(date: date) {
                            Button("Race on \(plan.suggestedDate.text(.long)) instead") { date = plan.suggestedDate.localDate }
                        }
                    }
                }
                if existing != nil {
                    Section {
                        Toggle("Keep the days I've edited", isOn: $keepEdits)
                        Button("Delete this plan", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Plan for a race" : "Edit race plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Create" : "Save") {
                        var s = model.settings
                        s.race = settings
                        model.save(settings: s)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete the race plan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    var s = model.settings
                    s.race = nil
                    model.save(settings: s)
                    dismiss()
                }
            } message: { Text("Your weekly plan comes back. Your workouts aren't affected.") }
            .onAppear {
                if let e = existing {
                    goal = e.goal; date = e.raceDate.localDate; runs = e.runsPerWeek; longDay = e.longRunDay
                    strength = e.strengthDay; startKm = e.startLongKm
                } else {
                    date = model.today.adding(7 * 12).localDate
                    runs = model.snapshot?.plan.perWeek ?? 3
                    let recent = model.data.workouts.filter { $0.sport == .run && $0.day >= model.today.adding(-28) }.map(\.km).max() ?? 1
                    startKm = max((recent * 2).rounded() / 2, 0.5)
                }
            }
        }
    }
}

// MARK: - One day of the race plan

struct DayEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let original: PlanDay
    @State private var kind = DayKind.easy
    @State private var km = 3.0
    @State private var note = ""
    @State private var skipped = false

    var body: some View {
        NavigationStack {
            Form {
                Section(original.day.text(.long)) {
                    Picker("Workout", selection: $kind) { ForEach(DayKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) } }
                    if kind.isRun {
                        Stepper("Distance: \(Fmt.km(km)) km", value: $km, in: 0.5...50, step: 0.5)
                    }
                    Toggle("Skip this day", isOn: $skipped)
                }
                Section("Notes") {
                    TextField("How to do it", text: $note, axis: .vertical).lineLimit(2...6)
                }
                if original.edited {
                    Section {
                        Button("Reset to the plan", role: .destructive) { save(nil) }
                    }
                }
            }
            .navigationTitle("Edit day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(PlanDay(day: original.day, kind: kind, km: kind.isRun ? km : 0, detail: note, edited: true, skipped: skipped))
                    }
                }
            }
            .onAppear {
                kind = original.kind; km = max(original.km, 0.5); note = original.detail; skipped = original.skipped
            }
        }
    }

    func save(_ day: PlanDay?) {
        guard var race = model.settings.race else { return dismiss() }
        race.edits[original.day.iso] = day
        var s = model.settings
        s.race = race
        model.save(settings: s)
        dismiss()
    }
}

// MARK: - The full race plan, week by week

struct RacePlanView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: PlanDay?
    @State private var editingPlan = false

    var body: some View {
        if let s = model.settings.race {
            let plan = Coach.racePlan(s)
            let weeks = Dictionary(grouping: plan.days) { $0.day.monday }.sorted { $0.key < $1.key }
            List {
                if let w = plan.warning {
                    Label(w, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.warn)
                }
                ForEach(Array(weeks.enumerated()), id: \.element.key) { i, wk in
                    Section {
                        ForEach(wk.value) { d in
                            Button { editing = d } label: { PlanDayRow(d: d, status: Coach.status(d, data: model.data, today: model.today)) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        let km = wk.value.filter { $0.kind.isRun && !$0.skipped }.map(\.km).reduce(0, +)
                        Text("Week \(i + 1) · \(wk.key.text(.short)) · \(Fmt.km(km)) km")
                    }
                }
            }
            .navigationTitle("\(s.goal.label) plan")
            .toolbar { Button("Edit plan") { editingPlan = true } }
            .sheet(item: $editing) { DayEditor(original: $0) }
            .sheet(isPresented: $editingPlan) { RaceEditor() }
        } else {
            ContentUnavailableView("No race plan", systemImage: "flag.checkered", description: Text("Create one on the Running screen."))
        }
    }
}

struct PlanDayRow: View {
    var d: PlanDay
    var status: DayStatus

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: d.kind.symbol).frame(width: 24).foregroundStyle(d.kind == .rest ? Color.secondary : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(d.day.text(.weekday)) \(d.day.text(.dayNumber))").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(d.title).font(.subheadline.weight(d.kind == .rest ? .regular : .semibold))
                        .strikethrough(d.skipped)
                    if d.edited { Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("edited") }
                }
                if !d.detail.isEmpty, d.kind != .rest {
                    Text(d.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            StatusIcon(status: status)
        }
        .contentShape(Rectangle())
    }
}

struct StatusIcon: View {
    var status: DayStatus
    var body: some View {
        switch status {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good).accessibilityLabel("done")
        case .missed: Image(systemName: "xmark.circle").foregroundStyle(Theme.bad).accessibilityLabel("missed")
        case .today: Image(systemName: "circle.circle.fill").foregroundStyle(Theme.accent).accessibilityLabel("today")
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary).accessibilityLabel("skipped")
        case .upcoming: Image(systemName: "circle").foregroundStyle(.tertiary).accessibilityHidden(true)
        case .rest: Color.clear.frame(width: 16, height: 16).accessibilityHidden(true)
        }
    }
}

/// The race plan on the Running screen: countdown, today, this week
struct RacePlanCard: View {
    @EnvironmentObject var model: AppModel
    var r: RaceSummary
    var rest: Bool
    @State private var editing: PlanDay?

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR \(r.goal.uppercased()) PLAN").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(r.daysToGo == 0 ? "Race day!" : "\(r.daysToGo) days to go").font(.title3.bold())
                    Text("Race on \(r.raceDate.text(.long))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if r.planned > 0 {
                    VStack(alignment: .trailing) {
                        Text("\(r.done)/\(r.planned)").font(.headline)
                        Text("runs done").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let t = r.today {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Today: \(t.title)", systemImage: t.kind.symbol).font(.subheadline.bold())
                    if !t.detail.isEmpty { Text(t.detail).font(.caption).foregroundStyle(.secondary) }
                    if rest, t.kind.isRun, t.kind != .race {
                        Text("Today's call says rest. Tap the day to skip it or make it easier.").font(.caption).foregroundStyle(Theme.warn)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .onTapGesture { editing = t }
            }
            Text("This week").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(r.week) { d in
                Button { editing = d } label: { PlanDayRow(d: d, status: r.status[d.day.iso] ?? .upcoming) }.buttonStyle(.plain)
            }
            NavigationLink { RacePlanView() } label: {
                Label("See the whole plan, day by day", systemImage: "calendar").font(.subheadline.weight(.semibold))
            }
        }
        .sheet(item: $editing) { DayEditor(original: $0) }
    }
}
