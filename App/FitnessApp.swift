import FitnessCore
import SwiftUI

@main
struct FitnessApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task {
                    model.startWatching()
                    await model.refresh()
                }
                .onChange(of: phase) { _, now in
                    if now == .active { Task { await model.refresh() } }
                    if now == .background { model.scheduleBackgroundRefresh() }
                }
        }
        // iOS wakes the app now and then to sync Garmin in the background
        .backgroundTask(.appRefresh(AppModel.backgroundTask)) {
            await model.handleBackgroundRefresh()
        }
    }
}

enum Tab: String, Hashable { case today, training, health, settings }

struct RootView: View {
    @EnvironmentObject var model: AppModel
    // Launch argument -startTab training opens another tab (handy for testing)
    @State private var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .today

    var body: some View {
        if model.needsOnboarding {
            OnboardingView()
        } else {
            TabView(selection: $tab) {
                TodayView().tabItem { Label("Today", systemImage: "sun.max") }.tag(Tab.today)
                TrainingView().tabItem { Label("Running", systemImage: "figure.run") }.tag(Tab.training)
                HealthView().tabItem { Label("Health", systemImage: "heart.text.square") }.tag(Tab.health)
                SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(Tab.settings)
            }
            // Widgets open the matching tab: fitnesscoach://training
            .onOpenURL { url in
                let host = url.host() == "running" ? "training" : url.host() ?? ""      // fitnesscoach://running works too
                if let t = Tab(rawValue: host) { tab = t }
            }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "figure.run.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.accent)
            Text("Your coach, from first run to finish line").font(.largeTitle.bold())
            Text("Fitness Coach reads your workouts, steps, heart rate, HRV and sleep from Apple Health, from any watch that syncs there, and tells you how ready you are, what to run this week and how you're progressing. Garmin users can also connect Garmin directly in Settings for Body Battery, stress and more.")
                .foregroundStyle(.secondary)
            Label("Read-only, and your data never leaves this iPhone.", systemImage: "lock.shield")
                .font(.subheadline)
            Spacer()
            Button {
                Task { await model.connectAppleHealth() }
            } label: {
                Text("Connect Apple Health").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Button("Try it with demo data") { Task { await model.useDemo(true) } }
                .frame(maxWidth: .infinity)
            if let e = model.error { Text(e).font(.footnote).foregroundStyle(Theme.bad) }
        }
        .padding(24)
    }
}
