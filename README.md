<p align="center"><img src="docs/images/kestrel-icon.png" width="80" alt="Kestrel"></p>

# Kestrel

**Make everyday work immediate, predictable, and personal.**

A native Mac launcher for opening apps, finding files, searching Google, calculating, and reusing copied text and saved snippets—all from **Option–Space**. Five themes. Local storage. No account required.

**macOS 14+ · Apple silicon · Free and open source**

## Install

[**Download Kestrel for Mac (.zip)**](https://github.com/junoh-bg/kestrel/releases/download/v1.4.2/Kestrel-1.4.2-macos-arm64.zip)

v1.4.2 preview · [Release notes](https://github.com/junoh-bg/kestrel/releases/tag/v1.4.2) · [SHA-256 checksum](https://github.com/junoh-bg/kestrel/releases/download/v1.4.2/Kestrel-1.4.2-macos-arm64.zip.sha256)

Unzip the download, drag **Kestrel.app** into **Applications**, and open it. Press **Option–Space** to start. If another launcher uses that shortcut, quit it or change its shortcut.

This open-source preview is not Apple-notarized. If macOS blocks it, a trusted download may be opened through **System Settings → Privacy & Security → Open Anyway**. [Setup help](docs/getting-started.md#first-launch).

### Build from source

Requires Xcode command-line tools with Swift 6+ and Python 3. [Build guide](docs/development.md).

```sh
git clone https://github.com/junoh-bg/kestrel.git
cd kestrel
./scripts/package.sh
```

Move `dist/Kestrel.app` into Applications and open it.

### Set up with an AI agent

Paste this into **Claude Code, Codex, or another coding agent with access to your Mac**:

```text
Install Kestrel from https://github.com/junoh-bg/kestrel.
Read README.md and docs/agent-setup.md, check my Mac's compatibility,
and use the published app ZIP unless I ask to build from source.
Verify the download checksum, preserve any existing Kestrel data,
install the app, and help me test Option–Space. Explain any macOS
approval I need to complete. Keep clipboard history off unless I opt in.
Report the installed version and any unfinished steps.
```

[Agent setup guide](docs/agent-setup.md) · A browser-only chat can guide you but cannot install the app for you.

## Use

Type an app or folder name, `file report`, a Google query, `= 12 * 8`, `clip meeting`, or `snip signature`. Use **↑ / ↓** to select, **Return** to open or copy, and **Esc / ⌘ W** to dismiss.

Open **Settings** from the wing menu to choose a theme, manage snippets, or enable optional clipboard history. File search uses Spotlight and may need folder access. Clipboard history starts off and stores unencrypted text locally when enabled. Selecting Google search sends that query to your browser; Kestrel has no telemetry or cloud sync.

[Setup & help](docs/getting-started.md) · [Release notes](CHANGELOG.md) · [Report an issue](https://github.com/junoh-bg/kestrel/issues) · [MIT license](LICENSE)
