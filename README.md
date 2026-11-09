# Fitness Coach (iPhone)

An iPhone app and Home Screen / Lock Screen widgets that coach you from your
first run to an Ironman, using the data in **Apple Health**: from Apple Watch,
Garmin, Coros, Polar, Oura or any app that syncs there.

**No servers. Read-only. Your data never leaves the iPhone.**

Garmin users can also connect the **Garmin Personal API** directly (Settings ›
Garmin) for everything the web dashboard (`my-personal-dashboard`) shows: Body
Battery, stress, sleep score, HRV status, training load, heart rate zones, graphs
through the day and second-by-second graphs for each workout. The app calls Garmin
straight from the phone; the key lives in the iPhone's Keychain.

## What it does

| Screen | What you see |
|---|---|
| **Today** | ‹ Today › to step back through the last 90 days. Today's call (train, take it easy or rest) from HRV (Garmin's HRV status when connected), sleep (Garmin's sleep score), resting heart rate, Body Battery and training load. The day's steps, exercise, calories, resting HR, heart rate range, Body Battery, stress, sleep, HRV, breathing and floors; heart rate and Body Battery through the day (Garmin, last 7 days); new personal bests; the day's workouts. Tap a workout for its stats, heart rate zones, run/walk split and second-by-second graphs of heart rate, pace, cadence, power and elevation. |
| **Running** | Weekly goal ring and streak (**Edit** to change it). **Your weekly plan** (**Edit**: runs per week, which days, which milestone it builds toward, how fast the long run grows, how often an easier week comes) or **your race plan** (below). Milestone ladder; tiles comparing this week with recent weeks; distance / time / sessions by sport; exercise minutes per week; training load per week; heart rate zones; running form; personal bests and firsts; biggest days. |
| **Health** | Sleep insights for the last 2 weeks (vs your need, sleep debt, bedtime consistency, overnight stress, when you slept, tips); stress, Body Battery and calorie tiles; steps heatmap for 6 months; workouts other than running (hours per week and recent sessions); charts for steps, resting HR, HRV, sleep and sleep stages, stress, Body Battery high/low, exercise and active calories over 1M / 3M / 6M / 1Y. |
| **Settings** | Your name, weekly goal, sleep target, Apple Health, Garmin (connect, sync now, disconnect), demo data. |

### Race plans: day by day to 5K, 10K, half marathon or marathon

On the Running screen, **Make a day-by-day plan for a race**: pick the race, the race
date, runs per week (2-6), your long-run day, an optional strength day and your
longest recent run. The plan runs from today to race day:

- **Build:** the long run grows about 10% a week from where you are now, with an
  easier week every 4th; easy runs in between, and from week 3 one quality session a
  week (intervals for 5K/10K, tempo for half/marathon, alternating). Run-walk advice
  while runs are short. Never a run the day after the long run.
- **Taper:** 1 week (5K, 10K), 2 (half) or 3 (marathon) of shorter long runs.
- **Race week:** short easy runs, rest the two days before, then race day.
- **Too soon?** The preview warns when the date leaves too little time to build up
  and suggests the earliest comfortable date.

Each day shows ✓ when a run that day covered it (80% of the distance, or any run for
intervals and tempo), ✗ when missed. Tap any day to change it (another workout,
distance, notes) or skip it; **Reset to the plan** undoes that. **Edit plan** changes
the race, date or week (keeping your edited days if you like) or deletes the plan.
Today's planned workout also shows on the Today screen and in the Training plan widget.

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
   - **Free Apple account (Personal Team):** Apple Health and background updates
     work, but Xcode may not register the App Group the widgets share with the app.
     Build without it (the app works fully; widgets show "Open Fitness Coach to set up"):
     ```bash
     xcodebuild -project Fitness.xcodeproj -scheme Fitness -destination 'id=<your iPhone UDID>' \
       -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM=<your team ID> FC_SIGNING=-free build
     xcrun devicectl device install app --device <your iPhone UDID> build/Build/Products/Debug-iphoneos/Fitness.app
     ```
     `xcrun devicectl list devices` shows the UDID. For widgets on a real phone, tick the
     App Group under Signing & Capabilities in Xcode, or use the paid Apple Developer
     Program ($99/year), which TestFlight and the App Store need anyway.
   - The first time, the iPhone won't open the app until you trust yourself:
     **Settings › General › VPN & Device Management** › your Apple ID › **Trust**.
     Apps from a free account stop opening after 7 days; just build and install again.
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

### Connecting Garmin (optional)

1. In Garmin Connect on the web, open **Personal API Key**
   (https://connect.garmin.com/app/settings/personalApiToken), click **Create Key**,
   choose 1 year and copy the key (Garmin shows it once).
2. In the app: **Settings › Garmin**, paste it and tap **Connect Garmin**. The key is
   checked with Garmin, saved in the Keychain and never shown again.
3. The first sync downloads a year of history (a minute or two). After that the app
   syncs when you open it (at most every 15 minutes), when you pull to refresh, and
   in the background every few hours when iOS allows.

Garmin first, Apple Health filling the gaps: where both have a number, Garmin's is
used; workouts from other apps (an Apple Watch, say) are kept unless Garmin has the
same one. **Disconnect Garmin** deletes the key and everything downloaded from Garmin.

As before, the Personal API is meant for your own data: fine for your own phone,
but check Garmin's terms before offering it to other people.

For Garmin users without the API key: in the Garmin Connect app, turn on sharing to Apple Health
(**More › Settings › Connected Apps › Apple Health**). As far as we know, Garmin
shares workouts, steps, heart rate, calories and sleep, but not Body Battery,
stress or Garmin's own HRV status; the app works out its own versions from what's
there.

## How it's built

```
fitness-ios/
├── project.yml              Xcode project definition (XcodeGen); Fitness.xcodeproj is generated from it
├── Packages/FitnessCore/    Swift package: data models + all coaching logic, no Apple Health or UI code
│   ├── Sources/FitnessCore/ Readiness, Goals, Milestones, Plan, Bests, Sleep, Insights, Garmin, Snapshot, DemoData
│   └── Tests/               54 tests (Swift Testing), including a fake Garmin that answers with made-up data
├── App/                     SwiftUI app: Apple Health reading, Garmin sync (GarminService: Keychain + cache), screens
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
