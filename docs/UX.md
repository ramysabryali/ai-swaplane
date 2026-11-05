# UX — Swaplane

## Principles

1. **One click to switch.** Everything else is secondary.
2. **Always show who's active** — per tool, in the menu bar and on every surface.
3. **Never surprise.** Anything that quits an app or touches credentials is explicit, with a clear confirmation or a visible, undoable result.
4. **Calm and native.** SwiftUI, SF Symbols, system colors, supports Light/Dark, Reduce Motion, VoiceOver, Dynamic Type where applicable.

## Surfaces

### 1. Menu bar item

- Implemented with `NSStatusItem` (+ `NSPopover` or `NSMenu`) — not only `MenuBarExtra`, so we control multi-display behavior and click handling.
- **Icon states**: neutral glyph; active-profile color dot/badge; v0.2 adds usage ring or percentage text (user-selectable: icon only / icon + %, / compact bar).
- **Click** → popover (~340 pt wide):
  - Header: app name, gear, "+" (add profile).
  - Sections by tool (Claude Desktop, Claude Code, …), each listing profiles as rows: color/emoji, label, identity hint, active checkmark, (v0.2) usage mini-bar and reset countdown.
  - Row click = switch. Row secondary actions via hover/context menu: Rename, Duplicate as new empty profile, Re-import current state, Remove, Reveal info.
  - Footer: "Open Swaplane…", "Quit".
- **Option-click** on the icon: open main window. **Right-click**: classic menu (Open, Preferences, Quit).
- Switching shows inline progress ("Quitting Claude… Restoring… Relaunching…") and a success/failed toast with **Undo** for 10 s.

### 2. Main window

Sidebar: Profiles · Activity · Settings (· Usage v0.2 · Projects v0.4 · Backup v0.5).

- **Profiles**: table/list grouped by tool; detail pane shows label, tool, identity hint, color, emoji, created, last used, token health, snapshot size, actions.
- **Add profile** flow (wizard):
  1. Choose tool.
  2. "Import current login" (detected account preview) **or** "Create empty profile" (switches the tool into a logged-out state so user can sign in with a different account, then captures on confirm).
  3. Name, color, emoji.
  4. Confirm; success.
- **Activity**: local audit log list (time, tool, from → to, result). Export CSV. Clear.
- **Settings**: General (launch at login, menu bar display mode), Security (Touch ID gate options, auto-lock), Tools (enable/disable adapters, show detected versions, health), Advanced (feature flags, log level, reveal data folder).

### 3. Onboarding / import wizard

First launch: scan for installed/logged-in tools → list findings ("Claude Desktop — signed in as j***@x.com") → user checks which to import → name each → done. Explain in one screen what is stored where (Keychain; encrypted snapshots) and that nothing leaves the Mac.

### 4. Switcher panel (v0.5, hotkey)

Floating `NSPanel` (non-activating, `.nonactivatingPanel`, level `.floating`, joins all Spaces, `fullScreenAuxiliary`) with a search field and profile list; keyboard-first (↑↓ Enter, ⌘1–9, Esc).

## Multi-display behavior (F6)

- macOS shows the menu bar on all displays when **Settings → Desktop & Dock → Displays have separate Spaces** is on; the `NSStatusItem` then appears on each. Verify on hardware; do not assume.
- Popover anchors to the status item button's window; compute screen from `button.window?.screen` and clamp to `visibleFrame` so it never opens off-screen.
- Panels (palette, wizard HUD) open on the screen containing the mouse: `NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }`.
- Main window restores to the last screen; if that screen is gone (disconnected display), fall back to `NSScreen.main`.
- Listen for `NSApplication.didChangeScreenParametersNotification` and re-validate window/panel frames.
- Test matrix: 1 display, 2 displays, notch MacBook, display unplugged mid-session, fullscreen app on secondary display, different scale factors.

## States and copy

- **Empty**: "No profiles yet — import the account you're signed into now." [Import]
- **Tool not installed**: dimmed section, "Claude Desktop isn't installed" + link to vendor site.
- **Unsupported version**: "This version of <Tool> isn't verified. Switching is disabled to protect your data." + details.
- **Token expired**: warning badge, "Sign in again" action (opens tool).
- **Switch failed**: "Couldn't switch. Your previous account was restored." + details + copy diagnostics (secret-free).
- **Locked (Touch ID gate)**: row actions disabled until unlocked.

## Accessibility

- All controls labeled; menu bar icon has accessibility description with active profile names.
- Never rely on color alone — pair with emoji/initials/checkmark.
- Keyboard-navigable popover and main window; full VoiceOver pass in each milestone's acceptance.

## Visual design

- System materials (`.regularMaterial`), SF Pro, SF Symbols 5+, 8-pt grid, corner radius 10–12.
- Per-profile color palette of 8–10 accessible colors; avoid red/green-only distinctions.
- App icon: stylized rail-switch / branching track. Menu bar template image (monochrome) plus colored badge overlay.
