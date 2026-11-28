# Testing

Every pull request runs these automatically on GitHub. Nothing in them touches the real log: the website tests use a fake Supabase and the iPhone tests use the app's sample data.

| Suite | What it covers | Where | Run it yourself |
|---|---|---|---|
| Logic tests, website | Chart, hours-of-service clocks, LD steps and times, shifts past midnight, miles, LD detection, Simple day and LD estimate, city list, save checks | `tests/unit/` | `npm test` |
| Browser tests, website | The built site clicked through on a phone-sized screen: LD days, Today, History, editing, failures, two devices | `tests/e2e/` | `npm run build:netlify` then `npm run test:e2e` |
| Logic tests, iPhone | The same rules in Swift, with the same numbers as the website | `ios/Tests/` | `swift test` in `ios/` (macOS) |
| Simulator tests, iPhone | The app tapped through on a simulator: clock in, a stop with Other, Clear day, inspection view, History, Edit day, the tutorial (first launch and replay) | `ios/ci/host/UITests/` | `ci/uitests.sh` in `ios/` (macOS) |
| Screenshots, iPhone | Every main screen with sample data, published to the `ios-screenshots` branch | `ios/ci/screenshots.sh` | CI only |

## Scenarios covered

- **LD day, live:** clock in at the office, drive, fuel (Other place), lunch, post-trip at a hotel, clock out; the chart's remarks; History's red LD trip.
- **Next morning:** the hotel from last night is suggested; an older trip is not; the hours clocks appear only after clocking in.
- **Step times:** a step saved a minute ahead (the reported bug); a time before the current step names when it started; rounding up; last night.
- **Co-driver:** riding is logged as on duty; taking the wheel back starts a drive.
- **Unknown city:** miles are asked for before saving.
- **Clear day:** removes the whole day, including a drive in progress; other days stay.
- **Simple day:** add, Edit day, change lunch, Clear day; a single-location (labor only) job, alone or with a regular one; a clash with existing entries is explained, not saved.
- **Fill in a day:** steps past midnight, the next day's chart, Edit day on either day opens the whole shift.
- **Advanced entry:** add, edit, delete.
- **Failures:** a save that doesn't reach the server keeps the form open; the phone and the website changing the log at once.
- **Calendar:** daylight-saving days (23 and 25 hours), a time skipped by the clock change, a phone set to another time zone.
- **Hours of service:** over 11 hours and the 14-hour window, the 30-minute break (on-duty time counts), a new shift after 10 hours off, 70 hours in 8 days, a 34-hour restart.
- **Account:** driver details save; the lock button signs out.

## Bugs found and fixed (testing pass, Nov 2026)

| # | Severity | What happened | Fix |
|---|---|---|---|
| 1 | Medium | **A shift past midnight was split when editing.** Edit day only showed up to midnight; the next day showed the post-trip alone as a "Clock in". | Edit day works on the whole shift, carried past midnight while the work continues; opening the next day goes to the shift it belongs to. |
| 2 | Medium | **Phone and website at the same time.** A page that hadn't seen the other device's change got "Duty periods cannot overlap", which made no sense, and stayed stale. | The app recognizes this, refreshes from the server and says the log changed on another device. |
| 4 | High | **iPhone app crashed on Clear day** (found by the simulator tests). While what you're recording was removed, the Today list could redraw its old row once and force-read an end time it didn't have. The same could happen on any LD step. | Rows treat an entry with no end as "now" instead of assuming one. |
| 5 | Medium | **iPhone Clock in didn't preselect a place**, so Save asked "Enter where you are" although Preston office was listed. | The first real suggestion is preselected, as on the website. |
| 3 | Low | **The website didn't refresh when you came back to it.** Changes made on the phone only showed after a manual reload. | The website reloads when the tab or app comes back into view (the iPhone app already did). |

Fixed earlier, now covered by tests: a step time just past now read as yesterday ("before your driving started"), Clear day leaving a drive in progress, the LD page showing an old trip.

## Known limits (not bugs)

- Miles are straight-line estimates scaled for roads, usually within about 10% on highways; short city hops and mountain routes vary more.
- On daylight-saving days the chart's hour lines are evenly spaced, so the hour labels are approximate for the hour that repeats or is skipped. The totals are exact.
- This is a personal logbook, not a certified ELD.

## Check on a real phone (about 15 minutes)

Things the simulator and browser can't show:

1. Sign in with Google and with email on the iPhone app.
2. Tap through a short LD day for real (clock in, a stop with **Other**, clock out), then open the website: the same day is there.
3. Change something on the website, switch back to the app: it shows the change.
4. With the phone in airplane mode, tap a step: you get an error and the form stays open; turn the network back on and save.
5. Type an address with the keyboard in the **Other** box; the city suggestions appear and the miles estimate fills in.
6. Open **Inspection view** and scroll the 8 days; check it's readable in sunlight.
7. Rotate the phone, use large text (Settings → Display → Text Size), and check nothing is cut off.
