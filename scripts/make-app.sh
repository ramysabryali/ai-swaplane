#!/bin/bash
# Builds build/Swaplane.app from the SwiftPM products (ad-hoc signed; for local use only).
# Release signing/notarization (Developer ID) arrives in v0.5 — see docs/milestones/v0.5-polish-and-release.md.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Swaplane.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN/SwaplaneApp" "$APP/Contents/MacOS/Swaplane"
cp "$BIN/swaplane" "$APP/Contents/Resources/bin/swaplane"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.swaplane.mac</string>
  <key>CFBundleName</key><string>Swaplane</string>
  <key>CFBundleDisplayName</key><string>Swaplane</string>
  <key>CFBundleExecutable</key><string>Swaplane</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --options runtime -s - "$APP" 2>&1 | tail -1
echo "Built $APP"
