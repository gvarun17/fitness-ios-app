import AppIntents
import FitnessCore
import SwiftUI
import WidgetKit

/// Widgets only read the snapshot the app saves in the shared App Group folder,
/// so they need no Apple Health access of their own. The app refreshes it (and
/// reloads the widgets) whenever Apple Health has new data.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    var metric: MetricKind = .steps
}

private func makeTimeline(_ metric: MetricKind = .steps) -> Timeline<SnapshotEntry> {
    let entry = SnapshotEntry(date: Date(), snapshot: SnapshotStore.shared.loadSnapshot(), metric: metric)
    // Check again in 30 minutes, in case the app refreshed in the background
    return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .preview) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .preview : SnapshotStore.shared.loadSnapshot() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(makeTimeline())
    }
}

struct MetricProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .preview) }

    func snapshot(for configuration: MetricIntent, in context: Context) async -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: context.isPreview ? .preview : SnapshotStore.shared.loadSnapshot() ?? .preview,
                      metric: configuration.metric)
    }

    func timeline(for configuration: MetricIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        makeTimeline(configuration.metric)
    }
}

// MARK: - Configurable metric

enum MetricKind: String, AppEnum, CaseIterable {
    case steps, exercise, activeEnergy, restingHR, hrv, sleep, weeklyGoal, streak, nextMilestone, sleepDebt, longestRun, readiness

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Metric" }
    static var caseDisplayRepresentations: [MetricKind: DisplayRepresentation] {
        [.steps: "Steps", .exercise: "Exercise minutes", .activeEnergy: "Active calories", .restingHR: "Resting heart rate",
         .hrv: "HRV", .sleep: "Sleep last night", .weeklyGoal: "Weekly goal", .streak: "Goal streak",
         .nextMilestone: "Next milestone", .sleepDebt: "Sleep debt", .longestRun: "Longest run", .readiness: "Today's call"]
    }
}

struct MetricIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Choose a metric" }
    static var description: IntentDescription { "Pick the number this widget shows." }

    @Parameter(title: "Metric", default: .steps)
    var metric: MetricKind

    init() {}
    init(_ metric: MetricKind) { self.metric = metric }
}

/// What a widget shows for one metric
struct MetricInfo {
    var title: String
    var value: String
    var unit = ""
    var symbol: String
    var color: Color
    var values: [Double?]? = nil        // last 7 days
    var progress: Double? = nil         // 0...1 for gauges
    var note = ""

    static func make(_ kind: MetricKind, _ s: Snapshot) -> MetricInfo {
        let t = s.stats, tr = s.trends
        func n(_ v: Double?) -> String { v.map { Fmt.number($0) } ?? "–" }
        switch kind {
        case .steps:
            return MetricInfo(title: "Steps", value: n(t.steps.map(Double.init)), symbol: "figure.walk", color: Theme.accent,
                              values: tr.steps, progress: t.steps.map { min(Double($0) / 10000, 1) }, note: "today")
        case .exercise:
            return MetricInfo(title: "Exercise", value: n(t.exerciseMinutes), unit: "min", symbol: "flame", color: Theme.good,
                              values: tr.exerciseMinutes, progress: t.exerciseMinutes.map { min($0 / 30, 1) }, note: "today")
        case .activeEnergy:
            return MetricInfo(title: "Active", value: n(t.activeKcal), unit: "kcal", symbol: "bolt.heart", color: Theme.run,
                              values: tr.activeKcal, note: "today")
        case .restingHR:
            return MetricInfo(title: "Resting HR", value: n(t.restingHR), unit: "bpm", symbol: "heart", color: Theme.bad,
                              values: tr.restingHR, note: "today")
        case .hrv:
            return MetricInfo(title: "HRV", value: n(t.hrv), unit: "ms", symbol: "waveform.path.ecg", color: Theme.accent,
                              values: tr.hrv, note: "last night")
        case .sleep:
            return MetricInfo(title: "Sleep", value: t.sleepHours.map { Fmt.hm(hours: $0) } ?? "–", symbol: "bed.double", color: .indigo,
                              values: tr.sleepHours, progress: t.sleepHours.map { min($0 / s.sleep.need, 1) }, note: "last night")
        case .weeklyGoal:
            let g = s.goal
            return MetricInfo(title: g.type.label, value: WeeklyGoal.text(g.value, g.type), unit: "/ \(WeeklyGoal.text(g.target, g.type))",
                              symbol: "target", color: g.reached ? Theme.good : Theme.accent, progress: g.progress, note: "this week")
        case .streak:
            return MetricInfo(title: "Goal streak", value: "\(s.goal.streak)", unit: s.goal.streak == 1 ? "week" : "weeks",
                              symbol: "flame.fill", color: Theme.warn, note: "best \(s.goal.best)")
        case .nextMilestone:
            let m = s.milestones
            return MetricInfo(title: m.nextStep.map { "Next: \($0.label)" } ?? "Ladder done", value: m.toGoKm.map { Fmt.km($0) } ?? "\(m.reachedCount)",
                              unit: m.toGoKm != nil ? "km to go" : "of \(m.steps.count)", symbol: "flag.checkered", color: Theme.accent,
                              progress: Double(m.reachedCount) / Double(m.steps.count), note: m.weeks.map { "about \($0) weeks" } ?? "")
        case .sleepDebt:
            let d = s.sleep.debtHours ?? 0
            return MetricInfo(title: "Sleep debt", value: d > 0 ? Fmt.hm(hours: d) : "None", symbol: "moon.zzz", color: d >= 2 ? Theme.warn : Theme.good,
                              values: tr.sleepHours, note: "last 7 days")
        case .longestRun:
            return MetricInfo(title: "Longest run", value: Fmt.km(s.milestones.longestKm), unit: "km", symbol: "figure.run", color: Theme.run,
                              note: s.milestones.longestDay.map { $0.text(.short) } ?? "")
        case .readiness:
            let r = s.readiness
            return MetricInfo(title: "Today's call", value: r.level?.short ?? "–", symbol: Theme.symbol(r.level), color: Theme.color(r.level),
                              note: r.level == nil ? "needs data" : "")
        }
    }
}
