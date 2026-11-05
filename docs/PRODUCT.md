# Product — Swaplane

## Vision

Make it effortless and safe to run multiple accounts of AI tools on one Mac. Switching should take one click or one keystroke, never risk losing a session, and never expose a credential.

## Problem

People hold several accounts for the same tools: work and personal, multiple clients, a team seat plus an individual plan. Today switching means logging out and in, re-authenticating, losing context, and hand-editing config dirs for CLIs. It is slow, error-prone and insecure (tokens pasted into notes, dotfiles copied around).

## Personas

- **Freelancer / consultant** — one account per client; needs hard separation and quick switching.
- **Employee with work + personal** — must never mix work data into personal and vice versa.
- **Power user** — runs two terminals on two accounts simultaneously; wants hotkeys and project rules.
- **Security-conscious user** — wants Keychain, biometrics, no telemetry, auditable behavior.

## Key concepts

- **Tool** — a supported product surface: `claude-desktop`, `claude-code`, `codex-cli`, `chatgpt-desktop`.
- **Profile** — `{ id: UUID, tool, label, identityHint (email/org, display only), color, emoji, createdAt }` plus secret material in the Keychain and an encrypted state snapshot. Same email ⇒ many profiles allowed.
- **Active profile** — the profile currently live on disk/Keychain for a tool. Exactly one per tool globally, plus optional **per-shell overrides** (v0.4).
- **Group** — optional bundle of profiles across tools (e.g. "Work" = Claude Desktop + Claude Code + Codex) switchable in one action.

## Functional requirements (all milestones)

| ID | Requirement | Milestone |
|---|---|---|
| F1 | Switch Claude Desktop profile | v0.1 |
| F2 | Switch Claude Code (CLI) profile | v0.1 |
| F3 | Menu bar item with profile list and one-click switch | v0.1 |
| F4 | Keychain-backed secret storage | v0.1 |
| F5 | Auto-detect currently logged-in accounts (import wizard) | v0.1 |
| F6 | Menu bar and switcher work on main and all external displays | v0.1 |
| F7 | Separate state for same email (UUID profiles) | v0.1 |
| F8 | Live usage in menu bar | v0.2 |
| F9 | Touch ID / password gate | v0.2 |
| F10 | Codex CLI, then ChatGPT desktop | v0.3 |
| F11 | Per-shell and per-project switching | v0.4 |
| F12 | Global hotkey palette | v0.5 |
| F13 | App Intents (Shortcuts/Spotlight) | v0.5 |
| F14 | Encrypted backup/restore | v0.5 |
| F15 | Auto-update | v0.5 |
| F16 | Standalone: no external runtime (Node/Python) required | all |
| F17 | Full macOS app (main window) plus menu bar presence | all |

## Non-goals

- Not a proxy, token broker, or API gateway. Swaplane never sends prompts or intercepts traffic.
- Not for sharing accounts between people or reselling access.
- Not for bypassing rate limits; automatic usage-based failover is **not** performed (suggestions only).
- Not on the Mac App Store (needs unsandboxed access to other apps' data).
- No Windows/Linux. No cloud sync. No accounts/login for Swaplane itself.
- No telemetry or analytics.

## Success metrics (local-only, user-visible, never transmitted)

- Switch completes in < 3 s for CLI, < 8 s for desktop app (quit + restore + relaunch).
- Zero data loss across 500 consecutive automated switch cycles in tests.
- Import wizard correctly detects current account for each supported tool on a clean install.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Vendors change storage layout | Adapters isolate constants; version-detect; health-check on launch; clear "unsupported version" state instead of corrupting |
| Usage endpoints are undocumented | Feature flag, graceful degrade, never block switching |
| ToS concerns | Position as separation tool; no automatic limit evasion; README disclaimer |
| Relaunching apps interrupts work | Warn on switch if app has windows; offer side-by-side instance where supported (Electron `--user-data-dir`) |
| Token refresh races (CLI refreshes token while snapshot stale) | Capture-back on every switch and on a periodic/at-exit basis; see ARCHITECTURE |
| Corrupt switch mid-way | Journaled transaction + automatic rollback + backups kept N=3 |

## Naming

Name: **Swaplane** (chosen over AI Switch, AI Profile, Switchyard, Lanes, Valet, Keyring, Hotswap, Swivio, Zwiply). Identifiers: bundle ID `app.swaplane.mac`, CLI `swaplane`, data folder `~/Library/Application Support/Swaplane`, project rule file `.swaplane`.

Status as of 2026-11-05: `swaplane.app` was unregistered (RDAP check); `swaplane.com` is taken, so plan on `getswaplane.com` / `swaplane.dev` / `.io` (verify). A web search found no product named Swaplane, but this is **not** trademark clearance. Before public release: register the `.app` domain now, search USPTO/EUIPO/WIPO (software classes 9 and 42) and the App Store, ideally with an attorney. Never use any vendor's name or logo in the app name or icon.
