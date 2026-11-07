import FitnessCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var name = ""
    @State private var goalType = GoalType.minutes
    @State private var goalText = ""
    @State private var sleepNeed = 8.0
    @State private var message: String?
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $name)
                        .textContentType(.givenName).autocorrectionDisabled().focused($editing)
                        .submitLabel(.done).onSubmit(save)
                }
                Section {
                    Picker("Count", selection: $goalType) {
                        ForEach(GoalType.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Suggested: \(Int(goalType.suggested)) \(goalType.unit)", text: $goalText)
                        .keyboardType(.decimalPad).focused($editing)
                    Stepper("Sleep target: \(Fmt.hm(hours: sleepNeed))", value: $sleepNeed, in: 6...10, step: 0.25)
                } header: { Text("Weekly goal") } footer: {
                    Text("Counted Monday to Sunday. Leave the number empty for the suggested target. A runs goal also sets how many runs your plan has each week.")
                }
                Section {
                    Button("Save") { save() }
                    if let message { Text(message).font(.footnote).foregroundStyle(message.hasPrefix("Saved") ? Theme.good : Theme.bad) }
                }
                Section {
                    if model.connected {
                        Label("Connected to Apple Health", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                    } else {
                        Button("Connect Apple Health") { Task { await model.connectAppleHealth() } }
                    }
                    Toggle("Show demo data", isOn: Binding(get: { model.demoMode }, set: { on in Task { await model.useDemo(on) } }))
                } header: { Text("Data") } footer: {
                    Text("Reads workouts, steps, heart rate, HRV and sleep from Apple Health: from Apple Watch, Garmin, Coros, Polar, Oura or any app that syncs there. Read-only, and nothing leaves this iPhone. To change what's shared: Settings › Health › Data Access & Devices › Fitness Coach.")
                }
                Section("Widgets") {
                    Text("Touch and hold your Home Screen or Lock Screen, tap Edit › Add Widget, and search for Fitness Coach. The Metric widget can show any single number: tap it while editing to choose which.")
                        .font(.footnote)
                }
                Section {
                    Text("Fitness Coach gives general guidance from your watch data. It isn't medical advice. Talk to a doctor before starting a new training programme, or if something feels wrong.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: load)
        }
    }

    func load() {
        name = model.settings.name
        goalType = model.settings.goalType
        goalText = model.settings.goalValue.map { $0.rounded() == $0 ? "\(Int($0))" : "\($0)" } ?? ""
        sleepNeed = model.settings.sleepNeedHours
    }

    func save() {
        editing = false                 // close the keyboard so the last typing is committed first
        Task { @MainActor in
            await Task.yield()
            store()
        }
    }

    func store() {
        do {
            let value = try UserSettings.cleanGoal(goalType, goalText)
            model.save(settings: UserSettings(name: name.trimmingCharacters(in: .whitespaces), goalType: goalType,
                                              goalValue: value, sleepNeedHours: sleepNeed))
            message = "Saved."
        } catch {
            message = error.localizedDescription
        }
    }
}
