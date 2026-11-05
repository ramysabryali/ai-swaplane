# Testing — Swaplane

## Principles

- **Never touch the developer's real credentials or real tool state in automated tests.** All tests run against a sandboxed `HOME` and an isolated Keychain.
- Fast unit tests for logic; fixture-based integration tests for adapters; a manual checklist for things that need real apps/displays.

## Layers

| Layer | Tooling | What |
|---|---|---|
| Unit | XCTest / Swift Testing | Models, Redacted, snapshot crypto (round-trip, tamper → fail, wrong key → fail), journal state machine, project-rule parsing, usage parsing |
| Adapter integration | XCTest + temp dirs | Fixture trees mimicking each tool's layout; `capture`/`apply` round-trips; failure injection |
| Keychain | XCTest with a **test keychain** | Create via `SecKeychainCreate` in a temp file (or a unique `kSecAttrService` prefix `app.swaplane.test.<uuid>` cleaned up in `tearDown`). Never touch the login keychain items of real tools. |
| Engine | XCTest with fake adapter + fake process controller | Transaction order, rollback on failure at each phase, crash-recovery from journal, concurrent switch serialization |
| UI | SwiftUI previews + ViewInspector-style tests (optional) + XCUITest smoke | Popover renders, row click triggers switch intent |
| Manual | Checklist below | Real apps, real displays, Touch ID |

## Dependency injection seams (build these in from the start)

- `FileSystem` protocol (real / in-memory or temp-root).
- `KeychainClient` protocol (real / test).
- `ProcessController` protocol (list/quit/launch apps).
- `Clock` and `HTTPClient` protocols (usage tests with canned responses; verify host allowlist).
- `Paths` resolves from an injected `home` URL.

## Fixtures

`Tests/Fixtures/<tool>/<scenario>/` with **synthetic** data only: fake tokens like `FAKE-ACCESS-TOKEN-0001`, emails `alice@example.test`. Scenarios: `signed-in-A`, `signed-in-B`, `logged-out`, `same-email-two-profiles`, `expired-token`, `unsupported-version`, `corrupt-config`.

## Required test cases (engine/adapters)

1. A→B→A round-trip restores A exactly (modulo permitted refreshed-token differences).
2. Capture-back: modify live state while A active, switch to B, back to A → modification preserved.
3. Failure injection at each phase (preflight, stop, backup, apply, relaunch, verify) → state restored to pre-switch; error surfaced; journal cleared.
4. Simulated crash after `captured` and after `applied` → next launch recovery rolls back or completes deterministically.
5. Two profiles with the same email remain independent after edits to either.
6. Concurrent switch requests for the same tool are serialized; for different tools may run in parallel.
7. Switching when the tool isn't installed / never signed in yields clear, non-destructive errors.
8. File permissions: created files 0600, dirs 0700.
9. Log capture test: run a full switch with `FAKE-` tokens and assert no `FAKE-` token substring appears in any log output or error description.
10. Snapshot tamper test: flip one byte → decrypt fails and profile marked corrupted, live state untouched.

## Commands (keep current)

```bash
swift build
swift test
swift test --filter VaultTests
# App bundle (once App/ project exists)
xcodebuild -scheme Swaplane -configuration Debug build
xcodebuild -scheme Swaplane test
# Format / lint
swift format lint -r Sources Tests
```

## CI (GitHub Actions, macOS runner)

- Jobs: build, test, format-lint, **secret scan** (gitleaks), **host allowlist check** (script greps source for URL hosts not in allowlist), `codesign` verification on release builds.
- No secrets in CI for tests; signing/notarization only on tagged release workflow.

## Manual checklist (per milestone, on real hardware)

- [ ] Clean macOS user account: onboarding detects nothing → empty state OK.
- [ ] Import real logged-in account for each in-scope tool; identity shown correctly.
- [ ] Switch A↔B ten times for each tool; tools open signed in as expected.
- [ ] Switch while the desktop app has an unsent draft → warning shown, no data loss beyond documented.
- [ ] Kill Swaplane mid-switch → relaunch recovers.
- [ ] Display matrix from UX.md (1 display, 2 displays, unplug during popover, fullscreen app).
- [ ] VoiceOver walkthrough of popover and main window.
- [ ] Dark/Light, increased contrast, reduced motion.
- [ ] Security checklist from SECURITY.md.
- [ ] Fresh-install of notarized DMG on a second Mac passes Gatekeeper.
