# Architecture — Swaplane

## Overview

A single signed app bundle containing:

- **Swaplane.app** — SwiftUI/AppKit UI, owns the Vault, SwitchEngine, UsageService. Runs as an agent-style app (`LSUIElement` configurable: menu-bar-only by default, Dock icon while the main window is open).
- **`swaplane` CLI** — bundled at `Swaplane.app/Contents/Resources/bin/swaplane`, symlinked to `/usr/local/bin` (user-approved) in v0.4. A thin client: it never touches the Keychain itself; it asks the app over IPC.
- **IPC** — Unix domain socket in `~/Library/Application Support/Swaplane/run/ctl.sock` (mode 0600) or an XPC service; peer validated with `LOCAL_PEERCRED`/code-signature requirement. The app auto-launches headless if not running (`open -a Swaplane --args --headless`).

```
 UI (SwiftUI)   CLI (swaplane)   App Intents (v0.5)
        \             |              /
         ----- AppServices (actors) -----
         SwitchEngine   Vault   UsageService   ProjectRules
                |          |          |
            Adapters   Keychain   Usage providers
        (Claude, Codex, ChatGPT)
```

## Modules (SwiftPM targets)

| Module | Responsibility | Depends on |
|---|---|---|
| `SwaplaneCore` | `Profile`, `Tool`, `Redacted<T>`, errors, `Paths`, logging facade | — |
| `Vault` | Keychain wrapper, snapshot encrypt/decrypt, access control, backup (v0.5) | Core |
| `Adapters` | `ToolAdapter` protocol + `ClaudeDesktopAdapter`, `ClaudeCodeAdapter`, later Codex/ChatGPT | Core, Vault |
| `SwitchEngine` | Transactional switch, process control, journal/rollback | Core, Vault, Adapters |
| `Usage` | `UsageProvider` protocol, polling scheduler, cache | Core, Vault, Adapters |
| `Automation` | Shell hook, project rules, App Intents | Core, SwitchEngine |
| `SwaplaneUI` | Views, status item, popover, palette, onboarding | all |
| `swaplane-cli` | ArgumentParser CLI client | Core (IPC types only) |

## Data model

```swift
struct Profile: Codable, Identifiable, Sendable {
    let id: UUID                  // identity of the profile — NOT the email
    var tool: Tool                // .claudeDesktop, .claudeCode, .codexCLI, .chatgptDesktop
    var label: String
    var identityHint: String?     // email/org for display only; may be absent
    var color: ProfileColor
    var emoji: String?
    var createdAt: Date
    var lastUsedAt: Date?
    var schemaVersion: Int
}
```

- **Non-secret metadata**: `~/Library/Application Support/Swaplane/profiles.json` (atomic writes, `0600`). Contains no tokens. Identity hints may be masked in UI.
- **Secrets**: Keychain, service `app.swaplane.vault`, account `"<profileUUID>:<kind>"` where kind ∈ `credential`, `snapshotKey`. Values are opaque blobs.
- **Snapshots**: `~/Library/Application Support/Swaplane/snapshots/<profileUUID>.sealed` — AES-256-GCM (CryptoKit) over a tar/AppleArchive of the profile's state files; key in Keychain (`snapshotKey`). File carries a small header (magic, version, nonce).
- **State**: `state.json` — active profile per tool, last-switch records, per-shell overrides (v0.4), project rules (v0.4).
- **Audit log**: `activity.log` (JSON lines, no secrets), rotated at 1 MB.
- **Backups before overwrite**: `~/Library/Application Support/Swaplane/rollback/<tool>/<timestamp>.sealed` (encrypted the same way), keep last 3.

## ToolAdapter protocol

```swift
protocol ToolAdapter: Sendable {
    var tool: Tool { get }
    /// Installed? Version? Is that version verified/supported?
    func probe() async -> ToolProbe
    /// Read the live logged-in identity without side effects.
    func detectCurrentIdentity() async throws -> DetectedIdentity?
    /// Capture live state into a StateBundle (files + keychain items) for a profile.
    func capture() async throws -> StateBundle
    /// Make bundle the live state. Called only inside a SwitchEngine transaction.
    func apply(_ bundle: StateBundle) async throws
    /// Put the tool into a logged-out/empty state for "create empty profile".
    func prepareEmpty() async throws
    /// Processes that must be stopped before capture/apply (desktop apps).
    var runningProcessPredicate: ProcessPredicate? { get }
    /// Relaunch after apply (desktop apps).
    func relaunch() async throws
    /// Validate after apply: identity matches expectation, tool can read state.
    func verify(expected: Profile) async throws
    /// Optional usage (v0.2).
    func usageProvider() -> UsageProvider?
    /// Env vars for per-shell activation (CLI adapters, v0.4).
    func shellEnvironment(for profile: Profile) async throws -> [String: String]?
}
```

`StateBundle` = `{ files: [RelativePath: Data/Stream], keychainItems: [KeychainItemRef: Redacted<Data>], metadata }`. Large trees stream through the archiver rather than loading into memory.

## Switch transaction (SwitchEngine)

For `switch(tool, to target)`:

1. **Preflight** — adapter `probe()` says supported; Touch ID gate (v0.2); target snapshot exists and decrypts; disk space check; no other switch in flight for that tool (actor-serialized).
2. **Stop** — if desktop app running: request graceful quit (`NSRunningApplication.terminate()`), wait up to 10 s, then prompt user before force quitting. CLI adapters: no process stop required, but warn if a CLI session is active (best effort).
3. **Backup** — `capture()` live state → rollback store (encrypted).
4. **Capture-back** — if a current active profile exists, update *its* snapshot with the just-captured live state (preserves refreshed tokens and in-app changes). This is the critical anti-data-loss step.
5. **Apply** — `apply(targetBundle)`. Writes use temp + atomic rename; Keychain updates use add-or-update; never delete before the new value is written.
6. **Journal** — write `journal.json` (`started`, `captured`, `applied`) before each phase so a crash can be recovered on next launch (recover = roll back to backup).
7. **Relaunch** — desktop adapters relaunch the app.
8. **Verify** — `verify()`; on failure → **rollback** (apply backup bundle, relaunch) and surface error.
9. **Commit** — update `state.json` active profile, `lastUsedAt`, audit log; clear journal; prune old backups.

All steps are idempotent where possible. The engine exposes progress as an `AsyncStream<SwitchProgress>` for UI/CLI.

### Side-by-side mode (optional, desktop Electron apps)

Instead of swap-in-place, launch a second instance with `--user-data-dir=<profile dir>` using a decrypted working copy under a Swaplane-managed directory (permissions 0700), re-sealed on quit. Behind a per-tool capability flag from SPIKE-0 findings; not in v0.1 unless spike shows it's trivial.

## Process control

- Find apps via bundle ID using `NSWorkspace.shared.runningApplications`.
- Launch with `NSWorkspace.openApplication(at:configuration:)`.
- Never `kill -9` without explicit user confirmation.

## Usage (v0.2)

- `UsageProvider.fetch(for profile) async throws -> UsageSnapshot` where `UsageSnapshot = { windows: [UsageWindow(label, usedFraction, resetsAt)], planName?, fetchedAt }`.
- `UsageService` actor: polls active + recently used profiles (default 60 s active, 5 min others, exponential backoff on errors, pause on battery saver / sleep / lock), caches last good snapshot, exposes `AsyncStream`.
- Reads the profile's credential **from the Vault at call time**, uses it in memory only, never persists.
- Endpoints per ADAPTERS.md; all behind `FeatureFlags.liveUsage`.

## Security gate (v0.2)

`AuthGate` actor wrapping `LocalAuthentication` (`LAContext`, policy `.deviceOwnerAuthentication`, reuse window configurable: always / 1 min / 5 min / until lock). Keychain items for credentials created with `SecAccessControl` (`.userPresence` optional per setting). See SECURITY.md.

## Per-shell and per-project (v0.4)

- `swaplane shell-hook zsh|bash|fish` prints a snippet adding a `precmd`/`chpwd` hook that calls `swaplane env --shell` and `eval`s exports (e.g. `CLAUDE_CONFIG_DIR`, `CODEX_HOME`).
- Per-shell profiles use **materialized config dirs** under `~/Library/Application Support/Swaplane/shells/<profileUUID>/` (0700) so a shell can use a profile without changing the global live state. Credentials for these are written to a Keychain service name the tool derives from the dir (see SPIKE-0), never to plaintext files unless the tool only supports file storage — in which case use files with 0600 inside a 0700 dir and flag it in Security settings.
- Project rules: `.swaplane` file (TOML: `claude = "<profile label or uuid>"`) discovered walking up from `$PWD`; global fallback list in `state.json`. Trust prompt the first time a rule from a new path is applied.

## Concurrency and reliability

- All mutations go through `SwitchEngine` actor; Vault is an actor; UI observes via `@Observable` view models on `@MainActor`.
- File watching (`DispatchSource`/FSEvents) on tool state dirs to detect external logins/logouts and flag profile drift ("Active profile no longer matches live identity").
- Every external call has timeouts and cancellation.

## Distribution

- Developer ID signing, Hardened Runtime, notarization via `notarytool`, DMG packaging script in `scripts/`.
- Entitlements: none sandbox-related; `com.apple.security.automation.apple-events` only if needed for quitting apps (prefer `NSRunningApplication`, avoid).
- Keychain access group shared between app and helper(s) if needed: `$(TeamIdentifierPrefix)app.swaplane`.
- Sparkle (v0.5): EdDSA-signed appcast, hosted statically.
- **Mac App Store is not a target for the main app.** Swaplane must read and write other apps' data folders and Keychain items, which the App Store's mandatory App Sandbox forbids. Primary channel: notarized Developer ID DMG from the project's own site (+ optional Homebrew cask later).
- Optional future: a separate, sandboxed "Swaplane Companion" App Store product (usage viewer / launcher only, no switching engine). Out of scope for v0.1–v0.5; decide after v1.0.

## Decisions log

_(append dated entries as SPIKE-0 and implementation refine this document)_
