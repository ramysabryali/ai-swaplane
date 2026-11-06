# Adapters

> **Status:** checked on a real machine on 2026-11-05 — see [SPIKE-0-FINDINGS.md](SPIKE-0-FINDINGS.md). Items marked **Verified** below were confirmed on a real machine; everything else (and all usage endpoints) is still unverified prior knowledge. Record verification date and tool version in each adapter's `Constants.swift`.
>
> Never hardcode these values outside `Constants.swift`. Adapters must refuse to operate (state: *unsupported version*) when the installed tool version is outside the verified range.

Common interface: see `ToolAdapter` in [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 1. Claude Code (CLI) — `claude-code`

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



**Verified** (2026-11-05, CLI 1.0.83 local npm install):
- ✅ Keychain service `Claude Code-credentials` exists in the login keychain; the CLI refreshes tokens by rewriting the same item (modified-date changed same day).
- ✅ `~/.claude.json` (0600) holds `oauthAccount` (`accountUuid`, `emailAddress`, `organizationName`, `organizationUuid`, …) alongside caches/history — merge only `oauthAccount`, never swap the file.
- ✅ `claude auth status` prints identity JSON non-interactively — use it for `verify()`.
- ⚠ The CLI may be a shell alias (`alias claude=~/.claude/local/claude`), not on `PATH`: probe known install locations. Claude Desktop also bundles its own Claude Code build sharing the same Keychain service.
- ❓ Credential JSON field names and usage endpoint: not verified.

---

## 2. Claude Desktop — `claude-desktop`

**Candidate storage**
- Bundle ID candidate: `com.anthropic.claudefordesktop` (verify via `mdls -name kMDItemCFBundleIdentifier /Applications/Claude.app`).
- Electron user data dir: `~/Library/Application Support/Claude/` (cookies, Local Storage, IndexedDB, session storage, config JSON).
- Electron `safeStorage` encryption key: Keychain item (typically `Claude Safe Storage`) — shared by all profiles on this Mac; **do not** swap or copy it. Because it's shared, copied encrypted cookies/tokens remain decryptable.

**State bundle**: the user data dir minus regenerable caches (`Cache`, `Code Cache`, `GPUCache`, `DawnCache`, `Crashpad`, `logs`, `blob_storage` if safe — confirm in SPIKE-0). Include: `Cookies`, `Local Storage`, `IndexedDB`, `Session Storage`, `Preferences`, `config.json`-style files, `Network` (cookie/token DBs). Snapshot as Apple Archive/tar → encrypted.

**Switch recipe**: Stop app (graceful) → backup → capture-back → clear managed state paths → restore target bundle → relaunch → verify (identity shown in app config/DB, or app starts without login prompt).

**Detect identity**: SPIKE-0 must find a reliable non-secret place that contains the signed-in email (e.g. a config JSON or a Local Storage key). If none: show "Signed in (unknown email)" and ask user to label manually.

**Side-by-side** (optional): `open -n -a Claude --args --user-data-dir=<dir>` — SPIKE-0 must confirm the app honors this flag and that single-instance locks don't block it. Different data dirs may still share the Keychain safe-storage item; confirm behavior.


**Verified** (2026-11-05, app 4.16336.0):
- ✅ Bundle ID `com.anthropic.claudefordesktop`; Electron; no single-instance Info.plist key.
- ✅ Keychain item `Claude Safe Storage` exists, single, never modified → shared key; do not touch.
- ✅ Data dir is **~15 GB** (`vm_bundles` 11 GB, `Cache` 1.3 GB, `claude-code` 561 MB, …). **State bundle MUST be an allowlist**, not "everything minus caches".
- ✅ Auth lives in `Cookies` (SQLite; `.claude.ai` `sessionKey*`, `lastActiveOrg`) and `config.json` (`oauth:tokenCache`, `oauth:tokenCacheV2`, `lastKnownAccountUuid`). Full allowlist/exclude lists: SPIKE-0-FINDINGS.md.
- ✅ No clean plain-text identity file (email only in IndexedDB blobs/session JSON). Identity = `lastKnownAccountUuid`, mapped to a user-confirmed label, optionally resolved via a Claude Code profile with the same `accountUuid`.
- ✅ Snapshots contain plaintext PII → encryption mandatory.
- ❓ Not verified: `--user-data-dir` side-by-side launch, Safe Storage ACL, graceful-quit timing.

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
