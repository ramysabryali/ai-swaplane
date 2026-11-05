# Adapters — per-tool specs

> **Status:** SPIKE-0 ran on 2026-11-05 — see [SPIKE-0-FINDINGS.md](SPIKE-0-FINDINGS.md). Items marked **Verified** below were confirmed on a real machine; everything else (and all usage endpoints) is still unverified prior knowledge. Record verification date and tool version in each adapter's `Constants.swift`.
>
> Never hardcode these values outside `Constants.swift`. Adapters must refuse to operate (state: *unsupported version*) when the installed tool version is outside the verified range.

Common interface: see `ToolAdapter` in [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 1. Claude Code (CLI) — `claude-code` — v0.1

**Candidate storage**
- Credentials: macOS Keychain generic password, service `Claude Code-credentials` (account = macOS username). Value: JSON containing an OAuth object (access token, refresh token, expiry, scopes, subscription type).
- Account metadata: `~/.claude.json` (e.g. `oauthAccount` with email / org / display name), plus other per-user settings and project history.
- Config dir: `~/.claude/` (settings, MCP, history, projects). Overridable with env `CLAUDE_CONFIG_DIR`.
- API-key users: `ANTHROPIC_API_KEY` env / `apiKeyHelper` — out of scope for v0.1 (detect and show "API key mode, not switchable").

**State bundle for a profile**
- Keychain item value (credential blob).
- Selected parts of `~/.claude.json` (identity block). **Do not** swap the whole file by default — it holds project history and settings the user probably wants shared. Default policy: switch credentials + `oauthAccount` only; "isolate fully" option snapshots the entire config dir (for "separate state for same email" users who want separate history/MCP/settings).
- Per-profile isolation modes (profile setting): `credentialsOnly` (default) · `fullIsolation` (separate config dir per profile).

**Switch recipe (global)**
1. No process stop required; warn if `claude` processes are running (`pgrep -x claude`) — running sessions keep old in-memory token.
2. Capture live Keychain item + `oauthAccount` → active profile snapshot.
3. Write target Keychain item (update in place), merge target `oauthAccount` into `~/.claude.json` atomically (preserve all other keys).
4. Verify: run `claude` with a safe non-interactive status command if available, or re-read identity from files.

**Detect identity**: read `~/.claude.json` → `oauthAccount.emailAddress` (and org); confirm credential exists in Keychain (exists-check only; no secret read needed).

**Per-shell (v0.4)**: set `CLAUDE_CONFIG_DIR=<materialized dir>`. SPIKE-0 must determine how the Keychain service name is derived when this var is set (newer versions may append a hash of the dir), and whether the credentials must be written under that derived name.

**Usage (v0.2)**: candidate undocumented endpoint `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <accessToken>` and header `anthropic-beta: oauth-2025-04-20`; response includes rolling-window utilization (e.g. 5-hour and 7-day) with reset times. Treat as unstable. Handle 401 by flagging "token expired" (do not attempt to refresh tokens ourselves in v0.2 — refreshing rotates the refresh token and could desync from the CLI; only revisit with explicit design).

**Verified** (2026-11-05, CLI 1.0.83 local npm install):
- ✅ Keychain service `Claude Code-credentials` exists in the login keychain; the CLI refreshes tokens by rewriting the same item (modified-date changed same day).
- ✅ `~/.claude.json` (0600) holds `oauthAccount` (`accountUuid`, `emailAddress`, `organizationName`, `organizationUuid`, …) alongside caches/history — merge only `oauthAccount`, never swap the file.
- ✅ `claude auth status` prints identity JSON non-interactively — use it for `verify()`.
- ✅ `CLAUDE_CONFIG_DIR` uses separate Keychain items named `Claude Code-credentials-<8 hex>`; ❌ the suffix is **not** `sha256(path)[:8]` — derivation unknown (blocks v0.4 per-shell; see SPIKE-0-FINDINGS follow-up 1).
- ⚠ The CLI may be a shell alias (`alias claude=~/.claude/local/claude`), not on `PATH`: probe known install locations. Claude Desktop also bundles its own Claude Code build sharing the same Keychain service.
- ❓ Credential JSON field names and usage endpoint: not verified.

---

## 2. Claude Desktop — `claude-desktop` — v0.1

**Candidate storage**
- Bundle ID candidate: `com.anthropic.claudefordesktop` (verify via `mdls -name kMDItemCFBundleIdentifier /Applications/Claude.app`).
- Electron user data dir: `~/Library/Application Support/Claude/` (cookies, Local Storage, IndexedDB, session storage, config JSON).
- Electron `safeStorage` encryption key: Keychain item (typically `Claude Safe Storage`) — shared by all profiles on this Mac; **do not** swap or copy it. Because it's shared, copied encrypted cookies/tokens remain decryptable.

**State bundle**: the user data dir minus regenerable caches (`Cache`, `Code Cache`, `GPUCache`, `DawnCache`, `Crashpad`, `logs`, `blob_storage` if safe — confirm in SPIKE-0). Include: `Cookies`, `Local Storage`, `IndexedDB`, `Session Storage`, `Preferences`, `config.json`-style files, `Network` (cookie/token DBs). Snapshot as Apple Archive/tar → encrypted.

**Switch recipe**: Stop app (graceful) → backup → capture-back → clear managed state paths → restore target bundle → relaunch → verify (identity shown in app config/DB, or app starts without login prompt).

**Detect identity**: SPIKE-0 must find a reliable non-secret place that contains the signed-in email (e.g. a config JSON or a Local Storage key). If none: show "Signed in (unknown email)" and ask user to label manually.

**Side-by-side** (optional): `open -n -a Claude --args --user-data-dir=<dir>` — SPIKE-0 must confirm the app honors this flag and that single-instance locks don't block it. Different data dirs may still share the Keychain safe-storage item; confirm behavior.

**Usage**: via the same account's OAuth data if obtainable; otherwise show "usage unavailable for desktop"; desktop profiles may inherit usage from a linked Claude Code profile with the same identity (link UI in v0.2).

**Verified** (2026-11-05, app 4.16336.0):
- ✅ Bundle ID `com.anthropic.claudefordesktop`; Electron; no single-instance Info.plist key.
- ✅ Keychain item `Claude Safe Storage` exists, single, never modified → shared key; do not touch.
- ✅ Data dir is **~15 GB** (`vm_bundles` 11 GB, `Cache` 1.3 GB, `claude-code` 561 MB, …). **State bundle MUST be an allowlist**, not "everything minus caches".
- ✅ Auth lives in `Cookies` (SQLite; `.claude.ai` `sessionKey*`, `lastActiveOrg`) and `config.json` (`oauth:tokenCache`, `oauth:tokenCacheV2`, `lastKnownAccountUuid`). Full allowlist/exclude lists: SPIKE-0-FINDINGS.md.
- ✅ No clean plain-text identity file (email only in IndexedDB blobs/session JSON). Identity = `lastKnownAccountUuid`, mapped to a user-confirmed label, optionally resolved via a Claude Code profile with the same `accountUuid`.
- ✅ Snapshots contain plaintext PII → encryption mandatory.
- ❓ Not verified: `--user-data-dir` side-by-side launch, Safe Storage ACL, graceful-quit timing.

---

## 3. Codex CLI — `codex-cli` — v0.3

**Candidate storage**
- Home: `~/.codex/` overridable with env `CODEX_HOME`.
- Auth: `~/.codex/auth.json` (ChatGPT login tokens: id token, access token, refresh token, account id; or an API key). Config option (e.g. `cli_auth_credentials_store = file | keyring | auto`) may move this to the Keychain (service candidate: `Codex Auth`).
- Sessions/logs: `~/.codex/sessions/**` JSONL rollouts (may contain rate-limit info events).
- Config: `~/.codex/config.toml`.

**State bundle**: `auth.json` (or Keychain item, depending on store mode) + optionally full `~/.codex` for `fullIsolation`. Never copy `sessions/` in `credentialsOnly`.

**Switch recipe (global)**: capture-back → write target `auth.json` atomically with mode 0600 (or update Keychain item) → verify by parsing identity (id token claims: email, account id — decode JWT payload locally, **never** send or log it).

**Identity**: decode the id token's payload (base64url, no signature verification needed for display) → `email`, plan type if present.

**Per-shell (v0.4)**: `CODEX_HOME=<materialized dir>` containing a 0600 `auth.json`; document the plaintext-file caveat or force keyring mode in that dir's `config.toml` if supported.

**Usage (v0.3/0.2 extension)**: candidates — (a) parse the latest `rate_limits` event in `~/.codex/sessions` rollouts (local, no network, preferred); (b) ChatGPT backend usage endpoint (undocumented, e.g. `/backend-api/wham/usage`) with the access token. Prefer (a); (b) behind feature flag.

**Verified** (2026-11-05; no `codex` binary on this machine, `~/.codex` used by the Codex desktop app):
- ✅ Credentials are the **file** `~/.codex/auth.json` (mode 0600); **no Keychain item**. Keys: `OPENAI_API_KEY`, `auth_mode`, `last_refresh`, `tokens{access_token, account_id, id_token, refresh_token}`.
- ✅ **Usage source (local, preferred):** session JSONL contains `rate_limits` events with `primary.used_percent`, `primary.window_minutes` (300) and `primary.resets_at`.
- ✅ `~/.codex` holds 70 MB+ of unrelated state → `credentialsOnly` copies `auth.json` only.
- ⚠ One adapter should serve both the CLI and the Codex desktop app (shared directory); probe them separately.
- ❓ `CODEX_HOME` override and keyring-mode config key: not tested.

---

## 4. ChatGPT Desktop — `chatgpt-desktop` — v0.3 (after Codex)

**Candidate storage**
- Bundle ID candidate: `com.openai.chat`.
- Data: `~/Library/Application Support/com.openai.chat/` and/or `~/Library/Containers/com.openai.chat/` (if sandboxed — then access may be restricted; SPIKE-0 decides feasibility).
- Auth tokens likely in the Keychain under the app's access group — **may not be readable/writable by a different signing identity**. If the Keychain items are ACL-locked to OpenAI's team ID, Swaplane cannot swap them without user-interactive ACL prompts or at all. This is a go/no-go for the adapter.

**Plan**: if feasible → same stop/capture/apply/relaunch recipe as Claude Desktop. If not feasible → ship as "launch separate instance via different macOS user data location" only if the app supports it; otherwise mark as *Unsupported* with an in-app explanation and track it in the Decisions log.

**Usage**: likely unavailable; show "n/a".

**Verified** (2026-11-05):
- ⚠ **`/Applications/ChatGPT.app` has bundle ID `com.openai.codex`** (v26.1029.x, team `2DC432GLL2`, not sandboxed) — it is the **Codex desktop app**, not a separate ChatGPT chat client. It uses `~/.codex/auth.json` plus `~/Library/Application Support/Codex` (192 MB, Chromium-style).
- `~/Library/Application Support/com.openai.chat` (812 KB) holds account-suffixed caches (`conversations-v3-<id>`, `codex-taskItems-*-<id>`), not auth.
- No Keychain items for openai/codex/chatgpt in the login keychain; the app's keychain access group (`2DC432GLL2.*`) means any items live in the data-protection keychain and are **not reachable** by a different signing identity.
- **Decision:** v0.3 Part 2 becomes **"Codex Desktop"** (`com.openai.codex`) sharing the Codex adapter's `auth.json` switch + app stop/relaunch. A distinct ChatGPT chat client stays *Unsupported* until its auth store is identified. Needs a second account to test.

---

## Adapter acceptance checklist (apply to every adapter)

- [ ] `Constants.swift` holds all paths/IDs/endpoints with `// VERIFIED:` annotations
- [ ] `probe()` reports version and support status; unsupported → switching disabled
- [ ] `detectCurrentIdentity()` has no side effects and reads no secrets unless unavoidable
- [ ] `capture()`/`apply()` are atomic and round-trip tested against fixtures
- [ ] Switch to B then back to A leaves A byte-identical modulo tool-refreshed tokens
- [ ] Failure injection at each phase → rollback restores original state
- [ ] No secret appears in logs/errors
- [ ] Works with the tool not installed / never signed in (clean states)
