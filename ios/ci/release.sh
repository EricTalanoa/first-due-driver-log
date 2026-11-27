#!/bin/bash
# Archives the app, signs it with the App Store Connect API key and uploads it to TestFlight.
# Run by .github/workflows/release.yml. Needs these GitHub secrets:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (the .p8 file's text), APPLE_TEAM_ID
# and VERSION (e.g. 1.0) and BUILD (a number that goes up every upload) in the environment.
set -euo pipefail
: "${ASC_KEY_ID:?missing}" "${ASC_ISSUER_ID:?missing}" "${ASC_KEY_P8:?missing}" "${APPLE_TEAM_ID:?missing}" "${VERSION:?missing}" "${BUILD:?missing}"
cd ci/release

# Info.plist with this release's version and build number.
cp ../../Info.plist Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" Info.plist

# App icon (one 1024 px image; Xcode makes the other sizes).
mkdir -p Assets.xcassets/AppIcon.appiconset
cp ../../AppIcon.png Assets.xcassets/AppIcon.appiconset/AppIcon.png
cat > Assets.xcassets/Contents.json <<'JSON'
{ "info": { "author": "xcode", "version": 1 } }
JSON
cat > Assets.xcassets/AppIcon.appiconset/Contents.json <<'JSON'
{ "images": [ { "filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" } ], "info": { "author": "xcode", "version": 1 } }
JSON

KEY="$RUNNER_TEMP/AuthKey_$ASC_KEY_ID.p8"
printf '%s\n' "$ASC_KEY_P8" > "$KEY"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

xcodegen generate --quiet
xcodebuild archive -project DriverLogRelease.xcodeproj -scheme FirstDueDriverLog -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/DriverLog.xcarchive \
  -skipPackagePluginValidation -skipMacroValidation DEVELOPMENT_TEAM="$APPLE_TEAM_ID" "${AUTH[@]}"

# Export with App Store signing and upload straight to App Store Connect (it then appears in TestFlight).
cat > ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath build/DriverLog.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/export "${AUTH[@]}"
rm -f "$KEY"
echo "::notice::Uploaded version $VERSION ($BUILD). It shows up in App Store Connect → TestFlight after Apple finishes processing (usually 10–30 minutes)."
