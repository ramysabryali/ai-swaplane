#!/bin/bash
# Builds AI Swaplane from source and installs it.
#   ./scripts/install.sh [--dir <folder>]    default folder: /Applications (falls back to ~/Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DEST="${2:?--dir needs a folder}"; shift 2 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ "$(uname)" = "Darwin" ] || { echo "AI Swaplane only runs on macOS." >&2; exit 1; }
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || { echo "AI Swaplane needs macOS 14 or newer (found $(sw_vers -productVersion))." >&2; exit 1; }
if ! command -v swift >/dev/null 2>&1; then
  echo "Swift toolchain not found. Install Xcode 16 or newer (App Store) or run: xcode-select --install" >&2
  exit 1
fi
SWIFT_MAJOR="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9]*\).*/\1/p' | head -1)"
if [ -n "$SWIFT_MAJOR" ] && [ "$SWIFT_MAJOR" -lt 6 ]; then
  echo "Swift 6 or newer is required (found $SWIFT_MAJOR). Update Xcode." >&2
  exit 1
fi

if [ -z "$DEST" ]; then
  if [ -w /Applications ]; then DEST=/Applications; else DEST="$HOME/Applications"; fi
fi
mkdir -p "$DEST"

echo "Building (first build takes a minute)…"
./scripts/make-app.sh release

APP="build/AI Swaplane.app"
pkill -x Swaplane 2>/dev/null || true          # quit a running copy so the new one starts clean
rm -rf "$DEST/AI Swaplane.app"
ditto "$APP" "$DEST/AI Swaplane.app"
xattr -dr com.apple.quarantine "$DEST/AI Swaplane.app" 2>/dev/null || true

echo
echo "Installed: $DEST/AI Swaplane.app"
echo "Open it with:  open \"$DEST/AI Swaplane.app\""
echo "It lives in the menu bar (no Dock icon). On first launch macOS asks to let it read the"
echo "Claude Code sign-in from your Keychain; choose Always Allow."
