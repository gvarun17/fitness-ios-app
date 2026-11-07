import FitnessCore
import Foundation
import SwiftUI
import WidgetKit

/// The app's state: settings, the data from Apple Health (or demo data) and the
/// snapshot worked out from it. Every refresh saves the snapshot for the widgets.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: UserSettings
    @Published private(set) var data = HealthData()
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var loading = false
    @Published var error: String?
    @AppStorage("demoMode") var demoMode = false
    @AppStorage("connected") var connected = false

    private let health = HealthKitService()
    private let store = SnapshotStore.shared
    private var watching = false

    init() {
        settings = SnapshotStore.shared.loadSettings()
        snapshot = SnapshotStore.shared.loadSnapshot()
    }

    var needsOnboarding: Bool { !connected && !demoMode }
    var today: Day { Day(date: Date()) }

    func connectAppleHealth() async {
        guard HealthKitService.isAvailable else {
            error = "Apple Health isn't available on this device."
            return
        }
        do {
            try await health.requestAccess()
            connected = true
            demoMode = false
            await refresh()
            startWatching()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func useDemo(_ on: Bool) async {
        demoMode = on
        await refresh()
    }

    func startWatching() {
        guard connected, !watching else { return }
        watching = true
        health.watchForChanges { [weak self] in await self?.refresh() }
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            if demoMode {
                data = DemoData.make(today: today)
            } else if connected {
                data = try await health.load()
            } else {
                return
            }
            error = nil
            publish()
        } catch {
            self.error = "Couldn't read Apple Health: \(error.localizedDescription)"
        }
    }

    func save(settings new: UserSettings) {
        settings = new
        try? store.save(new)
        publish()
    }

    private func publish() {
        let s = Coach.snapshot(data, settings: settings, today: today, isDemo: demoMode)
        snapshot = s
        try? store.save(s)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
