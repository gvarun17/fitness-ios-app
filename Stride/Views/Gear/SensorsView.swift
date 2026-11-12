import SwiftUI

/// Pair and manage a Bluetooth heart rate sensor.
struct SensorsView: View {
    @ObservedObject private var monitor = HeartRateMonitor.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            if monitor.status == .bluetoothOff || monitor.status == .unauthorized {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(monitor.status == .unauthorized ? "Bluetooth access is off" : "Bluetooth is off",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(monitor.status == .unauthorized
                             ? "Allow Bluetooth for Stride in Settings to connect a heart rate sensor."
                             : "Turn on Bluetooth to connect a heart rate sensor.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if monitor.status == .unauthorized {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                }
            }

            if let name = monitor.pairedName {
                Section("Your sensor") {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(.headline)
                            Text(statusText)
                                .font(.subheadline)
                                .foregroundStyle(monitor.status == .connected ? Color.green : Color.secondary)
                        }
                        Spacer()
                        if let bpm = monitor.heartRate {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)
                                Text("\(Int(bpm.rounded()))")
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(Int(bpm.rounded())) beats per minute")
                        }
                    }
                    if let battery = monitor.batteryLevel {
                        LabeledContent("Battery", value: "\(battery)%")
                    }
                    Button("Forget Sensor", role: .destructive) {
                        monitor.forget()
                    }
                }
            }

            Section {
                if monitor.found.isEmpty {
                    HStack(spacing: 10) {
                        if monitor.isScanning { ProgressView() }
                        Text(monitor.isScanning ? "Looking for sensors…" : "No sensors found")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(monitor.found) { sensor in
                    Button {
                        monitor.connect(sensor)
                    } label: {
                        HStack {
                            Text(sensor.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: sensor.rssi > -65 ? "wifi" : "wifi.exclamationmark")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(sensor.rssi > -65 ? "Strong signal" : "Weak signal")
                            Text("Connect")
                                .fontWeight(.semibold)
                        }
                    }
                }
                if !monitor.isScanning {
                    Button("Search Again") { monitor.startScan() }
                }
            } header: {
                Text("Nearby sensors")
            } footer: {
                Text("Sensors only appear while they are awake and transmitting.")
            }

            Section("Polar H10 and other chest straps") {
                Text("Moisten the electrodes and put the strap on. It switches on when it touches your skin and should appear above within a few seconds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Garmin watches") {
                Text("On the watch, turn on Broadcast Heart Rate (in the heart rate or sensor settings; the exact menu depends on the model). Many models can also broadcast automatically during an activity. The watch then appears above like a chest strap.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Heart Rate Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { monitor.startScan() }
        .onDisappear { monitor.stopScan() }
    }

    private var statusText: String {
        switch monitor.status {
        case .connected: return monitor.heartRate == nil ? "Connected, waiting for a reading" : "Connected"
        case .connecting: return "Searching… wear the sensor to wake it"
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth access is off"
        case .idle, .ready: return "Not connected"
        }
    }
}
