import FitnessCore
import SwiftUI

/// Colours and small views shared by the app and the widgets.
enum Theme {
    static let accent = Color(red: 0.22, green: 0.53, blue: 0.90)
    static let good = Color(red: 0.05, green: 0.64, blue: 0.05)
    static let warn = Color(red: 0.88, green: 0.64, blue: 0.11)
    static let bad = Color(red: 0.90, green: 0.40, blue: 0.40)
    static let run = Color(red: 0.85, green: 0.35, blue: 0.15)

    static func color(_ s: SignalState) -> Color {
        switch s {
        case .good: good
        case .ok: warn
        case .poor: bad
        case .none: .secondary
        }
    }

    static func color(_ l: ReadinessLevel?) -> Color {
        switch l {
        case .go: good
        case .easy: warn
        case .rest: bad
        case nil: .secondary
        }
    }

    /// An icon as well as a colour, so the state never depends on colour alone
    static func symbol(_ s: SignalState) -> String {
        switch s {
        case .good: "checkmark.circle.fill"
        case .ok: "minus.circle.fill"
        case .poor: "exclamationmark.circle.fill"
        case .none: "circle.dotted"
        }
    }

    static func symbol(_ l: ReadinessLevel?) -> String {
        switch l {
        case .go: "checkmark.circle.fill"
        case .easy: "minus.circle.fill"
        case .rest: "exclamationmark.circle.fill"
        case nil: "questionmark.circle"
        }
    }

    static func sport(_ s: Sport) -> Color {
        switch s {
        case .run: run
        case .walk: accent
        case .cycle: Color(red: 0.10, green: 0.62, blue: 0.44)
        case .swim: Color(red: 0.79, green: 0.52, blue: 0.0)
        case .hike: Color(red: 0.84, green: 0.32, blue: 0.51)
        case .strength: Color(red: 0.0, green: 0.51, blue: 0.0)
        case .other: Color(red: 0.56, green: 0.52, blue: 0.91)
        }
    }
}

/// A progress ring with a value in the middle
struct Ring<Center: View>: View {
    var progress: Double
    var color: Color = Theme.accent
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
    }
}

/// Seven small bars for the last 7 days (today on the right)
struct MiniBars: View {
    var values: [Double?]
    var color: Color = Theme.accent
    var target: Double? = nil

    var body: some View {
        let top = max(values.compactMap { $0 }.max() ?? 0, target ?? 0, 1)
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    let v = values[i] ?? 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == values.count - 1 ? color : color.opacity(0.45))
                        .frame(height: max(2, g.size.height * v / top))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Label + icon showing a signal's state
struct StateIcon: View {
    var state: SignalState
    var body: some View {
        Image(systemName: Theme.symbol(state))
            .foregroundStyle(Theme.color(state))
            .accessibilityLabel(state == .none ? "no data" : state.rawValue)
    }
}

extension Snapshot {
    /// Placeholder for widget galleries and previews: made-up data, clearly demo
    static var preview: Snapshot {
        let today = Day(date: Date())
        return Coach.snapshot(DemoData.make(today: today), settings: UserSettings(name: "Alex"), today: today, isDemo: true)
    }
}

extension Day {
    enum Style { case long, short, weekday }

    /// "Friday 6 November", "6 Nov" or "Fri", in the user's language. A Day's
    /// date is midnight UTC, so it's formatted in UTC.
    func text(_ style: Style) -> String {
        var f = Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!)
        switch style {
        case .long: f = f.weekday(.wide).day().month(.wide)
        case .short: f = f.day().month(.abbreviated)
        case .weekday: f = f.weekday(.abbreviated)
        }
        return date.formatted(f)
    }
}
