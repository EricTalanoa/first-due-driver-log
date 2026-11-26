#!/bin/bash
# Builds the app for the iOS Simulator with sample data (-demo), opens each screen, saves PNGs to ci-shots/.
set -euo pipefail
cd ci/host
xcodegen generate --quiet
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
c=[x for k,v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone") and "Pro Max" not in x["name"] and "Plus" not in x["name"]]
print(sorted(c,key=lambda x:x["name"])[-1]["udid"])')
echo "::notice::Simulator $(xcrun simctl list devices | grep $UDID | head -1 | xargs)"
xcodebuild build -project DriverLogHost.xcodeproj -scheme DriverLogHost -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath ../../dd -skipPackagePluginValidation -skipMacroValidation -quiet
APP=$(cd ../../dd/Build/Products && pwd)/$(cd ../../dd/Build/Products && find . -name "DriverLogHost.app" -maxdepth 2 | head -1)
cd ../..
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"
mkdir -p ci-shots
shoot() { # name, launch args...
  local name=$1; shift
  xcrun simctl terminate "$UDID" com.erictalanoa.DriverLogHost 2>/dev/null || true
  xcrun simctl launch "$UDID" com.erictalanoa.DriverLogHost "$@" >/dev/null
  sleep "${WAIT:-6}"
  xcrun simctl io "$UDID" screenshot "ci-shots/$name.png" >/dev/null
}
shoot 01-sign-in
shoot 02-today -demo ld
shoot 03-ld-off-clock -demo off -screen ld
shoot 04-ld-driving -demo ld -screen ld
# Sheets opened at launch need a moment longer to finish presenting.
WAIT=10 shoot 05-ld-step -demo ld -screen step
shoot 06-inspection -demo ld -screen inspect
shoot 07-history -demo ld -screen history
shoot 08-fill-in-day -demo ld -screen timeline
shoot 09-simple-day -demo off -screen simple
shoot 10-settings -demo off -screen settings
ls -la ci-shots
