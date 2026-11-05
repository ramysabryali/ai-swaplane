# Security — Swaplane

Swaplane handles the most sensitive thing a user owns for these tools: login sessions. Security is a product feature, not a layer.

## Assets

1. OAuth/session tokens and API keys for each profile.
2. Application state snapshots (cookies, local storage, config) that may embed sessions or private data.
3. Snapshot encryption keys.
4. Metadata (emails, labels) — lower sensitivity but private.

## Threat model

| Threat | In scope? | Mitigation |
|---|---|---|
| Other local apps/processes reading secrets from disk | Yes | No plaintext secrets on disk; Keychain with access control; 0600/0700 permissions |
| Malware running as the same user | Partially | Keychain ACL scoped to app's code signature; biometric gate; cannot fully defend against same-user malware with full access — document honestly |
| Lost/stolen laptop | Yes | FileVault assumed; snapshots encrypted with Keychain-held key (`ThisDeviceOnly`) |
| Accidental disclosure via logs/crash reports/screenshots | Yes | `Redacted` type, log scrubbing, masked emails in UI by default option, no secrets in diagnostics |
| Malicious update | Yes | Sparkle EdDSA signature + notarization + HTTPS |
| Malicious `.swaplane` project file in a cloned repo | Yes | Trust prompt on first use of a new path; rules can only select existing profiles, never inject credentials or commands |
| Malicious shell-hook output | Yes | CLI output is strictly validated key/values from an allowlist (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, …); shell-quoted |
| IPC abuse by other processes | Yes | Socket 0600 in user dir; peer UID check; command allowlist; sensitive commands require gate |
| Network eavesdropping on usage polling | Yes | HTTPS only, ATS enforced, no custom trust, no proxies/cert pinning bypass |
| Nation-state / root attacker | No | Out of scope |

## Hard rules

1. **Keychain only for secrets.** Use `kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false` (never iCloud Keychain). Prefer the data-protection keychain (`kSecUseDataProtectionKeychain`) where entitlements allow.
2. **Access control.** Credential items created with `SecAccessControl` — `.userPresence` when the user enables the Touch ID gate (v0.2); otherwise ACL restricted to this app's signing identity.
3. **Snapshot encryption.** AES-256-GCM via CryptoKit; fresh random 96-bit nonce per seal; 256-bit random key per profile stored in Keychain; authenticated header; reject on tag failure; zeroize buffers where practical.
4. **No plaintext temp files.** Staging areas are inside `~/Library/Application Support/Swaplane/` (0700), created `O_EXCL`, and securely deleted (overwrite + unlink; note APFS limits) after use. Never use `/tmp` for decrypted material.
5. **Redaction.** Every secret-bearing value is wrapped in `Redacted<T>` whose `description`/`debugDescription`/`Codable`-to-log forms print `‹redacted›`. Logging goes through a facade that rejects raw `Data` > 32 bytes by default.
6. **No telemetry, no analytics, no crash upload.** Local diagnostics only; "Copy diagnostics" produces a secret-free report the user reviews.
7. **Network allowlist.** Only vendor usage endpoints (ADAPTERS.md) and the update feed host. Enforce in a single `HTTPClient` wrapper with a host allowlist; CI test fails if other hosts appear in source.
8. **Hardened Runtime** on, notarized, no `com.apple.security.cs.disable-library-validation`, no JIT, no `allow-unsigned-executable-memory`.
9. **Least privilege.** No Full Disk Access requirement; if the OS prompts for access to other apps' data, explain why in onboarding. No Accessibility permission unless a milestone proves necessary.
10. **Clipboard hygiene.** Never place tokens on the clipboard. Diagnostics only.
11. **Quarantine of drift.** If live state doesn't match the expected active profile (external login), never overwrite silently — prompt: "Save as new profile / Discard / Keep".
12. **Secure deletion on profile removal.** Delete Keychain items, snapshot file, rollback backups for that profile; confirm in UI.

## Touch ID gate (v0.2)

- Gated actions: switching, revealing token health details, export/backup, removing profiles, changing security settings.
- Modes: Off · On each switch · Reuse window (1/5/15 min) · Until Mac locks.
- Fallback to device password via `.deviceOwnerAuthentication`.
- Failed/cancelled auth never partially performs an action.

## Backup security (v0.5)

- User-supplied passphrase → key derivation with scrypt or PBKDF2-HMAC-SHA256 (≥ 600k iterations) via CryptoKit/CommonCrypto; salt per file.
- Backup file: `.swaplanebackup` — header (magic, version, KDF params, salt, nonce) + AES-256-GCM ciphertext. Never include the Keychain `snapshotKey`s in plaintext; re-key on restore.
- Passphrase strength meter; refuse < 10 chars. No passphrase recovery — say so clearly.

## Verification checklist (run each milestone)

- [ ] `grep -R` for token-looking strings in repo, logs, test snapshots finds nothing.
- [ ] `security dump-keychain` review: items have expected ACLs; not synchronizable.
- [ ] After a full run, `find ~/Library/Application\ Support/Swaplane -type f` contains no plaintext credentials (inspect with `strings`).
- [ ] Console/log output during switch contains no secrets (`log stream --predicate 'subsystem == "app.swaplane.mac"'`).
- [ ] `codesign --verify --deep --strict` and `spctl --assess` pass on the release build.
- [ ] Network capture (Little Snitch/`nettop`) shows only allowlisted hosts.

## Responsible disclosure

Add `SECURITY_CONTACT.md` before public release with a contact address and PGP key.
