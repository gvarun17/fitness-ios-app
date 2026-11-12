import SwiftUI
import SwiftData

@main
struct StrideApp: App {
    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Run.self, Shoe.self, PlanRecord.self, SavedWorkout.self])
    }
}
