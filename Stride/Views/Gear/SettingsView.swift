import SwiftUI
import RunCore

struct SettingsView: View {
    @AppStorage(SettingsKey.unit) private var unit: DistanceUnit = .localeDefault
    @AppStorage(SettingsKey.weeklyGoalMeters) private var weeklyGoal = 20_000.0
    @AppStorage(SettingsKey.weightKg) private var weightKg = 70.0
    @AppStorage(SettingsKey.audioCues) private var audioCues = true
    @AppStorage(SettingsKey.cueEverySplits) private var cueEverySplits = 1
    @AppStorage(SettingsKey.autoPause) private var autoPause = true
    @AppStorage(SettingsKey.countdown) private var countdown = true
    @AppStorage(SettingsKey.keepScreenOn) private var keepScreenOn = true
    @AppStorage(SettingsKey.appearance) private var appearance = "dark"
    @AppStorage(SettingsKey.healthEnabled) private var healthEnabled = false
    @AppStorage(SettingsKey.maxHeartRate) private var maxHeartRate = 190.0
    @ObservedObject private var monitor = HeartRateMonitor.shared
    @State private var healthUnavailable = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Gear") {
                    NavigationLink {
                        ShoesView()
                    } label: {
                        Label("Shoes", systemImage: "shoe.fill")
                    }
                }

                Section {
                    NavigationLink {
                        SensorsView()
                    } label: {
                        LabeledContent {
                            Text(monitor.pairedName ?? "Not set up")
                        } label: {
                            Label("Sensor", systemImage: "heart.fill")
                        }
                    }
                    Stepper(value: $maxHeartRate, in: 120...230, step: 1) {
                        LabeledContent("Max heart rate", value: "\(Int(maxHeartRate)) bpm")
                    }
                } header: {
                    Text("Heart rate")
                } footer: {
                    Text("Connect a chest strap such as a Polar H10, or a watch that broadcasts heart rate. Max heart rate sets your training zones; 220 minus your age is a rough starting point.")
                }

                Section {
                    Picker("Distance", selection: $unit) {
                        Text("Kilometers").tag(DistanceUnit.kilometers)
                        Text("Miles").tag(DistanceUnit.miles)
                    }
                    Stepper {
                        LabeledContent("Weekly goal", value: "\(Fmt.distance(weeklyGoal, unit: unit, decimals: 0)) \(unit.abbreviation)")
                    } onIncrement: {
                        weeklyGoal = min(300, (weeklyGoal / unit.meters).rounded() + 5) * unit.meters
                    } onDecrement: {
                        weeklyGoal = max(5, (weeklyGoal / unit.meters).rounded() - 5) * unit.meters
                    }
                    Stepper(value: $weightKg, in: 30...200, step: 1) {
                        LabeledContent("Weight", value: unit == .kilometers
                                       ? "\(Int(weightKg)) kg"
                                       : "\(Int((weightKg * 2.20462).rounded())) lb")
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text("Weight is only used to estimate calories.")
                }

                Section {
                    Toggle("Audio cues", isOn: $audioCues)
                    if audioCues {
                        Picker("Announce", selection: $cueEverySplits) {
                            Text("Every \(unit.singular)").tag(1)
                            Text("Every 2 \(unit.plural)").tag(2)
                            Text("Every 5 \(unit.plural)").tag(5)
                        }
                    }
                    Toggle("Auto-pause", isOn: $autoPause)
                    Toggle("3-second countdown", isOn: $countdown)
                    Toggle("Keep screen on", isOn: $keepScreenOn)
                } header: {
                    Text("During a run")
                } footer: {
                    Text("Audio cues speak your distance, time and pace, and lower your music while they play. Interval and goal announcements follow the same switch.")
                }

                Section {
                    Toggle("Apple Health", isOn: $healthEnabled)
                } footer: {
                    Text("Saves each run as a workout with its route and heart rate. Without a Bluetooth sensor, heart rate is read from Health instead.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("Match System").tag("system")
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                } footer: {
                    Text("Your runs are stored on this device only.")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: healthEnabled) {
                guard healthEnabled else { return }
                Task {
                    let granted = await HealthService.shared.requestAuthorization()
                    if !granted {
                        healthEnabled = false
                        healthUnavailable = true
                    }
                }
            }
            .alert("Apple Health isn't available", isPresented: $healthUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Health data can't be used on this device right now.")
            }
        }
    }
}
