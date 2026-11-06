#!/bin/bash
# Writes the Homebrew cask for the current VERSION into a tap checkout.
#   ./scripts/update-cask.sh <path to homebrew-tap checkout> [zip]
# The zip defaults to dist/AI-Swaplane-<version>.zip (build it with scripts/release.sh and
# upload that exact file to the GitHub release first, or the checksum won't match).
set -euo pipefail
cd "$(dirname "$0")/.."
TAP="${1:?Usage: update-cask.sh <tap checkout> [zip]}"
VERSION="$(tr -d '[:space:]' < VERSION)"
ZIP="${2:-dist/AI-Swaplane-$VERSION.zip}"
[ -f "$ZIP" ] || { echo "Missing $ZIP. Run ./scripts/release.sh first." >&2; exit 1; }
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
mkdir -p "$TAP/Casks"
cat > "$TAP/Casks/ai-swaplane.rb" <<RUBY
cask "ai-swaplane" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/ramysabryali/ai-swaplane/releases/download/#{version}/AI-Swaplane-#{version}.zip"
  name "AI Swaplane"
  desc "Switch between Claude accounts from the menu bar"
  homepage "https://github.com/ramysabryali/ai-swaplane"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "AI Swaplane.app"
  binary "#{appdir}/AI Swaplane.app/Contents/Resources/bin/swaplane"

  # Releases are ad-hoc signed until they are notarized, so clear the quarantine flag.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/AI Swaplane.app"],
        must_succeed: false
  end

  zap trash: [
    "~/Library/Application Support/Swaplane",
    "~/Library/Preferences/app.swaplane.mac.plist",
    "~/Library/Saved Application State/app.swaplane.mac.savedState",
  ]
end
RUBY
echo "Wrote $TAP/Casks/ai-swaplane.rb (version $VERSION, sha256 $SHA)"
