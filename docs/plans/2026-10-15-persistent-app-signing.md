# Persistent app signing

Use a maintainer-owned self-signed code-signing certificate in login Keychain, separate from the existing Sparkle Ed25519 key. Keep `com.localpilot.launcher` and pin the public certificate fingerprint in the designated requirement. Never use an identifier-only requirement, export a private key, or install a new trusted root on user machines.

Source builds remain ad-hoc unless release signing is explicitly requested. Release archives must use the pinned identity and fail if unavailable; never silently fall back to ad-hoc. Preserve Sparkle's nested vendor signatures. The initial Gatekeeper warning remains because these builds are not Apple-notarized.

Verify a changed bundle satisfies the same certificate-bound requirement; verify ad-hoc code cannot satisfy it. Then stage two builds of the real Kestrel app with a localhost-only signed Sparkle feed, install the first under /Applications with a backup, refresh its existing Full Disk Access once, and update through Sparkle. Check the permission toggle and actual folder operations before and after. Return the final app to the public feed without publishing the test feed or test artifacts. Do not claim cross-version macOS coverage from one Mac.

Changing from ad-hoc to persistent signing may require a final permission approval. Certificate loss, replacement, or expiry needs a separately planned migration. Private keys remain in Keychain; public metadata is safe to commit. Release publication and merging are outside this test's scope.

## Verification on 2026-10-15

Tested on Apple silicon running macOS 27.0.1 (26A434). Created `Kestrel Code Signing` in login Keychain; only its public fingerprints are committed. The existing Sparkle key was reused. No certificate trust settings were changed and no private key was exported. Keychain needed an explicit allowed-app entry for `/usr/bin/codesign`; approval was completed by the user.

The local test builds used Kestrel's real AppDelegate, UI, and SoftwareUpdates service, plus temporary startup-only instrumentation. It opened `~/Library/Safari` with `O_RDONLY | O_DIRECTORY | O_CLOEXEC`, immediately closed the descriptor, and recorded only success/errno, build, process ID, and time. It did not enumerate the directory or read file contents. This instrumentation is absent from the normal installed build.

| Stage | Build | Protected-directory open |
| --- | --- | --- |
| Before approving the new identity | 11 | Denied, errno 1 |
| After one permission approval and restart | 11 | Allowed, errno 0 |
| After Sparkle download, install, and relaunch | 12 | Allowed, errno 0 |

The final step used a fresh process. Full Disk Access remained enabled in System Settings, with no permission changes or authentication between the last two stages. Both test builds shared the exact certificate-bound designated requirement. The feed and archive were Ed25519-signed using the existing Sparkle key and served only on 127.0.0.1; no test release or feed was published.

Restored the normal packaged app under `/Applications/Kestrel.app`, with the same persistent certificate, original public feed, and no diagnostic instrumentation. Retained the prior installed app and test app under ignored `dist/archive/`. Existing user data was not copied or modified by the test harness. The restored app still showed 34 clipboard items and two snippets, automatic update checks enabled, a working `dev/docs` folder result, and readable Desktop/Documents/Downloads. Full Disk Access remained on after restoring the normal package. The normal local build retains version 1.6.1/build 12 and includes the already-installed, unreleased nested-path work; it is not a new public release.

Validation: 83 Swift tests passed; all 12 packaging tests passed with the maintainer signing test enabled, including changed-build identity continuity, rejection of ad-hoc code against the pinned requirement, wrong bundle identity, and missing-key failure. Normal and release-signing packaging, strict nested signature verification, isolated installed-app smoke test, Swift formatting lint, and whitespace checks passed. Code review checked certificate binding, no private-key export, no silent signing fallback, preserved Sparkle signatures, and separation of test/public feeds.

This proves persistence for the tested update on this Mac, not all supported macOS versions. Before broad distribution, repeat on another Mac without the maintainer's certificate in Keychain and cover macOS 14. The initial Gatekeeper warning remains. Migrating existing users from ad-hoc builds may need one final approval; replacing future releases with ad-hoc source builds or changing the certificate can require approval again.
