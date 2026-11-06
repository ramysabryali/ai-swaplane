#!/bin/bash
# Builds build/AI Swaplane.app from the SwiftPM products.
#   ./scripts/make-app.sh [release|debug]     default: release
# Env: UNIVERSAL=1 builds arm64 + x86_64. SWAPLANE_SIGN_ID picks the signing identity
# (default: first "Apple Development" identity, else ad-hoc). Notarization: see scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="$(tr -d '[:space:]' < VERSION)"
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
APP="build/AI Swaplane.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "$BIN/SwaplaneApp" "$APP/Contents/MacOS/Swaplane"
cp "$BIN/swaplane" "$APP/Contents/Resources/bin/swaplane"
ICONDIR="$(mktemp -d)"
"$BIN/SwaplaneApp" --render-icon "$ICONDIR"
iconutil -c icns "$ICONDIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONDIR"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.swaplane.mac</string>
  <key>CFBundleName</key><string>AI Swaplane</string>
  <key>CFBundleDisplayName</key><string>AI Swaplane</string>
  <key>CFBundleExecutable</key><string>Swaplane</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# A stable signing identity keeps Keychain "Always Allow" valid across rebuilds (ad-hoc signatures change every build).
SIGN_ID="${SWAPLANE_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
[ "$SIGN_ID" = "-" ] && SIGN_ID=""
codesign --force --deep --options runtime -s "${SIGN_ID:--}" "$APP" 2>&1 | tail -1
echo "Signed with: ${SIGN_ID:-ad-hoc}"
if [ -z "${SIGN_ID:-}" ]; then
  echo "Note: ad-hoc signature. macOS will ask again for Keychain access after every rebuild; install a signing certificate (or set SWAPLANE_SIGN_ID) to avoid that." >&2
fi
echo "Built $APP"
