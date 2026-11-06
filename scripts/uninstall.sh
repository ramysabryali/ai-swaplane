#!/bin/bash
# Removes AI Swaplane. Your saved accounts are kept unless you pass --purge.
#   ./scripts/uninstall.sh [--purge]
# --purge also deletes ~/Library/Application Support/Swaplane and the app's Keychain items
# (service "app.swaplane.vault"). Accounts you saved in AI Swaplane can't be recovered afterwards.
# Claude Code and Claude Desktop themselves are never touched.
set -euo pipefail

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

pkill -x Swaplane 2>/dev/null || true
for d in /Applications "$HOME/Applications"; do
  if [ -d "$d/AI Swaplane.app" ]; then rm -rf "$d/AI Swaplane.app"; echo "Removed $d/AI Swaplane.app"; fi
done

if [ "$PURGE" = "1" ]; then
  rm -rf "$HOME/Library/Application Support/Swaplane"
  echo "Removed ~/Library/Application Support/Swaplane"
  while security delete-generic-password -s "app.swaplane.vault" >/dev/null 2>&1; do :; done
  echo "Removed Keychain items for app.swaplane.vault"
else
  echo "Kept your saved accounts. Re-run with --purge to delete them too."
fi
