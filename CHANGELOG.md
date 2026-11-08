# Changelog

## Unreleased

- Signed-in accounts are detected automatically. A card in the panel offers **Import account**, or **Not now**.
- **Sign in to a new account** is a guided window with three steps: prepare, sign in (detected automatically), import. Cancel restores your previous account.
- First-run welcome tour: find the icon, import detected accounts, learn how switching works. Reopen it from Settings > About.
- CLI and Desktop sign-ins join one account only when they are the same identity.
- Background refresh is configurable in Settings > General. The default is every 5 minutes (it was every minute), with a Low Power Mode slowdown. Opening the panel and waking the Mac always refresh.

## 0.1.0

First public version.

- Switch Claude Code and Claude Desktop accounts together or one at a time.
- Menu bar panel with account lanes, hold-to-switch, and a usage summary.
- Per-window reset reminders for Session and Weekly limits.
- Import the account you're signed in to, add another, re-authenticate, rename, recolour, remove.
- Credentials encrypted with keys held in the macOS Keychain. No telemetry.
