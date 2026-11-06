# Architecture — AI Swaplane

## Overview

A single app bundle:

- **AI Swaplane.app** — SwiftUI/AppKit UI that owns the Vault, SwitchEngine and UsageService. It runs as a menu bar app (`LSUIElement`). A Dock icon shows only while the Settings or add-account window is open.
- **`swaplane` CLI** — bundled at `AI Swaplane.app/Contents/Resources/bin/swaplane`. It is read-only: it lists saved accounts from non-secret metadata and never touches the Keychain.

```
        UI (SwiftUI + AppKit)
              |
      AppModel (@MainActor)
        /       |        \
 SwitchEngine  Vault   UsageService      (actors)
      |          |          |
   Adapters   Keychain   Claude usage endpoint
 (Claude Code, Claude Desktop)
```

## Modules (SwiftPM targets)

| Module | Responsibility | Depends on |
|---|---|---|
| `SwaplaneCore` | `Profile`, `AccountGroup`, `Tool`, `Redacted<T>`, errors, `Paths`, JSON helpers | — |
| `Vault` | Keychain wrapper, snapshot encrypt/decrypt, profile and group storage | Core |
| `Adapters` | `ToolAdapter` protocol, `ClaudeCodeAdapter`, `ClaudeDesktopAdapter` | Core |
| `SwitchEngine` | Transactional switching, process control, journal and rollback | Core, Vault, Adapters |
| `Usage` | Usage fetch, cache and states | Core |
| `SwaplaneUI` | Views, status item, panel, Settings, icon, sounds | all |
| `SwaplaneApp` | App entry point | UI |
| `swaplane-cli` | Read-only command-line client | Core |

## Data model

- A **Profile** is one tool's saved sign-in: `id` (UUID, never the email), `tool`, `label`, `identityHint`, `groupID`, timestamps.
- An **AccountGroup** is what the UI shows as an account. It links a Claude Code profile and a Claude Desktop profile so one switch moves both. Profiles of different tools with the same identity are merged into one group. Same-tool duplicates stay separate.
- **Non-secret metadata**: `~/Library/Application Support/Swaplane/` — `profiles.json`, `groups.json`, `state.json` (active profile per tool), `usage.json` (cached percentages), `activity.log`. Files are mode 0600, the folder 0700.
- **Secrets**: Keychain, service `app.swaplane.vault`. Per-profile snapshot keys only.
- **Snapshots**: `snapshots/<profileUUID>.sealed` — AES-256-GCM over the profile's state files; the key is in the Keychain.
- **Rollback backups**: `rollback/<tool>/<timestamp>.sealed`, encrypted the same way, last 3 kept.

## ToolAdapter

```swift
public protocol ToolAdapter: Sendable {
    var tool: Tool { get }
    var processBundleID: String? { get }          // desktop app to quit during a swap
    func probe() async -> ToolProbe               // installed? version supported?
    func detectCurrentIdentity() async throws -> DetectedIdentity?
    func capture() async throws -> StateBundle
    func apply(_ bundle: StateBundle) async throws
    func prepareEmpty() async throws              // sign out so another account can sign in
    func verify(expectedIdentityKey: String?) async throws
}
```

All paths, Keychain names and endpoints for a tool live in that adapter's `Constants.swift`.

## Switch transaction

For `switch(tool, to profile)`:

1. **Preflight** — the adapter supports this version, the target snapshot exists and decrypts, and no other switch is running for that tool.
2. **Stop** — a running desktop app is asked to quit and waited for; the user is never force-quit silently.
3. **Backup** — the live state is captured into the rollback store.
4. **Capture-back** — the live state is saved into the currently active profile, so refreshed tokens and in-app changes aren't lost. Skipped when the live account has drifted from the active profile.
5. **Apply** — the target state is written with atomic writes. Nothing is deleted before the new value exists.
6. **Journal** — `journal.json` records each phase, so a crash is recovered on the next launch by rolling back.
7. **Relaunch and verify** — desktop apps are reopened and the live identity is checked. On failure the backup is restored.
8. **Commit** — `state.json` and the activity log are updated and the journal is cleared.

Switching an account runs one transaction per tool, Claude Code first. A failure in one tool never rolls back the other.

## Usage

`UsageService` reads the live Claude Code credential from the Keychain at call time, asks Anthropic's usage endpoint for the session and weekly windows, and caches only percentages and reset times per account. It never refreshes tokens. States: fresh, stale, expired, unavailable, none. Usage can be switched off in Settings, and it never blocks switching.

## Concurrency and reliability

- All mutations go through the `SwitchEngine` actor. The Vault is an actor. The UI observes `@Observable` models on `@MainActor`.
- Every external call has a timeout.

## Distribution

- Not sandboxed: it must read and write other apps' data folders and Keychain items. Hardened Runtime is on.
- Releases are built with `scripts/release.sh`. Notarization needs a Developer ID Application identity.
- The Mac App Store is not a target, because the App Sandbox forbids what the app does.
