import Foundation
import RunCore

enum SettingsKey {
    static let unit = "unit"
    static let weeklyGoalMeters = "weeklyGoalMeters"
    static let weightKg = "weightKg"
    static let audioCues = "audioCues"
    static let cueEverySplits = "cueEverySplits"
    static let autoPause = "autoPause"
    static let countdown = "countdown"
    static let keepScreenOn = "keepScreenOn"
    static let appearance = "appearance"
    static let healthEnabled = "healthEnabled"
    static let defaultShoeID = "defaultShoeID"
    static let goalType = "goalType"
    static let goalDistanceMeters = "goalDistanceMeters"
    static let goalTimeSeconds = "goalTimeSeconds"
    static let goalPaceSecondsPerKm = "goalPaceSecondsPerKm"
    static let lastIntervalWorkout = "lastIntervalWorkout"
}

extension DistanceUnit {
    /// Kilometers for metric locales, miles otherwise.
    static var localeDefault: DistanceUnit {
        Locale.current.measurementSystem == .metric ? .kilometers : .miles
    }
}

/// Settings as read by non-view code. Views use @AppStorage with the same keys.
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            SettingsKey.unit: DistanceUnit.localeDefault.rawValue,
            SettingsKey.weeklyGoalMeters: 20_000.0,
            SettingsKey.weightKg: 70.0,
            SettingsKey.audioCues: true,
            SettingsKey.cueEverySplits: 1,
            SettingsKey.autoPause: true,
            SettingsKey.countdown: true,
            SettingsKey.keepScreenOn: true,
            SettingsKey.appearance: "dark",
            SettingsKey.healthEnabled: false,
            SettingsKey.defaultShoeID: "",
            SettingsKey.goalType: "distance",
            SettingsKey.goalDistanceMeters: 5000.0,
            SettingsKey.goalTimeSeconds: 1800.0,
            SettingsKey.goalPaceSecondsPerKm: 360.0
        ])
    }

    static var unit: DistanceUnit {
        DistanceUnit(rawValue: defaults.string(forKey: SettingsKey.unit) ?? "") ?? .localeDefault
    }
    static var weightKg: Double { defaults.double(forKey: SettingsKey.weightKg) }
    static var audioCues: Bool { defaults.bool(forKey: SettingsKey.audioCues) }
    static var cueEverySplits: Int { max(1, defaults.integer(forKey: SettingsKey.cueEverySplits)) }
    static var autoPause: Bool { defaults.bool(forKey: SettingsKey.autoPause) }
    static var countdown: Bool { defaults.bool(forKey: SettingsKey.countdown) }
    static var keepScreenOn: Bool { defaults.bool(forKey: SettingsKey.keepScreenOn) }
    static var healthEnabled: Bool { defaults.bool(forKey: SettingsKey.healthEnabled) }
}
