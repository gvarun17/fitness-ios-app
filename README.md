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
- **Heart rate sensors**: connects directly over Bluetooth to a chest strap (Polar H10 and similar) or a watch broadcasting heart rate (Garmin), with live zones, auto-reconnect and time-in-zone after the run.
- **Garmin import**: paste a Garmin Connect Personal API key to import your running history (routes, pace, heart rate, elevation) from Garmin's activity files, or import `.fit` files directly. The key is kept in the Keychain.
- **Apple Health** (optional): saves runs as workouts with routes and heart rate; reads heart rate from Health when no Bluetooth sensor is connected.

## Running it

Requires Xcode 16 or later.

1. Open `Stride.xcodeproj`.
2. Select the **Stride** target, then **Signing & Capabilities**, and choose your team. Change the bundle identifier from `com.example.stride` if needed.
3. Run on an iPhone. GPS tracking needs a real device; in the simulator use **Features > Location > City Run** to simulate movement.

## Layout

| Path | What it is |
| --- | --- |
| `RunCore/` | Swift package with all run logic and no UI or Apple-framework dependencies: GPS filtering, distance, splits, auto-pause, best efforts, intervals, goals, stats, spoken text, plan generation, heart-rate decoding, FIT file decoding and Garmin API request building. |
| `Stride/Services/` | Location, audio, Bluetooth heart rate, HealthKit, the live `RunSession`, and saving runs. |
| `Stride/Models/` | SwiftData models: `Run`, `Shoe`, `PlanRecord`, `SavedWorkout`. |
| `Stride/Views/` | Screens, grouped by tab. |
| `Config/` | `Info.plist` (background modes, permission text) and entitlements. |

## Tests

The run logic is covered by unit tests in the package:

```sh
cd RunCore && swift test
```

In Xcode, choose the **RunCore** scheme and press Cmd-U.
