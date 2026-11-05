# Roadmap — Swaplane

Order is fixed. Each milestone has its own spec in [milestones/](milestones). Do SPIKE-0 first.

| Milestone | Scope | Spec |
|---|---|---|
| **Spike 0** | Verify tool storage assumptions (read-only) | [SPIKE-0.md](SPIKE-0.md) |
| **v0.1** | Claude Desktop + Claude Code, import wizard, menu bar switcher, Keychain storage, multi-display | [v0.1](milestones/v0.1-claude-core.md) |
| **v0.2** | Live usage (menu bar + popover), Touch ID gate | [v0.2](milestones/v0.2-usage-and-gate.md) |
| **v0.3** | Codex CLI, then ChatGPT desktop | [v0.3](milestones/v0.3-codex-chatgpt.md) |
| **v0.4** | Per-shell and per-project switching | [v0.4](milestones/v0.4-shell-and-projects.md) |
| **v0.5** | Hotkey palette, App Intents, encrypted backup, auto-update | [v0.5](milestones/v0.5-polish-and-release.md) |

## Cross-cutting (every milestone)

- Security checklist in SECURITY.md
- Accessibility pass (VoiceOver, keyboard, contrast)
- Multi-display manual test
- Update ADAPTERS.md "Verified" tables and Decisions logs
- Keep `docs/TESTING.md` commands accurate

## Deferred ideas (not scheduled)

Groups (one-click "Work" bundle across tools), API-key profiles, Gemini/Cursor adapters, widgets, usage history charts, team/org features, MCP-config-per-profile UI, Homebrew cask distribution, localized UI.

## Release gating

v1.0 = v0.5 + 2 weeks of dogfooding + security review + notarized signed DMG + trademark/domain cleared + public SECURITY_CONTACT.md.
