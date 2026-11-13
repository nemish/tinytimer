#!/bin/sh
# Builds TinyTimer.app next to this script. Usage: ./build.sh [run]
set -e
cd "$(dirname "$0")"
APP=TinyTimer.app
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/TinyTimer"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>TinyTimer</string>
  <key>CFBundleIdentifier</key><string>app.tinytimer.TinyTimer</string>
  <key>CFBundleExecutable</key><string>TinyTimer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
mkdir -p "$APP/Contents/Resources" && cp sounds/*.mp3 AppIcon.icns "$APP/Contents/Resources/"
# Developer ID + hardened runtime (needed for notarization); ad-hoc if no certificate on this Mac.
codesign --force --options runtime --timestamp --sign "Developer ID Application" "$APP" 2>/dev/null \
  || { echo "no Developer ID certificate, signing ad-hoc"; codesign --force --sign - "$APP"; }
"$APP/Contents/MacOS/TinyTimer" --selftest
if [ "$1" = run ]; then
  pkill -x TinyTimer 2>/dev/null || true
  rm -rf /Applications/TinyTimer.app && cp -R "$APP" /Applications/ && open /Applications/TinyTimer.app
fi
# ./build.sh release: notarize, staple, and zip for other Macs;
#   uses the saved notarytool keychain profile (override with NOTARY_PROFILE=name)
if [ "$1" = release ]; then
  ditto -c -k --keepParent "$APP" TinyTimer.zip
  xcrun notarytool submit TinyTimer.zip --keychain-profile "${NOTARY_PROFILE:-lexy-notary}" --wait
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" TinyTimer.zip
  spctl -a -vv "$APP"
fi
