# Verification notes

**Run:** 2026-11-05, macOS 27.2, one developer machine. **Mode:** read-only (no files, Keychain items or app state were modified; no secret values were read or printed; emails/UUIDs below are masked or omitted).

## Summary

| Area | Call | One-line reason |
|---|---|---|
| Claude Code — global switch (`credentialsOnly`) | **GO** | Credential in login Keychain, rewritten in place on refresh; identity readable without secrets |
| Claude Desktop | **GO, with allowlist** | Auth is in `Cookies` + `config.json`; data dir is ~15 GB so whole-dir snapshot is impossible |
| Live usage (Claude) | **UNVERIFIED** | Endpoint not called in this spike (would need the access token); keep feature-flagged |
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

## Platform

- Not tested: external display behavior of `NSStatusItem`, `SecItem` prompts for items created by other apps, cross-binary Keychain sharing (app ↔ CLI helper). These are still open.
- Unrelated observation: `security dump-keychain` listing (names only) did not prompt for any item.

## Follow-ups (open)

1. Run the side-by-side `--user-data-dir` test for Claude Desktop (consent required).
2. Read Safe Storage ACL (trusted apps) to learn whether Swaplane will trigger a Keychain prompt.
3. Test Claude usage endpoint with a throwaway/own token in a controlled run; confirm response shape.
4. Verify external-display status item behavior on hardware.

## Usage spike (2026-11-06, approved)

One read-only call from a script (token read from the `Claude Code-credentials` Keychain item, never printed):

- Credential JSON keys: `accessToken, expiresAt, rateLimitTier, refreshToken, refreshTokenExpiresAt, scopes, subscriptionType`. `subscriptionType` is present (e.g. `pro`).
- `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <access token>` and `anthropic-beta: oauth-2025-04-20` **answers** (HTTP 401, `authentication_error`) — the endpoint exists and is reachable.
- The live access token had **already expired** (the CLI refreshes lazily when it next runs). So a successful response, and therefore the **JSON shape, is still unverified**; the parser assumes `five_hour` / `seven_day` objects with `utilization` and `resets_at` (community-reported shape).
- Consequence for the design: saved tokens of inactive accounts will usually be expired, and Swaplane must not refresh them. Usage is therefore fetched only for the account live in Claude Code (when its token is valid), cached per account, and shown as "last known" for the others. When the live token is expired the UI says "Open Claude Code to refresh usage".
- To verify the shape: run `claude` once (it refreshes its token), then re-run the spike within the token lifetime.

Decisions log: usage states are `fresh / stale / expired / unavailable / none`; refreshing tokens remains out of scope until rotation behaviour is tested.
