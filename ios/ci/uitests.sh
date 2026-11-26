#!/bin/bash
# Runs the simulator tap-through tests (ci/host/UITests) against the app with sample data.
set -uo pipefail
cd ci/host
xcodegen generate --quiet
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
c=[x for k,v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone") and "Pro Max" not in x["name"] and "Plus" not in x["name"]]
print(sorted(c,key=lambda x:x["name"])[-1]["udid"])')
# Boot the simulator and wait until it is fully up: the first test otherwise races a cold boot and the app isn't running yet.
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
START=$(date +%s)
OPTS=(-project DriverLogHost.xcodeproj -scheme DriverLogHost -sdk iphonesimulator -destination "id=$UDID" \
  -derivedDataPath ../../dd-tests -skipPackagePluginValidation -skipMacroValidation)
xcodebuild build-for-testing "${OPTS[@]}" -quiet || exit 1
# Warm up: the first launch on a fresh simulator can fail while it is still migrating data after boot.
APP=$(find ../../dd-tests/Build/Products -name DriverLogHost.app -maxdepth 2 | head -1)
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.erictalanoa.DriverLogHost -demo off >/dev/null && sleep 15
xcrun simctl terminate "$UDID" com.erictalanoa.DriverLogHost 2>/dev/null || true
xcodebuild test-without-building "${OPTS[@]}" -resultBundlePath ../../ui-tests.xcresult 2>&1 \
  | grep -E "Test Case|error:|XCTAssert|Executed|TEST (SUCCEEDED|FAILED)|TEST EXECUTE"
STATUS=${PIPESTATUS[0]}
# If the app crashed, print the top of its crash report (exception and the crashing thread's frames).
echo "Recent crash reports:"; ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | head -5
for f in $(find ~/Library/Logs/DiagnosticReports -name 'DriverLogHost*' -mmin -60 2>/dev/null | head -2); do
  echo "::error::Crash report: $f"
  python3 - "$f" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
head, _, body = text.partition('\n')
try:
    r = json.loads(body)
    print('exception:', r.get('exception'), r.get('termination'))
    t = next((t for t in r.get('threads', []) if t.get('triggered')), {})
    imgs = r.get('usedImages', [])
    for fr in t.get('frames', [])[:25]:
        img = imgs[fr.get('imageIndex', 0)].get('name', '?') if imgs else '?'
        print(' ', img, fr.get('symbol', '?'), fr.get('sourceFile', ''), fr.get('sourceLine', ''))
except Exception as e:
    print(text[:4000])
PY
done
exit $STATUS
