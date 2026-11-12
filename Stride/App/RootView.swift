import SwiftUI

struct RootView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = "dark"
    @State private var activeSetup: RunSetup?

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some View {
        TabView {
            RunHomeView(start: { activeSetup = $0 })
                .tabItem { Label("Run", systemImage: "figure.run") }
            HistoryView()
                .tabItem { Label("Activity", systemImage: "list.bullet") }
            StatsView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
            PlanView(start: { activeSetup = $0 })
                .tabItem { Label("Plan", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .fullScreenCover(item: $activeSetup) { setup in
            ActiveRunView(setup: setup)
                .preferredColorScheme(colorScheme)
        }
        .preferredColorScheme(colorScheme)
    }
}
