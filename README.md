# Fitness Coach (iPhone)

An iPhone app and Home Screen / Lock Screen widgets that coach you from your
first run to an Ironman, using the data in **Apple Health**: from Apple Watch,
Garmin, Coros, Polar, Oura or any app that syncs there.

**No servers. Read-only. Your data never leaves the iPhone.**

## What it does

| Screen | What you see |
|---|---|
| **Today** | Today's call (train, take it easy or rest) from last night's HRV, sleep, resting heart rate and your training load; steps, exercise, calories, resting HR, HRV and sleep with 7-day bars; new personal bests; today's workouts (tap one for details). |
| **Training** | Weekly goal ring and streak; a training plan toward your next milestone (easy runs plus a long run growing ~10% a week, run-walk intervals while runs are short, an easier week every 4th); the milestone ladder from first run to Ironman; running form charts (pace, cadence, stride, metres per heartbeat); personal bests and firsts. |
| **Health** | Sleep insights for the last 2 weeks (average vs your target, sleep debt, bedtime consistency, a chart of when you slept, tips) and trend charts for steps, resting HR, HRV, sleep, exercise and active calories over 1M / 3M / 6M / 1Y. |
| **Settings** | Your name, weekly goal (exercise minutes, distance, running distance or number of runs), sleep target, Apple Health connection, demo data. |

### Widgets

| Widget | Sizes | Shows |
|---|---|---|
| **Today's call** | Small, Medium, Lock Screen (circle, rectangle, inline) | Train / easy / rest, with each signal |
| **Metric** (you choose) | Small, Lock Screen (circle, rectangle, inline) | Any one of: steps, exercise minutes, active calories, resting HR, HRV, sleep, weekly goal, goal streak, next milestone, sleep debt, longest run, today's call |
| **Weekly goal** | Small, Lock Screen (circle, rectangle) | Ring with progress and streak |
| **Training plan** | Medium, Large | This week's runs, ticked off as you go; Large adds the next 4 weeks |
| **Sleep** | Small, Medium, Lock Screen (rectangle) | Last night, 7-night bars, sleep debt, usual bedtime |
| **Overview** | Medium, Large | Today's call, key numbers, goal, next milestone, last workout |
| **Next milestone** | Small, Lock Screen (rectangle) | Next step and how far to go |
| **Last workout** | Small, Medium | Latest workout, its numbers and any personal bests |

To add one: touch and hold the Home Screen or Lock Screen › **Edit** › **Add
Widget** › search **Fitness Coach**. For the Metric widget, tap it while editing
to choose what it shows. Tapping a widget opens the matching screen.

## Getting it running

You need a Mac with **Xcode** (free from the Mac App Store, iOS 17 SDK or newer).

1. Install Xcode, open it once to finish setup, then in Terminal:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   ```
2. Open `Fitness.xcodeproj`.
3. Select the **Fitness** project › each target (**Fitness** and **FitnessWidgets**) ›
   **Signing & Capabilities** › choose your **Team** (sign in with your Apple ID
   in Xcode › Settings › Accounts if the list is empty).
   - The bundle IDs (`com.gvarun17.fitness`, `.widgets`) and the App Group
     (`group.com.gvarun17.fitness`) must be unique to your account. If Xcode
     complains, change them in `project.yml` and `SnapshotStore.appGroup`, then run
     `xcodegen`.
   - If Xcode says a capability (HealthKit, App Groups, background delivery) isn't
     available for a **Personal Team**, you need the paid Apple Developer Program
     ($99/year), which you'll need for TestFlight and the App Store anyway.
4. **Simulator:** pick an iPhone simulator and press **Run** (⌘R). The Simulator has no
   health data, so tap **Try it with demo data** on the first screen.
5. **Your iPhone:** plug it in (or use the same Wi-Fi after pairing once), turn on
   **Settings › Privacy & Security › Developer Mode**, trust the Mac, pick the iPhone
   in Xcode's device menu and press **Run**. Then tap **Connect Apple Health**:
   - Turn on all the topics, and when asked how much data to share, choose
     **All Recorded Data and Future Data**. With only the past 30 days, your
     trends, bests, streaks and milestones start from scratch.
   - Keep **Settings › General › Background App Refresh** on for Fitness Coach,
     so new workouts and sleep reach the widgets without opening the app.

For Garmin users: in the Garmin Connect app, turn on sharing to Apple Health
(**More › Settings › Connected Apps › Apple Health**). As far as we know, Garmin
shares workouts, steps, heart rate, calories and sleep, but not Body Battery,
stress or Garmin's own HRV status; the app works out its own versions from what's
there.

## How it's built

```
fitness-ios/
├── project.yml              Xcode project definition (XcodeGen); Fitness.xcodeproj is generated from it
├── Packages/FitnessCore/    Swift package: data models + all coaching logic, no Apple Health or UI code
│   ├── Sources/FitnessCore/ Readiness, Goals, Milestones, Plan, Bests, Sleep, Snapshot, DemoData
│   └── Tests/               34 tests (Swift Testing)
├── App/                     SwiftUI app: Apple Health reading, screens, settings
├── Widgets/                 WidgetKit extension: 8 widgets
├── Shared/                  Colours and small views used by both the app and the widgets
└── scripts/test-core.sh     Runs the FitnessCore tests on the Mac
```

- **Data flow:** the app reads Apple Health (`App/HealthKitService.swift`), works out a
  `Snapshot` with `FitnessCore`, and saves it as JSON in the shared App Group folder.
  Widgets only read that file, so they need no Apple Health access of their own.
- **Staying fresh:** the app asks Apple Health to wake it when new workouts, sleep,
  steps, resting HR or HRV arrive (background delivery), refreshes the snapshot and
  reloads the widgets. Widgets also re-read the file every 30 minutes.
- **Same logic as the web dashboard:** today's call, the weekly goal, milestones,
  training plan, bests and sleep insights are ported from `coach.py` in
  `my-personal-dashboard`, adapted to Apple Health. Differences: HRV is Apple Health's
  SDNN measure compared with your own 7-day average; Body Battery is replaced by
  training load (exercise minutes in the last 7 days vs your usual week); there's no
  sleep score, so sleep uses hours against your target.

### Tests

```bash
./scripts/test-core.sh
```

Runs the coaching logic tests on the Mac in a second, with or without Xcode. In
Xcode, **Product › Test** (⌘U) runs the same tests.

After adding or removing source files, regenerate the project:

```bash
brew install xcodegen   # once
xcodegen
```

## Privacy

- Read-only access to Apple Health; the app never writes to it.
- No accounts, no servers, no analytics. Everything is worked out on the phone.
- The widgets' snapshot is stored in the app's private App Group folder, protected
  until you first unlock the phone after a restart.
- A guide from your watch data, not medical advice.
