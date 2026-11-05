# CLAUDE.md — Swaplane

Guidance for Claude Code when working in this repository. Read this first, then the docs it points to.

## What this project is

**Swaplane** is a native, standalone macOS app (menu bar + main window) that lets users switch between multiple accounts of AI tools — desktop apps and CLIs — safely and instantly. First target: Claude (Desktop + Claude Code). Then Codex CLI, then ChatGPT desktop.

Core idea: a **Profile** = (tool, identity, isolated state bundle). Profiles are keyed by UUID, **never by email**, so the same email can have several independent profiles.

## Read before coding

| Doc | Purpose |
|---|---|
| [docs/PRODUCT.md](docs/PRODUCT.md) | Vision, personas, scope, non-goals |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, data model, switch transaction, IPC |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model and **hard security rules** |
| [docs/ADAPTERS.md](docs/ADAPTERS.md) | Per-tool storage locations, switch recipes, usage sources |
| [docs/UX.md](docs/UX.md) | Menu bar, main window, multi-display behavior |
| [docs/TESTING.md](docs/TESTING.md) | Test strategy and fixtures |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones v0.1–v0.5 |
| [docs/milestones/](docs/milestones) | Per-milestone tasks + acceptance criteria |
| [docs/SPIKE-0.md](docs/SPIKE-0.md) | **Do this first** — verify assumptions about tool storage |

## Non-negotiable rules

1. **No plaintext secrets on disk. Ever.** Tokens, refresh tokens, API keys and snapshot encryption keys live only in the Keychain. See SECURITY.md.
2. **Never log secrets.** Use the `Redacted` wrapper type for any value that could be sensitive. No tokens in logs, crash reports, error messages, or test snapshots.
3. **No telemetry.** The only network calls allowed are usage polling to each vendor's own endpoints (v0.2+) and the update feed (v0.5). Nothing else.
4. **Switching must be transactional.** Always capture-back current state, back up before overwriting, and roll back on failure. See ARCHITECTURE.md §Switch transaction.
5. **Facts about third-party tools are unverified until SPIKE-0 confirms them.** Paths, Keychain item names and endpoints in ADAPTERS.md come from prior knowledge and may have changed. Put every such constant behind the adapter's `Constants.swift` and mark with `// VERIFIED: <date>` once confirmed on a real machine. Never hardcode them elsewhere.
6. **Undocumented usage endpoints are optional.** Usage features must degrade gracefully (show "unavailable"), sit behind a feature flag, and never block switching.
7. **Never touch a user's real credentials in automated tests.** Use fixtures and a temp `HOME`. See TESTING.md.

## Tech stack and conventions

- Swift 6 (strict concurrency), macOS 14+ deployment target, SwiftUI + AppKit where SwiftUI falls short (`NSStatusItem`, `NSPanel`).
- Swift Package Manager for all logic modules; one thin Xcode project/target for the app bundle, helper and CLI.
- Dependencies: keep minimal. Allowed: `swift-argument-parser`, `Sparkle` (v0.5 only). Everything else needs justification in the PR description.
- Not sandboxed (needs other apps' data dirs). Hardened Runtime on. Developer ID distribution, notarized. **Not** Mac App Store.
- Concurrency: actors for stateful services (`Vault`, `SwitchEngine`, `UsageService`); no global mutable state.
- Errors: typed `enum` errors per module, conforming to `LocalizedError` with user-presentable text that contains no secrets.
- Style: `swift-format` default config; public APIs documented with `///`.

## Repo layout (target)

```
Swaplane/
├── CLAUDE.md
├── README.md
├── docs/
├── Package.swift              # app executable = SwaplaneApp, CLI product = swaplane
├── Sources/
│   ├── SwaplaneCore/        # models, Profile, errors, Redacted, paths
│   ├── Vault/                 # Keychain + encrypted snapshots
│   ├── SwitchEngine/          # transactional switching, process control
│   ├── Adapters/              # ToolAdapter protocol + Claude/Codex/ChatGPT
│   ├── Usage/                 # usage providers + polling (v0.2)
│   ├── Automation/            # shell hook, project rules, App Intents (v0.4–0.5)
│   ├── SwaplaneUI/          # SwiftUI views, menu bar, palette
│   └── swaplane-cli/        # CLI executable
├── App/                       # Xcode project: app bundle, entitlements, Info.plist
└── Tests/
```

## Working agreements

- Implement **one milestone at a time**, in order. Each milestone doc has a checklist and acceptance criteria; do not start the next until acceptance passes.
- Prefer small, reviewable commits. Do not commit unless asked.
- When a spec detail is ambiguous or contradicted by SPIKE-0 findings, update the doc in the same change and note it under "Decisions log" at the bottom of the relevant doc.
- Ask before adding dependencies, entitlements, or any network endpoint.
- Build/test commands live in [docs/TESTING.md](docs/TESTING.md); keep them current.
