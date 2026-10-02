# Security policy

Found a vulnerability? **Do not open a public issue.** Use GitHub's private
vulnerability reporting (Security tab → "Report a vulnerability") or email the
maintainer. Expect an acknowledgement within 72 hours.

The threat model, mitigations and residual risks are in [docs/SECURITY.md](docs/SECURITY.md).

Never commit signing certificates, Sparkle private keys, Stripe keys or tokens
(`.gitignore` blocks common patterns; review diffs before pushing).
