#!/bin/bash
# Runs the simulator tap-through tests (ci/host/UITests) against the app with sample data.
set -euo pipefail
cd ci/host
xcodegen generate --quiet
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
c=[x for k,v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone") and "Pro Max" not in x["name"] and "Plus" not in x["name"]]
print(sorted(c,key=lambda x:x["name"])[-1]["udid"])')
xcodebuild test -project DriverLogHost.xcodeproj -scheme DriverLogHost -sdk iphonesimulator \
  -destination "id=$UDID" -derivedDataPath ../../dd-tests -skipPackagePluginValidation -skipMacroValidation -quiet
