# Release maintenance

## Version policy

`version.json` is the single source for the displayed app version and numeric build number. Use semantic versions:

- **PATCH** for fixes and distribution/documentation improvements.
- **MINOR** for backward-compatible capabilities.
- **MAJOR** for breaking compatibility.

Increment `build` for every distributed app build. Never reuse a published version/tag or replace its assets; issue a new patch version instead. Tag releases `vMAJOR.MINOR.PATCH`. Mark preview releases as prereleases in GitHub; they are not the default “latest” release. Version 1.4.2 is the first open-source preview; the earlier numbers preserve upgrade ordering for existing users.

Before a release, update `version.json`, the matching `CHANGELOG.md` section, and `docs/releases/<version>.md` together. Update the versioned ZIP, checksum, and release links in the README and getting-started guide; the primary download button must point to the app asset, not the release listing. Avoid `/releases/latest` for previews because prereleases are excluded. Date the changelog entry when the release is actually published. The packager verifies bundle versions against the version file and includes the MIT license in the app.

## Build a release archive

Run the checks in [development.md](development.md), then:

```sh
scripts/release.sh
```

Follow the [release checklist](release-readiness.md). Publish ad-hoc-signed builds as previews with an explicit notarization caveat and first-launch instructions.

This creates a new directory under `dist/releases/` containing a versioned app ZIP and SHA-256 file. The ZIP includes the app, plain-text installation guide, license, and release notes. The script never publishes anything and retains previous output. It currently builds only Apple silicon and uses ad-hoc signing; do not call its output notarized.

From the output directory, verify `shasum -a 256 -c Kestrel-<version>-macos-arm64.zip.sha256`. Extract the ZIP into a fresh folder, verify the app with `codesign --verify --deep --strict`, and run its executable with `--smoke-test` in a logged-in macOS session. Test an actual downloaded copy on a separate Mac before widening distribution.

## Developer ID and notarization

For a normal download-and-open release, obtain a **Developer ID Application** certificate for the publisher. Sign the final app with hardened runtime and a secure timestamp. Submit an archive with Apple's `notarytool` using Keychain-stored credentials; wait for acceptance, staple and validate the ticket on the app, then create a new final ZIP and checksum from that stapled app. Verify the signature and Gatekeeper assessment. Do not rerun `release.sh` afterward because it rebuilds and applies an ad-hoc signature.

An Apple Development certificate is not sufficient for this distribution path. Do not place certificates, private keys, or notarization credentials in Git. See [Apple's guidance](https://developer.apple.com/developer-id/) and [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Publish

Source and preview app downloads are published on GitHub. Apple Developer membership and App Store submission are not prerequisites for publishing the source or an explicitly unnotarized preview.

1. Confirm the release commit, version, build, changelog date, release notes, architecture, and signing status match the tested artifact.
2. Create the matching Git tag and GitHub release from that exact commit; use `docs/releases/<version>.md` as the release body.
3. Upload only the tested app ZIP and its checksum. Mark unnotarized previews as prereleases and document manual approval and any unverified compatibility. For a notarized release, verify the stapled ticket and Gatekeeper assessment before uploading.
4. Check the download anonymously after publication, compare its checksum, and follow the installation guide on a separate Mac.

Release notes should describe what users get, what changed, setup/upgrade requirements, and known limitations. Planned features belong outside shipped release notes.
