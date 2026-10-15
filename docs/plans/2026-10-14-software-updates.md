# Software updates

Provide Check for Updates in the wing menu and General settings. Use Sparkle 2 for authenticated downloads and app replacement rather than a custom installer. This is an intentional exception to the previous no-third-party-runtime convention; pin and review the dependency.

Automatic checks are user-controlled. Default to asking before installation; do not silently restart while a snippet draft is open. Keep the existing termination guard. Disable system-profile reporting. Update checks contact the public GitHub-hosted feed; clipboard and snippet data are never included.

Store the Ed25519 private key in macOS Keychain and commit only its public key. Require archive verification before extraction. The release workflow signs finalized ZIPs and generates the appcast only after all asset URLs and bundle metadata are known. Never advertise draft/unpublished releases or reuse a version. Keep a valid empty feed until the first updater-enabled release is published.

Package the pinned Sparkle framework, helper services, and license with preserved symlinks and valid nested signatures. Maintain ad-hoc signing disclosure; update authentication does not provide Apple notarization.

Test settings callbacks and availability, packaging identity and signing metadata, archive signature validation, and a complete isolated old-to-new update. No user history is used by tests. The existing v1.5.0 app needs one manual replacement to acquire the updater.

## Review and verification

Implemented with automatic checks enabled by default and explicit user installation. The private Ed25519 key was created with user approval in Keychain; only its public key is committed. Both feed and archive signatures are required. The committed feed is empty and signed until a tested release is approved for publication.

Review covered updater lifetime, menu availability, stored preferences, shutdown/draft handling, framework embedding, key isolation, release identity validation, and documentation. Two findings were corrected: release preparation now rejects a mismatched Keychain public key, and manual checks dismiss the floating launcher so it cannot cover the update dialog. A clipboard test exposed dependence on the frontmost application while macOS displayed a security prompt; the test now injects that input, with a separate regression proving security prompts still block capture.

Verification on the development Mac:

- 75 Swift tests and eight packaging tests passed.
- Release build, package identity/icon checks, nested code-signature verification, packaged-app smoke test, strict Swift formatting lint, and diff checks passed.
- Reviewed native Settings renders in all five themes, including light/dark transitions through the real Settings controls. Captures use isolated sample state.
- An isolated app using the production update service installed a signed build 2 over build 1 and relaunched. Manual checking then reported the newest version correctly.
- A signed feed pointing to a one-byte-modified ZIP produced Sparkle's “improperly signed” error and retained build 2. Public-key-only verification independently accepted the original archive and rejected the altered one.
- The release ZIP preparation and signed-feed generation completed locally after Keychain approval. The generated feed correctly identifies the app version/build, macOS 14 minimum, Apple silicon requirement, and versioned asset URL; signature verification passed. This test feed was not published.

Version 1.6.0 (build 11) is the first updater-enabled release. The installed v1.5.0 app needs one manual upgrade. Separate-Mac download/Gatekeeper validation and macOS 14 coverage remain release checks; updater signing does not provide Apple notarization.

The refreshed English demo covers apps, folders, files, calculator, Google search, clipboard history, snippets, five themes, and update controls. The release demo shows the available update controls. Native views use isolated sample data and the opaque accessibility fallback.

Final 1.6.0 release checks on 2026-10-15 passed: 75 serial Swift tests, eight packaging tests, release build/package, nested signatures, isolated packaged startup, strict formatting, and diff checks. The 43-second H.264 MP4 was re-rendered with shipped-feature wording, decoded fully, and visually checked. No new blocking findings were identified in the final updater/release review.
