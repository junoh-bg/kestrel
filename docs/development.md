# Build and contribute

## Requirements

Apple silicon, macOS 14+, Xcode 16+ or compatible Command Line Tools with Swift 6+, and Python 3. Builds use AppKit and Foundation, plus pinned Sparkle 2.10.0 for signed updates. The first build downloads this dependency. No signing key is needed to build or use Kestrel; only maintainers publishing updates need the private Keychain key.

```sh
git clone https://github.com/junoh-bg/kestrel.git
cd kestrel
scripts/package.sh
```

Move `dist/Kestrel.app` to Applications and open it. Quit an existing Kestrel before replacing it. Local builds use an ad-hoc signature. Earlier build outputs are retained under ignored `dist/archive/`.

## Verify changes

```sh
swift test --no-parallel
python3 -B -m unittest discover -s Tests/Packaging -v
swift build -c release
scripts/package.sh
scripts/check-control-contrast.sh
dist/Kestrel.app/Contents/MacOS/Kestrel --smoke-test
xcrun swift-format lint --strict --recursive Sources Tests Package.swift scripts/MakeIcon.swift
git diff --check
```

Native tests require a logged-in Mac and Spotlight indexing. Run them serially: AppKit shares process state and some search tests have fixed timing assumptions. Smoke mode uses temporary data and ignores saved user data. Check live theme transitions as well as automated tests when changing native controls. `check-control-contrast.sh` renders checkbox labels under both macOS 14 and current SDK compatibility modes; the unit-test host and a standalone preview can otherwise use a different AppKit rendering path from the packaged app.

For demo exports, normalize native PNG captures to a single pixel format before concatenating them. AppKit may produce mixed 8-bit and 16-bit frames; video filter reinitialization can otherwise alter timing and skip visible scenes. Check the encoded video, not only its source frames.

## Structure

- `Sources/Kestrel/`: native app, launcher, settings, and macOS adapters.
- `Sources/KestrelCore/`: matching, ranking, calculations, and storage.
- `Tests/`: core, native, and packaging checks.
- `version.json`: release version and build number.
- `scripts/`: icon generation, packaging, and release archives.

Keep the existing bundle identifier and data-directory name stable for upgrades. Never include application-support data in a release. Clipboard capture stays off by default. Search input must not become shell commands.

Use conventional commits and focused pull requests. Include the user-visible change, verification, and screenshots for interface changes. See [release maintenance](releasing.md) for versioning and distribution.
