# SPIKE-0 Findings

**Run:** 2026-11-05, macOS 27.2, one developer machine. **Mode:** read-only (no files, Keychain items or app state were modified; no secret values were read or printed; emails/UUIDs below are masked or omitted).

## Summary

| Area | Call | One-line reason |
|---|---|---|
| Claude Code — global switch (`credentialsOnly`) | **GO** | Credential in login Keychain, rewritten in place on refresh; identity readable without secrets |
| Claude Code — per-shell (v0.4) | **NEEDS FOLLOW-UP** | `CLAUDE_CONFIG_DIR` items exist (hash-suffixed) but hash scheme not yet derived |
| Claude Desktop | **GO, with allowlist** | Auth is in `Cookies` + `config.json`; data dir is ~15 GB so whole-dir snapshot is impossible |
| Codex (CLI/desktop shared `~/.codex`) | **GO** | Plain `auth.json` (0600), no Keychain; local rate-limit data available |
| "ChatGPT desktop" | **NEEDS REDESIGN** | `/Applications/ChatGPT.app` is actually the Codex app (`com.openai.codex`); real ChatGPT chat store not identified |
| Live usage (Claude) | **UNVERIFIED** | Endpoint not called in this spike (would need the access token); keep feature-flagged |
| Live usage (Codex) | **GO (local)** | `rate_limits` events in session logs |
| Multi-display menu bar | **NOT TESTED** | Needs external display hardware test |

## Claude Code — CLI 1.0.83 (local npm install) — verified 2026-11-05

- Install: `claude` is a shell **alias** to `~/.claude/local/claude` (npm local install), not a binary on `PATH`. Adapters must locate the CLI by probing known locations, not only `which`. Another Claude Code build is also bundled inside Claude Desktop (`Application Support/Claude/claude-code`, ~560 MB) — it shares the same Keychain service.
- Credential location: login keychain, generic password, service **`Claude Code-credentials`** (account = macOS username). Created 2025-08-16; **modified today** → the CLI refreshes tokens by rewriting the *same* item. ✅ confirms capture-back is essential.
- **12 additional items** named `Claude Code-credentials-<8 hex>` exist. These are the per-`CLAUDE_CONFIG_DIR` items (confirms the "service name gets a suffix" assumption). **The suffix is not `sha256(configDirPath)[:8]`** — tried 13 candidate paths, 0 matches. Derivation still unknown → see Follow-ups.
- Identity (no secrets): `~/.claude.json` (mode 0600) → `oauthAccount` with keys: `accountUuid, billingType, displayName, emailAddress, fullName, organizationName, organizationRole, organizationType, organizationUuid, seatTier, subscriptionCreatedAt, userRateLimitTier, workspaceRole, …`. Note `~/.claude.json` is large and holds caches, `projects`, `userID`, `machineID` — **do not swap the whole file**; merge `oauthAccount` only.
- Non-interactive identity command exists: **`claude auth status`** prints JSON (`loggedIn`, `authMethod`, …). Preferred `verify()` mechanism.
- Config dir `~/.claude/` contains `settings.json`, `projects/`, `history.jsonl`, `plugins/`, `skills/`, etc. (`fullIsolation` candidate).
- Env var `CLAUDE_CONFIG_DIR` not set on this machine (default mode).
- Not verified: exact credential JSON field names (requires reading the secret value; deliberately skipped), usage endpoint behavior.

## Claude Desktop — 4.16336.0 — bundle `com.anthropic.claudefordesktop` — verified 2026-11-05

- Electron app; no `LSMultipleInstancesProhibited` key in Info.plist. Helper processes run with `--user-data-dir=<default dir>`.
- Data dir `~/Library/Application Support/Claude` is **~15 GB**. Breakdown: `vm_bundles` 11 GB, `Cache` 1.3 GB, `claude-code` 561 MB, `Code Cache` 375 MB, `claude-code-vm` 316 MB, `local-agent-mode-sessions` 204 MB; actual auth/UI state is only a few MB. ⇒ **Snapshot by allowlist, never the whole dir.**
- Auth state:
  - `Cookies` (SQLite, values encrypted): `.claude.ai` cookies incl. `sessionKey`, `sessionKeyLC`, `sessionKeyV3`, `sessionKeyV3LC`, `lastActiveOrg`, `routingHint`, `cf_clearance`, plus analytics cookies.
  - `config.json` keys include `oauth:tokenCache`, `oauth:tokenCacheV2`, `lastKnownAccountUuid`, and account-scoped keys of the form `dxt:allowlist*:<orgUuid>`.
  - Candidates to include in the allowlist: `Cookies` (+ `-journal`), `Local Storage`, `Session Storage`, `IndexedDB`, `Partitions`, `Network Persistent State`, `Preferences`, `Local State`, `config.json`, `Trust Tokens*`, `SharedStorage`, `WebStorage`, `ant-did`, `ant-device-registry.json`, `Service Worker` (confirm necessity in v0.1).
  - Exclude: `Cache`, `Code Cache`, `GPUCache`, `Dawn*`, `GraphiteDawnCache`, `Crashpad`, `vm_bundles`, `claude-code*`, `sentry`, `blob_storage`(?), `Shared Dictionary`.
- Some content is already account-namespaced on disk: `local-agent-mode-sessions/<accountUuid>/<orgUuid>/…`. These are history, not auth; decide per-profile inclusion (default: exclude from `credentialsOnly`, include in `fullIsolation`).
- Keychain: **`Claude Safe Storage`** (single item, created 2025-08-07, never modified). Because it is shared and stable, encrypted cookie/token values copied between profiles remain decryptable. **Do not touch this item.**
- Identity: signed-in email appears in plain text inside a `claude.ai` IndexedDB blob and in agent-session JSON → there is no clean "identity file". Recommended: read `lastKnownAccountUuid` from `config.json` and map it to a label the user confirms; optionally resolve email via the matching Claude Code `oauthAccount` when `accountUuid` matches.
- **Privacy note:** snapshots contain plaintext PII (emails, conversation blobs) → encryption at rest in the Vault is mandatory (already specified).
- Not verified (needs user consent to launch a second instance): `open -n -a Claude --args --user-data-dir=<tmp>` side-by-side behavior; Safe Storage ACL trusted-app list; graceful-quit duration.

## Codex — `~/.codex` — verified 2026-11-05

- **No `codex` CLI binary on `PATH`** on this machine, but `~/.codex` is populated (used by the Codex desktop app, bundle `com.openai.codex`). The same directory is what the CLI uses, so one adapter should serve both; probe CLI and app separately.
- Credentials: **`~/.codex/auth.json`, mode 0600, file-based — no Keychain item** found for openai/codex/chatgpt. Top-level keys: `OPENAI_API_KEY`, `auth_mode`, `last_refresh`, `tokens{access_token, account_id, id_token, refresh_token}`. Identity: decode `id_token` payload locally.
- `config.toml` (0600) exists; no credential-store key observed in this config (so default = file).
- `CODEX_HOME` not set here; support for the override is documented behavior but **not tested**.
- **Usage (local, no network): session JSONL files contain `rate_limits` events**: `limit_id`, `primary.used_percent`, `primary.window_minutes` (300), `primary.resets_at`, (and likely a secondary window). ✅ Preferred usage source.
- `~/.codex` is large (70 MB+ of state, sqlite DBs, sessions): `credentialsOnly` must copy `auth.json` only.

## "ChatGPT desktop" — verified 2026-11-05

- `/Applications/ChatGPT.app` reports bundle ID **`com.openai.codex`** (v26.1029.x), team `2DC432GLL2`, **not sandboxed**, entitlements include `keychain-access-groups` `2DC432GLL2.*` and `2DC432GLL2.com.openai.shared`. So this is the **Codex desktop app** shipped under the ChatGPT name.
- Data: `~/Library/Application Support/Codex` (192 MB, Chromium-style: `Default`, `Local State`, …) and `~/Library/Application Support/com.openai.chat` (812 KB: per-account-suffixed folders like `conversations-v3-<id>`, `codex-taskItems-*-<id>`, `workspace-data`). Account-namespaced folders mean OpenAI already separates per-account caches.
- No Keychain items matching openai/codex/chatgpt in the login keychain (the app's items, if any, would live in the data-protection keychain under its access group — **not visible to this spike**).
- **Decision:** reframe v0.3 Part 2 as **"Codex Desktop"** (`com.openai.codex`) sharing `~/.codex/auth.json` with the Codex adapter; treat a separate "ChatGPT chat" app as unsupported until its auth store is identified. Verify by test: switch `auth.json` and relaunch the app (needs a second account; not done here).

## Platform

- Not tested: external display behavior of `NSStatusItem`, `SecItem` prompts for items created by other apps, cross-binary Keychain sharing (app ↔ CLI helper). These remain for the v0.1 build.
- Unrelated observation: `security dump-keychain` listing (names only) did not prompt for any item.

## Follow-ups (open)

1. **Derive the `Claude Code-credentials-<suffix>` scheme** (needed for v0.4 per-shell). Safest test: with the user's consent, run `CLAUDE_CONFIG_DIR=$(mktemp -d) claude auth status` and compare Keychain item list before/after; try hashes of the *resolved real path*, with/without trailing slash, other digests (sha1/md5), and the first 8 hex of the digest of a different encoding. Alternatively inspect the installed CLI's JS for the service-name builder (read-only).
2. Run the side-by-side `--user-data-dir` test for Claude Desktop (consent required).
3. Read Safe Storage ACL (trusted apps) to learn whether Swaplane will trigger a Keychain prompt.
4. Obtain a second Codex/ChatGPT account to test `auth.json` swap on the Codex desktop app.
5. Test Claude usage endpoint with a throwaway/own token in a controlled run; confirm response shape.
6. Verify external-display status item behavior on hardware.
