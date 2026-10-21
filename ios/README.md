# Driver Log for iPhone

The native app for the First Due driver's log, built with SwiftUI and [xtool](https://github.com/xtool-org/xtool) from Windows (WSL). It uses the same Supabase account and data as the website, so entries made on either show up on both.

## What's different from the website

- **GPS keeps recording with the phone locked.** During a drive the app uses iOS 17's background location session with "While Using" permission. iOS shows the blue location pill while it records. Fixes go through the same trip meter as the website (`Sources/DriverLogCore/TripMeter.swift`).
- Drive progress is saved on the phone after every fix and to Supabase every 30 seconds, so a crash or relaunch mid-drive picks up where it left off.

## Layout

| Path | What it is |
|---|---|
| `Sources/DriverLogCore` | UI-free logic shared with the website's rules: models, home-terminal time math, Simple day planner, GPS trip meter, Supabase row mapping, History summaries. Builds on macOS so it can be unit tested. |
| `Sources/DriverLog` | The SwiftUI app: sign-in, Log (Add entry, Clock in/out, Start driving, Set status, Daily log), History, Settings, editors. |
| `Tests/DriverLogCoreTests` | Planner results match the website, daylight saving, GPS gaps and glitches, sync diffs. |
| `xtool.yml`, `Info.plist`, `AppIcon.png` | Bundle ID, location permission text, background location mode, sign-in callback URL scheme, icon. |
| `ci/` | macOS CI scripts: core tests, iOS build, simulator screenshots with sample data (`-demo`). |

## Run it on your iPhone

The one-time WSL, Swift, usbipd and `xtool setup` steps are the same as in the [Orbit README](https://github.com/EricTalanoa/orbit#one-time-setup-on-windows). Then:

```bash
git clone https://github.com/EricTalanoa/first-due-driver-log.git
cd first-due-driver-log/ios
xtool dev
```

On first launch iOS asks for location access when you tap **Start driving**: choose **Allow While Using App**.

## One-time Supabase settings

- Authentication → URL Configuration → Redirect URLs: add `firstduedriverlog://login-callback` (Google sign-in returns to the app through it).
- Run `supabase/migrations/20261022000000_delete_my_account.sql` in the SQL Editor (powers **Delete account**).

## Before the App Store

- Sign in with Apple (required when Google sign-in is offered).
- A privacy policy page and App Store privacy labels.
- Release builds through a GitHub Actions macOS job, since xtool can't sign for the App Store yet.
