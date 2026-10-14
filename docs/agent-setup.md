# Agent-assisted setup

For Claude Code, Codex, or another coding agent running on the user's Mac. This is an installation task, not a request to modify Kestrel's source. Read the README and [setup guide](getting-started.md) first.

## 1. Check the Mac

- Confirm macOS 14 or later and Apple silicon (`sw_vers -productVersion` and `system_profiler SPHardwareDataType`). An Intel Mac is not supported by the published app.
- Look for an existing Kestrel in `/Applications` and `~/Applications`. If installed, report its version and avoid creating a second copy. Do not read clipboard history or snippet contents.
- Explain that the preview is ad-hoc signed and not Apple-notarized. No Apple Developer account is needed to download or build it.

## 2. Obtain the app

**Default: prebuilt ZIP.** Use the Releases link in the README. Preview releases may not appear at GitHub's `/releases/latest` endpoint. Choose a published release, never a draft, and download its `Kestrel-<version>-macos-arm64.zip` and matching `.zip.sha256`. Do not use GitHub's source-code ZIP as the app download. Keep the two files together and verify the archive with:

```sh
shasum -a 256 -c Kestrel-<version>-macos-arm64.zip.sha256
```

Replace `<version>` with the selected release's exact version. Stop on a mismatch. Extract the ZIP to a new staging directory, verify the app's signature with `codesign --verify --deep --strict`, and compare its version/build with the release. These checks confirm consistency, not Apple notarization or publisher identity.

**If the user chooses source:** follow [development.md](development.md). Verify Swift 6+, the macOS SDK and Python 3 before building. If required tools are missing, explain the installation needed and its download size if known; do not silently install a package manager or full Xcode. Clone into a new directory, read its project instructions, and run `scripts/package.sh`. Preserve existing checkouts and uncommitted work. The output is `dist/Kestrel.app`.

## 3. Install without losing data

- Quit a running Kestrel normally, allowing the user to resolve any unsaved snippet draft.
- Keep a recoverable copy of the previous app before replacing it. Install in `/Applications`; if macOS requires authorization, let the user complete it. Do not silently choose a second installation location.
- Preserve `~/Library/Application Support/LocalPilot/` and all existing permissions and preferences. Never copy personal application data into the source checkout or release archive.
- Open the installed app. If blocked, explain Apple's per-app **Privacy & Security → Open Anyway** process from the setup guide and let the user decide. Do not disable Gatekeeper, remove quarantine, override organizational policy, or bypass malware/damaged-app warnings.

## 4. Verify and hand off

Check the installed version and ask the user to try Option–Space, opening an app, a calculation, and Esc/Command–W. If another launcher owns Option–Space, explain the conflict; do not quit or reconfigure it without the user's agreement. The wing menu can also open Kestrel.

Clipboard history remains off on a fresh install unless the user opts in; preserve existing preferences on upgrades. Folder access, Full Disk Access, and starting at login are optional. Explain the relevant settings when requested rather than granting broad access automatically.

Report the installed path, version, installation method, checks actually completed, and any remaining manual approval. Never report a successful launch solely because the download or build succeeded.
