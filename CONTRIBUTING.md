# Contributing

Thanks for helping. A few ground rules keep the project safe:

1. **Never put real credentials in code, tests, issues, or screenshots.** Tests use synthetic fixtures and a temporary home folder.
2. **No plaintext secrets on disk and none in logs.** Wrap anything sensitive in `Redacted`. See [docs/SECURITY.md](docs/SECURITY.md).
3. **No telemetry, and no new network hosts** without discussion first.
4. **Switching stays transactional:** capture current state, back up, apply, verify, and roll back on failure.
5. Facts about other apps (file paths, Keychain names, endpoints) live in each adapter's `Constants.swift`. Mark them `// VERIFIED: <date>` once you've confirmed them on a real machine.

## Set up

```bash
swift build
swift test
./scripts/make-app.sh debug
open "build/AI Swaplane.app"
```

You need macOS 14+ and Xcode 16+ (Swift 6, strict concurrency). `swift format` default settings are used.

To check the UI without real accounts, run `swift run SwaplaneApp --snapshot <folder>`. It renders the panel with sample data to PNGs.

## Pull requests

- Keep them small and focused, with tests for behaviour changes.
- Describe what changed and how you checked it. Include a screenshot for UI changes, made with sample data.
- Ask before adding a dependency, an entitlement, or a network endpoint.

The architecture and design notes are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/DESIGN.md](docs/DESIGN.md).
