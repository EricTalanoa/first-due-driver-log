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

The first time you tap **Start driving**, choose **Allow While Using App** for location.

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
