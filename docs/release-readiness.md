# Release checklist

Kestrel is distributed as MIT-licensed source and a prebuilt macOS app ZIP on GitHub. App Store submission is not required. An unnotarized open-source preview can be published when its signing status and limitations are clearly disclosed.

## Before publishing

- Review the source and Git history for credentials, personal data, third-party research, generated output, and unrelated material.
- Run the checks in [development.md](development.md). Build the ZIP from the exact release commit with a matching version, release notes, license, and checksum.
- Extract the archive into a fresh directory; verify its contents, signature, version, and isolated startup smoke test. Never include user history, snippets, bookmarks, or developer credentials.
- State the architecture, minimum OS, signing status, and unverified compatibility clearly. Keep preview releases marked as prereleases.
- Verify anonymous repository access and the published download's checksum after publication.

## Compatibility record

The 1.7.2 preview targets Apple silicon and macOS 14+. Local automated tests, packaging, and startup checks have run on macOS 27.0.1. An isolated signed upgrade and rejection of a tampered download were verified. A real persistent-signature Sparkle update also retained Full Disk Access on this Mac. A separate-Mac downloaded installation and macOS 14 acceptance have not been verified. Do not describe these as completed or claim a warning-free installation.

On 2026-10-29, installed 1.7.2/build 16 on the maintainer’s Apple silicon Mac running macOS 27.0.1. Live launcher checks found all nine independently audited project `.env` files, showed the partial-scan notice for a broad query, kept Cursor selected above arriving folders/files, and found `dev/docs`. No environment-file contents were opened. The full 101-test Swift suite, all 12 packaging/signing tests, strict format lint, release build, and signature verification passed.

## Manual acceptance

Record the date, chip, macOS version, release commit, app version/build, and archive checksum. Use sample snippets and copied text.

1. Download and install following the setup guide. Record any first-launch approval needed.
2. Open an app and an indexed folder/file; search Google; calculate and copy an answer.
3. Confirm history starts off on a fresh install. Opt in, copy sample text, retrieve it, clear history, then disable it. Save and copy a sample snippet.
4. Switch themes, dismiss with Escape and Command–W, reopen, quit, and relaunch. Check persistence.
5. Check shortcut conflict and denied folder access. Confirm other tools work without Full Disk Access.
6. Update an existing installation and verify preferences and sample snippets are preserved.

Developer ID signing and notarization are planned distribution improvements. Until available, retain the documented per-app macOS approval guidance and respect managed-device restrictions.
