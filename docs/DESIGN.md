# Design — Swaplane UI and brand (v0.2+)

Status: **locked 2026-11-06.** Mockups (interactive, kept outside the repo): "Connector lanes" v2. Supersedes the layout parts of [UX.md](UX.md). Reference for the approach only (not assets or code): the open-source menu bar app *Double Shot* (MIT). Swaplane's mark, palette, copy and sounds are original.

## Decisions

| Topic | Decision |
|---|---|
| Layout | **Connector lanes**: one lane per account on the left, lines to the tools on the right. Solid = tool is on that account; dashed = preview of the selected account's switch. |
| Switch confirmation | **Hold to switch** (≈0.9 s, progress fill, release cancels; Space/Return held works too). Undo for 9 s after. |
| Menu bar item | **Twin bars**: fork glyph + two micro bars (session, weekly) in the account colour; amber ≥ 80 %, red ≥ 95 %. Second dot when tools are on different accounts. |
| Signal colour | **Orange `#FF8A3D`** (one token, `Theme.signal`). |
| Appearance | **Follows system light/dark**, with an override in Settings (System / Light / Dark). |
| Usage spike | Approved: one read-only call with the live Claude Code token, percentages only. |
| Window | Settings-only native window (toolbar tabs). All account management is in the menu bar panel. |

## 1. Principles

1. **See everything, switch deliberately.** Every account's usage is visible without switching.
2. **Both or one.** Switch a whole account (Code + Desktop) or one tool.
3. **Never surprising.** Anything that restarts an app says so; failures say exactly what did and didn't change.
4. **Honest about data.** Usage states: fresh, stale, expired, unavailable, none. Never show a number we can't back.
5. **Native feel, own identity.** System materials and SF type, one accent colour.

## 2. Menu bar panel

Borderless `NSPanel`, 380 pt wide, 22 pt radius, on the screen that owns the status item (clamped to `visibleFrame`), closes on outside click / Esc. Top to bottom: header (title, per-tool status line, **gear → Settings**), provider tabs only when more than one provider has an installed tool, lanes + detail card, toast strip, footer (**Add account**, Quit). There is no Settings button at the bottom.

States: fresh install (welcome: detect and import), no accounts, one account ("Add another to start switching"), several, a provider with no accounts (empty state with import).

### Lanes and detail card
- Row: node (filled when active on any tool), name, one-line usage summary or state, **⋯ menu**: Re-authenticate, Re-import current state, Rename, Remove… (inline confirm, Undo).
- Selecting a lane shows its detail card: plan, masked email, "Active on …", limit bars (session / weekly, reset times), reminder bell (disabled without limits), switch controls.
- Account kinds: limits (one or two windows), **no limit**, **usage unavailable**, **sign-in expired** (Re-authenticate replaces Switch).

### Switching
- Tool selector above the button: **Both / Code only / Desktop only** (only tools not already on the account).
- Hold the button to switch. Each tool is its own transaction (existing engine contract); Code first, then Desktop.
- Partial failure: Code stays switched; toast offers **Retry Desktop** and **Undo Code**.
- Undo restores each tool's previous profile.

## 3. Menu bar item
Fork glyph (template-tinted) + two bars; the glyph's dots use the account colours, so the image is non-template. Tracks the provider tab last used. No usage data → empty bars. Tooltip: "Code: Personal · Desktop: Work".

## 4. Sound and motion
Quiet synthesised tones: select, toggle on/off, switch success, reminder ping, remove, warning. Settings: Sound on/off, Reduced motion. Honours macOS Reduce Motion. Motion: selection highlight, bar fills, connector draw after a switch, pulse on the switched node, toast slide.

## 5. Data model
- `AccountGroup { id, label, colorName, emoji? }` in `groups.json` (non-secret). `Profile.groupID` links tool profiles into one account; legacy profiles migrate (different tools with the same identity merge; same-tool duplicates stay apart).
- `SwitchEngine.switchGroup(_:tools:progress:)` → per-tool results, Code before Desktop.
- Tests: order, partial failure, undo, migration, one-tool group.

## 6. Usage
Active account polled; inactive accounts refreshed when the panel opens, only if their saved token works. Swaplane never refreshes tokens itself (rotation risk). Findings of the spike are recorded in SPIKE-0-FINDINGS.md. Failures never block switching.

## 7. Settings window
Native toolbar tabs: General (open at login, appearance, menu bar), Safety, Tools, Activity, About.

## 8. Brand
Lanes. Midnight `#0B1220`, Ink `#121B2B`, Rail `#E8EEF7`, signal orange. SF Pro; SF Symbols plus the custom fork glyph. Vendor-neutral: no AI vendor marks or colours. Copy: sentence case, verbs first.

## 9. Implementation order
Data model → theme and panel → lanes and detail card → hold to switch → twin-bars icon → sound/motion → Settings window → welcome flow → reminders.

## 10. Implementation status (2026-11-06)

Built: account groups + migration + `switchGroup` (tested), usage service with cache and honest states (tested; endpoint shape unverified, see SPIKE-0-FINDINGS.md), themed panel with connector lanes, ⋯ menus (re-authenticate, re-import, rename, colour, remove), detail card, hold to switch with Both/only selector, Undo and partial-failure actions, twin-bars menu bar icon, synthesised sounds, reduced motion, appearance override, settings-only window, add/re-authenticate window, welcome import, reminder notifications.

Not verified on a real screen: the panel was rendered to PNGs with synthetic data (`SwaplaneApp --snapshot <dir>`), but hold-to-switch timing, the NSPanel position on external displays, sounds, notifications and the Keychain prompt for reading the Claude Code token have not been exercised by hand. Provider tabs and OpenAI wiring wait for v0.3.

## 11. Naming (2026-11-06)

The product name shown to users is **AI Swaplane** (panel title, window titles, About, notifications, tooltip, Quit item, CLI text, bundle display name, `AI Swaplane.app`). Kept unchanged on purpose so saved data and Keychain permissions survive: bundle id `app.swaplane.mac`, SwiftPM module and target names, the `swaplane` CLI, the data folder `Application Support/Swaplane`, and Keychain service names.
