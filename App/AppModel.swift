import BackgroundTasks
import FitnessCore
import Foundation
import SwiftUI
import WidgetKit

/// The app's state: settings, the data from Apple Health and/or Garmin (or
/// demo data) and the snapshot worked out from it. Every refresh saves the
/// snapshot for the widgets.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings: UserSettings
    @Published private(set) var data = HealthData()
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var loading = false
    @Published var error: String?
    @Published private(set) var garminConnected = GarminKey.isSet
    @Published private(set) var garminSynced: Date?
    @Published private(set) var garminStatus: String?
    @AppStorage("demoMode") var demoMode = false
    @AppStorage("connected") var connected = false

    static let backgroundTask = "com.gvarun17.fitness.refresh"
    private let health = HealthKitService()
    let garmin = GarminService()
    private let store = SnapshotStore.shared
    private var watching = false
    private var apple = HealthData()

    init() {
        settings = SnapshotStore.shared.loadSettings()
        snapshot = SnapshotStore.shared.loadSnapshot()
    }

    var needsOnboarding: Bool { !connected && !demoMode && !garminConnected }
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

    /// Checks the key with Garmin, then keeps it in the Keychain. Returns an
    /// error message for the Settings screen, or nil when it worked.
    func connectGarmin(key raw: String) async -> String? {
        let key = GarminKey.clean(raw)
        guard !key.isEmpty else { return "Please paste your Garmin Personal API key." }
        do {
            try await GarminService.check(key)
        } catch {
            return error.localizedDescription
        }
        guard GarminKey.save(key) else { return "Couldn't save the key in the Keychain." }
        garminConnected = true
        demoMode = false
        await refresh(forceGarmin: true)
        scheduleBackgroundRefresh()
        return nil
    }

    func disconnectGarmin() async {
        GarminKey.delete()
        await garmin.forget()
        garminConnected = false
        garminSynced = nil
        garminStatus = nil
        await refresh()
    }

    func useDemo(_ on: Bool) async {
        demoMode = on
        await refresh()
    }

    func startWatching() {
        guard connected, !watching else { return }
        watching = true
        health.watchForChanges { [weak self] in await self?.refresh(garminToo: false) }
    }

    /// Reads Apple Health, syncs Garmin (at most every 15 minutes unless forced)
    /// and merges the two: Garmin first, Apple Health filling the gaps.
    func refresh(forceGarmin: Bool = false, garminToo: Bool = true) async {
        loading = true
        defer { loading = false }
        if demoMode {
            data = DemoData.make(today: today)
            error = nil
            publish()
            return
        }
        if connected {
            do { apple = try await health.load() } catch { self.error = "Couldn't read Apple Health: \(error.localizedDescription)" }
        }
        var g = await garmin.data
        garminSynced = await garmin.lastSync
        if garminConnected, garminToo, forceGarmin || (garminSynced.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true) {
            garminStatus = "Syncing with Garmin…"
            do {
                g = try await garmin.sync(today: today)
                garminSynced = await garmin.lastSync
                garminStatus = nil
            } catch {
                garminStatus = "Garmin sync failed: \(error.localizedDescription)"
            }
        }
        guard connected || g != nil else { return }
        data = HealthData.merge(apple: apple, garmin: garminConnected ? g : nil)
        publish()
    }

    /// Graphs for one workout: from the download, or fetched from Garmin now
    func detail(for w: Workout) async -> WorkoutDetail? {
        if let d = data.workoutDetails[w.id] { return d }
        guard w.isGarmin, garminConnected else { return nil }
        let d = await garmin.detail(for: w)
        if let d { data.workoutDetails[w.id] = d }
        return d
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

    // MARK: Background refresh

    /// Asks iOS to wake the app every few hours to sync Garmin. iOS decides
    /// exactly when, based on how you use the phone.
    func scheduleBackgroundRefresh() {
        guard garminConnected else { return }
        let r = BGAppRefreshTaskRequest(identifier: Self.backgroundTask)
        r.earliestBeginDate = Date().addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(r)
    }

    func handleBackgroundRefresh() async {
        scheduleBackgroundRefresh()
        await refresh(forceGarmin: true)
    }
}
