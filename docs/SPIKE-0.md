# SPIKE-0 — Verify tool storage assumptions

**Goal:** replace assumptions in [ADAPTERS.md](ADAPTERS.md) with facts from a real machine. **Time-box:** 1 day. **Output:** `docs/SPIKE-0-FINDINGS.md` and updated ADAPTERS.md "Verified" tables.

## Ground rules (read carefully)

- **Read-only.** Do not modify, delete, or write any tool's files or Keychain items during the spike.
- **Never print secrets.** When inspecting Keychain items or JSON containing tokens, show only *existence, keys/field names, lengths, and expiry dates* — not values. Use `security find-generic-password -s "<service>"` **without** `-w`/`-g`. Mask output.
- **Do not paste real tokens or emails into the findings doc.** Use `j***@example.com` style masks.
- Ask the user before running any command that triggers a Keychain access prompt.
- Work against a throwaway second account if the user can provide one; otherwise stay strictly read-only.

## Questions to answer per tool

### Claude Code
1. Installed path and version (`claude --version`). Install method (npm, native).
2. Keychain: does a generic password with service `Claude Code-credentials` exist? What are its account and creation/modification dates? What JSON field names does the value contain (names only)?
3. `~/.claude.json`: top-level keys; where is the signed-in email/org (`oauthAccount`?).
4. `CLAUDE_CONFIG_DIR`: with it set to an empty temp dir (`mktemp -d` under the scratchpad), does `claude` use a *different* Keychain service name? Capture the service name pattern (`security dump-keychain | grep -i claude` with values excluded — metadata only). Is login required in the new dir?
5. Is there a non-interactive command to show the logged-in identity (`claude /status`, `claude auth status`, etc.)?
6. Token expiry and refresh behavior: when the CLI refreshes, does it rewrite the same Keychain item?

### Claude Desktop
1. Bundle ID, version, install path.
2. Data dir contents (names + sizes via `du -sh`), which are caches vs state.
3. Where does the signed-in email live (file/key names only)?
4. Keychain items related to the app (`Claude Safe Storage`?), their ACL trusted apps (`security find-generic-password -s ... ` metadata only).
5. Does it honor `--user-data-dir`? Does `open -n -a Claude --args --user-data-dir=<tmp>` start a second independent instance? (Run only with user consent.)
6. Quit behavior: graceful quit time; any "are you sure" dialogs; background helper processes to wait for.

### Codex CLI
1. Version; `CODEX_HOME` support.
2. Where credentials live now: `~/.codex/auth.json` vs Keychain; config key controlling it.
3. Field names in `auth.json` (names only). JWT payload claims available for identity (names only).
4. Do session rollout files include rate-limit info? Which event/field names?

### ChatGPT Desktop
1. Bundle ID, sandboxed or not, data location.
2. Keychain items and their ACL/access group. **Go/no-go:** can another signed app read/replace them?
3. Any supported multi-profile or user-data-dir flag.

### Platform
1. macOS version; whether "Displays have separate Spaces" affects status items on external displays (test with an external display if available).
2. `SecItem` behavior for items created by other apps: does `SecItemCopyMatching` trigger a prompt for the Claude Code item from an unsigned vs Developer-ID-signed binary?
3. Can a Swift tool create a Keychain item readable by a *different* binary (CLI helper) — which access-group/ACL setup is needed?

## Deliverables

1. `docs/SPIKE-0-FINDINGS.md` — per tool: verified constants, version ranges, surprises, go/no-go.
2. Update `ADAPTERS.md` "Verified" lines and any recipe that changed.
3. A `Tools/spike/` folder of the read-only scripts used (no secrets embedded), runnable by the user.
4. A **go / no-go / needs-redesign** call per adapter and per feature (per-shell switching, side-by-side, usage).
5. Append to the Decisions log in ARCHITECTURE.md.

## Template for findings

```markdown
## <Tool> — <version> — verified <YYYY-MM-DD>
- Install path:
- Credential location: (Keychain service/account | file path) — exists: yes/no
- Credential fields (names only):
- Identity source: (path/key)
- Config-dir override: (env/flag) → behavior:
- Safe to swap: credentialsOnly? fullIsolation?
- Process stop needed? how:
- Usage source: (endpoint/local file) → reliability: low/med/high
- Go / No-go / Needs-redesign:
- Notes:
```

## Exit criteria

Spike is done when every "Candidate storage" statement in ADAPTERS.md for Claude Code and Claude Desktop (v0.1 scope) is either verified or corrected, and Codex/ChatGPT have at least a go/no-go with evidence.
