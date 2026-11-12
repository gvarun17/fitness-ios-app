# Stride

An iOS app for running, and only running. SwiftUI, iOS 17+, no third-party dependencies, no account, no backend: runs are stored on the device.

## Features

- **Live tracking**: GPS distance, time, current and average pace, elevation gain, calories, live route map. Keeps tracking with the screen locked.
- **Auto-pause**, manual pause/resume, and a hold-to-finish button.
- **Run types**: free run, goal run (distance, time or pace), and interval workouts (warm-up, repeats by time or distance, cool-down) with saved presets.
- **Audio cues**: spoken split updates, interval changes and goal progress that lower your music while they play.
- **History**: every run with a route thumbnail; detail view with map, splits, pace, elevation and heart-rate charts, tags, notes and effort.
- **Progress**: weekly/monthly/yearly totals, weekly goal, streaks, and personal records (1K to marathon) detected automatically.
- **Training plans**: 5K, 10K and half-marathon plans built back from your race date, with a "today" card that starts the workout in one tap.
- **Shoes**: per-shoe mileage with replacement warnings.
- **Apple Health** (optional): saves runs as workouts with routes; reads heart rate from a paired watch or strap.

## Running it

Requires Xcode 16 or later.

1. Open `Stride.xcodeproj`.
2. Select the **Stride** target, then **Signing & Capabilities**, and choose your team. Change the bundle identifier from `com.example.stride` if needed.
3. Run on an iPhone. GPS tracking needs a real device; in the simulator use **Features > Location > City Run** to simulate movement.

## Layout

| Path | What it is |
| --- | --- |
| `RunCore/` | Swift package with all run logic and no UI or Apple-framework dependencies: GPS filtering, distance, splits, auto-pause, best efforts, intervals, goals, stats, spoken text, plan generation. |
| `Stride/Services/` | Location, audio, HealthKit, the live `RunSession`, and saving runs. |
| `Stride/Models/` | SwiftData models: `Run`, `Shoe`, `PlanRecord`, `SavedWorkout`. |
| `Stride/Views/` | Screens, grouped by tab. |
| `Config/` | `Info.plist` (background modes, permission text) and entitlements. |

## Tests

The run logic is covered by unit tests in the package:

```sh
cd RunCore && swift test
```

In Xcode, choose the **RunCore** scheme and press Cmd-U.
