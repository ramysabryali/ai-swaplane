# Swaplane

> One-click account switching for your AI tools on macOS — desktop apps and CLIs, from the menu bar.

**Status:** specification stage. This repo currently contains the full spec set for implementation with Claude Code. Start with [CLAUDE.md](CLAUDE.md) and [docs/SPIKE-0.md](docs/SPIKE-0.md).

## Features (planned)

- Switch **Claude Desktop** and **Claude Code** accounts; later **Codex CLI** and **ChatGPT desktop**
- Menu bar switcher that works on every display
- Auto-detects accounts you're already logged into
- Separate state per profile — even for the same email
- Credentials stored in the macOS Keychain, snapshots encrypted at rest, Touch ID gate
- Live usage meters and reset countdowns
- Per-terminal and per-project account selection
- Global hotkey palette, Shortcuts/Spotlight integration, encrypted backup
- Fully native, standalone, no telemetry

## Roadmap

| Version | Scope |
|---|---|
| v0.1 | Claude Desktop + Claude Code, import wizard, menu bar switcher, Keychain storage |
| v0.2 | Live usage, Touch ID gate |
| v0.3 | Codex CLI, then ChatGPT desktop |
| v0.4 | Per-shell and per-project switching |
| v0.5 | Hotkey palette, App Intents, encrypted backup, auto-update |

Details: [docs/ROADMAP.md](docs/ROADMAP.md).

## Documentation

- [Product](docs/PRODUCT.md) · [UX](docs/UX.md) · [Architecture](docs/ARCHITECTURE.md)
- [Security](docs/SECURITY.md) · [Adapters](docs/ADAPTERS.md) · [Testing](docs/TESTING.md)
- [Spike 0](docs/SPIKE-0.md) · [Milestones](docs/milestones)

## Responsible use

Swaplane is for keeping legitimately separate accounts apart (work vs personal, client vs own). It is not designed to circumvent usage limits or vendor terms. Users are responsible for complying with each service's terms.
