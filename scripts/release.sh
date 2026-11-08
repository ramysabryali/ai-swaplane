#!/bin/bash
# Builds a universal (arm64 + x86_64) app and packs dist/AI-Swaplane-<version>.zip.
#   ./scripts/release.sh
# Without a Developer ID identity the zip is ad-hoc signed: users must right-click > Open once.
# For a notarized build set:
#   SWAPLANE_SIGN_ID="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE=<name of a profile saved with: xcrun notarytool store-credentials>
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"

# Never ship a build signed with a personal development certificate: ad-hoc unless told otherwise.
export SWAPLANE_SIGN_ID="${SWAPLANE_SIGN_ID:--}"
UNIVERSAL=1 ./scripts/make-app.sh release

APP="build/AI Swaplane.app"
mkdir -p dist
ZIP="dist/AI-Swaplane-$VERSION.zip"
rm -f "$ZIP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  case "${SWAPLANE_SIGN_ID:-}" in
    "Developer ID Application:"*) ;;
    *) echo "Notarization needs SWAPLANE_SIGN_ID set to a Developer ID Application identity." >&2; exit 1 ;;
  esac
  ditto -c -k --keepParent "$APP" "dist/notarize.zip"
  xcrun notarytool submit "dist/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "dist/notarize.zip"
fi

ditto -c -k --keepParent "$APP" "$ZIP"
echo
echo "Built $ZIP"
shasum -a 256 "$ZIP"
