import SwiftUI
import RunCore

/// Rounded panel used to group content.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A labelled number, e.g. "5:07 / AVG PACE".
struct MetricView: View {
    var value: String
    var label: String
    var size: CGFloat = 26

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SectionTitle: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Draws a normalized route ([x0, y0, x1, y1, ...] in the unit square) without map tiles.
struct RouteShape: Shape {
    var points: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 4 else { return path }
        let side = min(rect.width, rect.height)
        let originX = rect.midX - side / 2
        let originY = rect.midY - side / 2
        var index = 0
        while index + 1 < points.count {
            let point = CGPoint(x: originX + points[index] * side, y: originY + points[index + 1] * side)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
            index += 2
        }
        return path
    }
}

struct RouteThumbnailView: View {
    var points: [Double]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            if points.count >= 4 {
                RouteShape(points: points)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .padding(9)
            } else {
                Image(systemName: "figure.run")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TagBadge: View {
    var tag: RunTag

    var body: some View {
        Text(tag.title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tag.color.opacity(0.2), in: Capsule())
            .foregroundStyle(tag.color)
    }
}

/// Circular progress ring with content in the middle.
struct ProgressRing<Content: View>: View {
    var fraction: Double
    var lineWidth: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
    }
}

extension StepKind {
    var color: Color {
        switch self {
        case .warmup: return .yellow
        case .run: return .accentColor
        case .recover: return .green
        case .cooldown: return .blue
        }
    }
}

extension PlannedWorkoutKind {
    var color: Color {
        switch self {
        case .easy: return .green
        case .long: return .blue
        case .tempo: return .orange
        case .intervals: return .purple
        case .race: return .red
        }
    }

    var runTag: RunTag {
        switch self {
        case .easy: return .easy
        case .long: return .long
        case .tempo: return .tempo
        case .intervals: return .intervals
        case .race: return .race
        }
    }
}

enum Describe {
    /// "400 m", "1.5 km", "2:00".
    static func measure(_ measure: StepMeasure, unit: DistanceUnit) -> String {
        switch measure {
        case .time(let seconds):
            return Fmt.duration(seconds)
        case .distance(let meters):
            if meters < 1000 { return "\(Int(meters.rounded())) m" }
            return "\(Fmt.distance(meters, unit: unit, decimals: 1)) \(unit.abbreviation)"
        }
    }

    static func workout(_ workout: IntervalWorkout, unit: DistanceUnit) -> String {
        var parts: [String] = []
        if let warm = workout.steps.first(where: { $0.kind == .warmup }) {
            parts.append("\(measure(warm.measure, unit: unit)) warm-up")
        }
        if let run = workout.steps.first(where: { $0.kind == .run }) {
            var text = "\(workout.runStepCount) x \(measure(run.measure, unit: unit))"
            if let recover = workout.steps.first(where: { $0.kind == .recover }) {
                text += " / \(measure(recover.measure, unit: unit)) recovery"
            }
            parts.append(text)
        }
        if let cool = workout.steps.first(where: { $0.kind == .cooldown }) {
            parts.append("\(measure(cool.measure, unit: unit)) cool-down")
        }
        return parts.joined(separator: " · ")
    }

    static func goal(_ goal: RunGoal, unit: DistanceUnit) -> String {
        switch goal {
        case .distance(let meters):
            return "\(Fmt.distance(meters, unit: unit, decimals: 1)) \(unit.abbreviation)"
        case .time(let seconds):
            return Fmt.duration(seconds)
        case .pace(let pace):
            return "\(Fmt.pace(secondsPerMeter: pace, unit: unit)) /\(unit.abbreviation)"
        }
    }
}
