# Driver Log for iPhone

The native app for the First Due driver's log, built with SwiftUI and [xtool](https://github.com/xtool-org/xtool) from Windows (WSL). It uses the same Supabase account and data as the website, so entries made on either show up on both.

## Screens

The same three tabs as the website:

- **Today**: Add entry (Simple day, step by step, Advanced), then the day's DOT chart with totals and remarks, and the entries. Tap the chart to edit an entry.
- **LD**: tap through the day (Clock in, Start driving, Fuel stop, Quick break, Lunch, Start unload, Switch drivers, Arrive · post-trip, Clock out), each with a time and place; hours-of-service clocks; the inspection view of the last 8 days; Fill in or fix a day; Estimate an LD day.
- **History**: days by month, with LD trips outlined in red.

GPS tracking is shelved, as on the website: the app doesn't ask for location. The trip meter stays in `DriverLogCore` for later.

## Layout

| Path | What it is |
|---|---|
| `Sources/DriverLogCore` | UI-free logic shared with the website's rules: models, home-terminal time math, Simple day planner, LD steps, DOT chart and hours-of-service clocks (`HOS.swift`), Supabase row mapping, History summaries. Builds on macOS so it can be unit tested. |
| `Sources/DriverLog` | The SwiftUI app: sign-in, Log (Add entry, Clock in/out, Start driving, Set status, Daily log), History, Settings, editors. |
| `Tests/DriverLogCoreTests` | Planner results and LD charts match the website, hours-of-service clocks, daylight saving, sync diffs. |
| `xtool.yml`, `Info.plist`, `AppIcon.png` | Bundle ID, sign-in callback URL scheme, icon. |
| `ci/` | macOS CI scripts: core tests, iOS build, simulator screenshots with sample data (`-demo`). |

## Run it on your iPhone

Windows keeps the phone and relays it to WSL. The **Apple Devices** app (Microsoft Store) runs Apple's phone connector on `127.0.0.1:27015`. A `netsh portproxy` forward exposes that port to WSL, and `USBMUXD_SOCKET_ADDRESS` in Ubuntu points xtool at it. usbipd passthrough doesn't work for installs: `xtool dev` hangs at "Connecting" (xtool issue #19).

Each time:

1. Plug in and unlock the iPhone, and open **Apple Devices**.
2. Admin PowerShell: `usbipd unbind --busid 2-1`. It's fine if it says "already not shared".
3. Ubuntu: run `idevice_id -l`; it should print the phone's ID.
4. Build and install:

   ```bash
   cd ~/first-due-driver-log/ios
   git pull
   xtool dev
   ```

**One-time setup on a new PC**, in addition to WSL, Swift, xtool and `xtool setup`:

```powershell
# Admin PowerShell. Use the address Ubuntu prints for: ip route list default | awk '{print $3}'
netsh interface portproxy add v4tov4 listenaddress=172.31.32.1 listenport=27015 connectaddress=127.0.0.1 connectport=27015
New-NetFirewallRule -DisplayName "WSL usbmuxd relay" -Direction Inbound -LocalPort 27015 -Protocol TCP -Action Allow
```

```bash
# Ubuntu: always point at the relay, even if the address changes
echo 'export USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '"'"'{print $3}'"'"'):27015"' >> ~/.bashrc
```

## One-time Supabase settings

- Authentication → URL Configuration → Redirect URLs: add `firstduedriverlog://login-callback` (Google sign-in returns to the app through it).
- Run `supabase/migrations/20261022000000_delete_my_account.sql` in the SQL Editor (powers **Delete account**).

## Before the App Store

- Sign in with Apple (required when Google sign-in is offered).
- A privacy policy page and App Store privacy labels.
- Release builds through a GitHub Actions macOS job, since xtool can't sign for the App Store yet.
