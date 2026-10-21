# First Due Driver’s Log

A driving and duty log for First Due Movers drivers: clock in and out, record drives with GPS miles, fill in a whole work day in a few taps, and keep every day's record on the web and on iPhone.

**Live site:** https://first-due-driver-log-eric.netlify.app
**Status:** website in daily use · iPhone app in testing ([#13](https://github.com/EricTalanoa/first-due-driver-log/pull/13)) · App Store next

| Log | Drive in progress | History | Simple day |
|---|---|---|---|
| ![Log screen](https://github.com/EricTalanoa/first-due-driver-log/raw/ios-screenshots/03-log-on-clock.png) | ![Driving](https://github.com/EricTalanoa/first-due-driver-log/raw/ios-screenshots/04-log-driving.png) | ![History](https://github.com/EricTalanoa/first-due-driver-log/raw/ios-screenshots/06-history.png) | ![Simple day](https://github.com/EricTalanoa/first-due-driver-log/raw/ios-screenshots/07-simple-day.png) |

<sub>iPhone app with sample data, captured by CI on every change to `ios/`.</sub>

## What it does

- **Clock in, clock out, drive.** One card shows the day so far: worked time, miles, and when you clocked in. Start driving records the trip with GPS.
- **Simple day.** Enter the office, each job's load and unload cities, clock times and lunch; the whole day is laid out with estimated drive times and miles (or your odometer miles). Saved days can be reopened with **Edit day**.
- **Set status.** On duty, off duty (lunch) and sleeper berth, recorded as duty periods.
- **Daily log.** Every period for a day with totals per status, editable entries, and **Clear day**.
- **History.** Days grouped by month with monthly hours and miles; tap a day to open it.
- **Your data.** CSV export of every entry, JSON backup and import, print or PDF of a day.
- **Accounts.** Sign in with email or Google; each driver sees only their own log, on every device.

GPS miles are an estimate from the phone's location, not road routing; confirm with the odometer. This is a personal logbook, not a certified ELD.

## How it's built

| Part | Stack | Where |
|---|---|---|
| Website | React + Vite, deployed by Netlify from `main` | `app/`, `lib/`, `index.html` |
| Data & sign-in | Supabase (Postgres, row-level security, email + Google auth) | `supabase/migrations/` |
| iPhone app | SwiftUI, built from Windows with [xtool](https://github.com/xtool-org/xtool) | `ios/` |
| CI | GitHub Actions on macOS: core tests, iOS build, simulator screenshots | `.github/workflows/ios.yml` |

Both the website and the app read and write the same Supabase tables:

- `profiles`: driver and vehicle details.
- `entries`: one row per duty period. The row with no end time is the one being recorded now. A database rule stops duty periods from overlapping.
- `save_log()`: applies each change in one transaction; clients send only what changed.

The publishable Supabase key is in `lib/supabase.ts` and `ios/Sources/DriverLog/Backend.swift`. It's safe to ship because row-level security limits every query to the signed-in driver.

### GPS

- **Website:** keeps the screen awake while driving, ignores GPS wobble and impossible jumps, and bridges gaps (phone locked, signal lost) with a straight-line estimate. Gaps over five minutes are flagged to check.
- **iPhone app:** keeps recording with the phone locked, using "While Using" location and a background location session.
- Both use the same trip rules: `ios/Sources/DriverLogCore/TripMeter.swift` mirrors the website's.

## Working on it

**Website**

```sh
npm ci
npm run build:netlify      # production build into netlify-dist/
npx netlify dev            # local dev at http://localhost:8888
```

Use Node.js 22.13 or newer. No environment variables are needed. Pushing to `main` deploys to Netlify, and pull requests get a preview link.

**iPhone app** — see [`ios/README.md`](ios/README.md). In short, from WSL Ubuntu with the iPhone relayed through the Windows Apple Devices app:

```sh
cd ios
xtool dev
```

**Database changes** go in `supabase/migrations/` and are applied to the Supabase project.

## Roadmap

- [x] Simple day with multiple jobs, Edit day, Clear day; better GPS on the web ([#10](https://github.com/EricTalanoa/first-due-driver-log/pull/10))
- [x] Supabase database and sign-in with Google; import of the old log ([#11](https://github.com/EricTalanoa/first-due-driver-log/pull/11))
- [x] History grouped by month ([#12](https://github.com/EricTalanoa/first-due-driver-log/pull/12))
- [ ] iPhone app with background GPS ([#13](https://github.com/EricTalanoa/first-due-driver-log/pull/13), in testing)
- [ ] App Store: Sign in with Apple, privacy policy, signed TestFlight builds from CI
- [ ] Remove the unused starter scaffolding (see below)

## Repository notes

The project began from a starter template. These folders and files are left over from it and aren't used by the website or the app:

- `components/ui/`, `db/`, `drizzle/`, `examples/`
- `build/`, `scripts/`, `vendor/`
- `cloudflare-env.d.ts`, `next.config.ts`, `vite.config.ts`, and the `dev`/`build`/`start` npm scripts

The live site builds with `vite.netlify.config.ts` and `npm run build:netlify`.
