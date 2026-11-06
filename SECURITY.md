# Security policy

AI Swaplane handles login sessions, so security reports are taken seriously.

## Report a vulnerability

Please do not open a public issue. Use GitHub's private reporting instead:
**Security tab > Report a vulnerability** on this repository.

Include what you found, the steps to reproduce it, and the macOS and app versions. You can expect an acknowledgement within a few days. Please give a reasonable time to fix the problem before you share it publicly.

## Scope

In scope: leaking or mishandling saved sign-ins, plaintext secrets on disk or in logs, writing to the wrong account, and anything that makes a switch unsafe.

Out of scope: an attacker who already has root or full control of your user account, and changes in how third-party apps store their sign-in.

The threat model and the rules the code follows are in [docs/SECURITY.md](docs/SECURITY.md).
