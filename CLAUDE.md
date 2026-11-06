# CLAUDE.md — AI Swaplane

Guidance for Claude Code when working in this repository. Read this first, then the docs it points to.

## What this project is

**AI Swaplane** (display name; module and CLI names stay `Swaplane*` / `swaplane`) is a native macOS menu bar app that lets users switch between multiple Claude accounts (Claude Code and Claude Desktop) safely and instantly.

Core idea: a **Profile** = (tool, identity, isolated state bundle). Profiles are keyed by UUID, **never by email**, so the same email can have several independent profiles. An **AccountGroup** links a Claude Code profile and a Claude Desktop profile into the account the UI shows.

## Read before coding

| Doc | Purpose |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, data model, switch transaction |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model and **hard security rules** |
| [docs/ADAPTERS.md](docs/ADAPTERS.md) | Per-tool storage locations, switch recipes, usage source |
| [docs/DESIGN.md](docs/DESIGN.md) | Panel, menu bar item, settings and brand |
| [docs/TESTING.md](docs/TESTING.md) | Test strategy and fixtures |
| [docs/SPIKE-0-FINDINGS.md](docs/SPIKE-0-FINDINGS.md) | What was verified on a real machine |

## Non-negotiable rules

1. **No plaintext secrets on disk. Ever.** Tokens, refresh tokens, API keys and snapshot encryption keys live only in the Keychain. See SECURITY.md.
2. **Never log secrets.** Use the `Redacted` wrapper type for any value that could be sensitive. No tokens in logs, crash reports, error messages, or test snapshots.
3. **No telemetry.** The only network call allowed is the optional usage check to the vendor's own endpoint. Nothing else.
4. **Switching must be transactional.** Always capture-back current state, back up before overwriting, and roll back on failure. See ARCHITECTURE.md §Switch transaction.
5. **Facts about third-party tools can change.** Put every path, Keychain item name and endpoint behind the adapter's `Constants.swift` and mark it `// VERIFIED: <date>` once confirmed on a real machine. Never hardcode them elsewhere.
6. **Undocumented usage endpoints are optional.** Usage features must degrade gracefully (show "unavailable") and never block switching.
7. **Never touch a user's real credentials in automated tests.** Use fixtures and a temp `HOME`. See TESTING.md.

## Tech stack and conventions

- Swift 6 (strict concurrency), macOS 14+ deployment target, SwiftUI + AppKit where SwiftUI falls short (`NSStatusItem`, `NSPanel`).
- Swift Package Manager only; `scripts/make-app.sh` assembles the app bundle.
- Dependencies: none today. Ask before adding one.
- Not sandboxed (needs other apps' data dirs). Hardened Runtime on. **Not** Mac App Store.
- Concurrency: actors for stateful services (`Vault`, `SwitchEngine`, `UsageService`); no global mutable state.
- Errors: typed `enum` errors per module, conforming to `LocalizedError` with user-presentable text that contains no secrets.
- Style: `swift-format` default config; public APIs documented with `///`.

## Repo layout

```
├── Package.swift              # app executable = SwaplaneApp, CLI product = swaplane
├── Sources/
│   ├── SwaplaneCore/          # models, Profile, errors, Redacted, paths
│   ├── Vault/                 # Keychain + encrypted snapshots
│   ├── SwitchEngine/          # transactional switching, process control
│   ├── Adapters/              # ToolAdapter protocol + Claude adapters
│   ├── Usage/                 # usage fetch, cache, states
│   ├── SwaplaneUI/            # SwiftUI views, menu bar, settings, icon
│   ├── SwaplaneApp/           # app entry point
│   └── swaplane-cli/          # read-only CLI
├── Tests/
├── scripts/                   # make-app, install, uninstall, release
└── docs/
```

## Working agreements

- Prefer small, reviewable commits. Do not commit unless asked.
- When a doc is contradicted by what you find on a real machine, update the doc in the same change.
- Ask before adding dependencies, entitlements, or any network endpoint.
- Build/test commands live in [docs/TESTING.md](docs/TESTING.md); keep them current.
