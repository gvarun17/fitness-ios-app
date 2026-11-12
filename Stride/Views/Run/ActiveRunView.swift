import SwiftUI
import SwiftData
import MapKit
import RunCore

struct ActiveRunView: View {
    let setup: RunSetup

    @StateObject private var session: RunSession
    @ObservedObject private var monitor = HeartRateMonitor.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var page = 0
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var savedRun: Run?
    @State private var showTooShort = false

    init(setup: RunSetup) {
        self.setup = setup
        _session = StateObject(wrappedValue: RunSession(setup: setup))
    }

    private var unit: DistanceUnit { session.unit }

    var body: some View {
        Group {
            if let savedRun {
                NavigationStack {
                    RunDetailView(run: savedRun, isNew: true)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    if case .countdown(let seconds) = session.phase {
                        countdown(seconds)
                    } else {
                        runScreen
                    }
                }
                .environment(\.colorScheme, .dark)
            }
        }
        .onAppear { session.start() }
        .alert("Run not saved", isPresented: $showTooShort) {
            Button("OK") { dismiss() }
        } message: {
            Text("That run was too short to record.")
        }
    }

    // MARK: Countdown

    private func countdown(_ seconds: Int) -> some View {
        VStack(spacing: 24) {
            HStack {
                Button {
                    session.cancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.bold))
                        .padding(12)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("Cancel run")
                Spacer()
            }
            .padding(.horizontal, 20)
            Spacer()
            Text("\(seconds)")
                .font(.system(size: 180, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .contentTransition(.numericText())
                .animation(.snappy, value: seconds)
            Text("Tap to start now")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 10) {
                gpsStatus
                sensorStatus
            }
            .padding(.bottom, 30)
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture { session.skipCountdown() }
    }

    private var gpsStatus: some View {
        let (text, color): (String, Color) = {
            if session.locationDenied { return ("Location access is off", .red) }
            guard let accuracy = session.gpsAccuracy else { return ("Finding GPS…", .yellow) }
            if accuracy <= 12 { return ("GPS strong", .green) }
            if accuracy <= 30 { return ("GPS fair", .yellow) }
            return ("GPS weak", .orange)
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sensorStatus: some View {
        if monitor.hasPairedSensor {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(session.heartRate == nil ? Color.yellow : Color.pink)
                Text(session.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "Looking for heart rate sensor…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Run screen

    private var runScreen: some View {
        VStack(spacing: 0) {
            HStack {
                gpsStatus
                Spacer()
                Picker("View", selection: $page) {
                    Image(systemName: "speedometer").tag(0)
                    Image(systemName: "map.fill").tag(1)
                    Image(systemName: "list.number").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            statusBanner
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Group {
                switch page {
                case 1: mapPage
                case 2: splitsPage
                default: metricsPage
                }
            }
            .frame(maxHeight: .infinity)

            controls
                .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if session.state == .autoPaused {
            banner("Auto-paused", "Start moving to resume", color: .yellow, fraction: nil)
        } else if session.state == .paused {
            banner("Paused", "Resume or hold Finish to end", color: .yellow, fraction: nil)
        } else if let interval = session.interval {
            if let step = interval.currentStep {
                let remaining: String = {
                    switch step.measure {
                    case .time: return Fmt.duration(interval.remaining.rounded(.up))
                    case .distance: return "\(Int(interval.remaining.rounded())) m"
                    }
                }()
                let title = step.kind == .run && session.totalRunSteps > 1
                    ? "Run \(interval.currentRepeat)/\(session.totalRunSteps)" : step.kind.title
                HStack(spacing: 10) {
                    banner(title, "\(remaining) left", color: step.kind.color, fraction: interval.fraction)
                    Button {
                        session.skipIntervalStep()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .padding(14)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .accessibilityLabel("Skip to next step")
                }
            } else {
                banner("Workout complete", "Keep going or finish", color: .green, fraction: 1)
            }
        } else if let goal = session.goal {
            switch goal.goal {
            case .pace(let target):
                let delta = GoalProgress.paceDelta(target: target, elapsed: session.elapsed, distance: session.distance)
                let text: String = {
                    guard let delta else { return "Settling in" }
                    let perUnit = Int((delta * unit.meters).rounded())
                    if abs(perUnit) < 3 { return "On target" }
                    return perUnit < 0 ? "\(-perUnit)s ahead" : "\(perUnit)s behind"
                }()
                banner("Target \(Describe.goal(goal.goal, unit: unit))", text,
                       color: (delta ?? 0) <= 0 ? .green : .orange, fraction: nil)
            default:
                banner(goal.isComplete ? "Goal reached" : "Goal \(Describe.goal(goal.goal, unit: unit))",
                       "\(Int((goal.fraction * 100).rounded(.down)))%", color: .accentColor, fraction: goal.fraction)
            }
        }
    }

    private func banner(_ title: String, _ detail: String, color: Color, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text(detail)
                    .font(.headline)
                    .monospacedDigit()
            }
            if let fraction {
                ProgressView(value: min(1, max(0, fraction)))
                    .tint(color)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var metricsPage: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text(Fmt.distance(session.distance, unit: unit))
                    .font(.system(size: 104, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit == .kilometers ? "KILOMETERS" : "MILES")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack {
                MetricView(value: Fmt.duration(session.elapsed), label: "Time", size: 34)
                MetricView(value: Fmt.pace(secondsPerMeter: session.currentPace, unit: unit), label: "Pace", size: 34)
            }
            HStack {
                MetricView(value: Fmt.pace(secondsPerMeter: session.averagePace, unit: unit), label: "Avg pace")
                MetricView(value: Fmt.elevation(session.elevationGain, unit: unit), label: "Climb")
                if let bpm = session.heartRate {
                    MetricView(value: "\(Int(bpm.rounded()))", label: session.heartRateZone.map { "BPM · Zone \($0)" } ?? "BPM")
                } else {
                    MetricView(value: "\(Int(session.calories.rounded()))", label: "Kcal")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var mapPage: some View {
        VStack(spacing: 12) {
            Map(position: $camera) {
                UserAnnotation()
                if session.route.count > 1 {
                    MapPolyline(coordinates: session.route)
                        .stroke(Color.accentColor, lineWidth: 5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack {
                MetricView(value: Fmt.distance(session.distance, unit: unit), label: unit.abbreviation)
                MetricView(value: Fmt.duration(session.elapsed), label: "Time")
                MetricView(value: Fmt.pace(secondsPerMeter: session.currentPace, unit: unit), label: "Pace")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var splitsPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text(unit.abbreviation.uppercased()).frame(width: 50, alignment: .leading)
                    Text("PACE").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CLIMB").frame(width: 70, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)

                if session.splits.isEmpty {
                    Text("Splits appear here after your first \(unit.singular).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
                ForEach(session.splits.reversed()) { split in
                    HStack {
                        Text("\(split.index)").frame(width: 50, alignment: .leading)
                        Text(Fmt.pace(secondsPerMeter: split.secondsPerMeter, unit: unit))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.elevation(split.elevationChange, unit: unit))
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .padding(.vertical, 10)
                    Divider().overlay(Color.white.opacity(0.15))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 44) {
            if session.state == .running {
                Button {
                    session.pause()
                } label: {
                    controlLabel("pause.fill", color: .white, foreground: .black)
                }
                .accessibilityLabel("Pause")
            } else {
                HoldToFinishButton(action: finish)
                Button {
                    session.resume()
                } label: {
                    controlLabel("play.fill", color: .accentColor, foreground: .black)
                }
                .accessibilityLabel("Resume")
            }
        }
        .animation(.snappy, value: session.state == .running)
    }

    private func controlLabel(_ symbol: String, color: Color, foreground: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 92, height: 92)
            .background(color, in: Circle())
    }

    private func finish() {
        guard let finished = session.finish(), finished.distance >= 20 else {
            showTooShort = true
            return
        }
        savedRun = RunStore.save(finished, in: context)
    }
}

/// Ends the run only after being held, so a stray tap can't stop it.
struct HoldToFinishButton: View {
    var action: () -> Void

    @State private var progress = 0.0
    private let holdDuration = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            VStack(spacing: 2) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 28, weight: .bold))
                Text("HOLD")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 92, height: 92)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 60) {
            progress = 0
            action()
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: holdDuration) : .easeOut(duration: 0.2)) {
                progress = pressing ? 1 : 0
            }
        }
        .accessibilityLabel("Finish run")
        .accessibilityHint("Touch and hold to end the run")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
