# Get started with Kestrel

Kestrel is a menu-bar launcher for Apple silicon Macs running macOS 14 or later. No account or subscription is required. The current release is a preview; it has not yet been tested on every supported macOS release.

## Install

1. Download [Kestrel 1.6.1 for Mac (.zip)](https://github.com/junoh-bg/kestrel/releases/download/v1.6.1/Kestrel-1.6.1-macos-arm64.zip). This is the ready-to-use app, not GitHub’s source-code ZIP. [Release notes](https://github.com/junoh-bg/kestrel/releases/tag/v1.6.1) and a [checksum](https://github.com/junoh-bg/kestrel/releases/download/v1.6.1/Kestrel-1.6.1-macos-arm64.zip.sha256) are available separately.
2. Unzip the archive. Move **Kestrel.app** into **Applications** using Finder.
3. Open Kestrel from Applications. Use **Option–Space** or the **wing icon** in the menu bar to bring it back.

Kestrel does not automatically start at login. If you want that behavior, add it in **System Settings → General → Login Items**; the exact label can vary by macOS version.

## First launch

The current preview is ad-hoc signed, **not signed with a Developer ID certificate or notarized by Apple**. A successful build or checksum does not change that status. macOS may block a downloaded copy.

If the warning says Apple **cannot check Kestrel for malicious software** or **cannot verify its developer**, that describes a verification limitation; it is different from a warning that malware was detected. For a copy you trust from this repository and that your organization permits:

1. Open Kestrel from **Applications** to trigger the warning, then dismiss it without moving the app to Trash.
2. Open **System Settings → Privacy & Security** and scroll to **Security**.
3. Click **Open Anyway** for Kestrel, complete any authentication, and confirm **Open** when prompted.
4. Try **Option–Space**, or open Kestrel from the wing icon in the menu bar.

These are Apple's [per-app approval steps](https://support.apple.com/en-us/102445). You do not need to delete Kestrel or run the packaging script for this approval. If **Open Anyway** is unavailable on a managed Mac, contact your IT team. Do not disable Gatekeeper or remove quarantine attributes as part of setup.

If the warning says the app **will damage your computer**, **contains malware**, or **is damaged**, stop and [report the exact message](https://github.com/junoh-bg/kestrel/issues). Do not treat those warnings as the routine unnotarized-preview warning.

If you choose to [build from source](development.md), `scripts/package.sh` creates `dist/Kestrel.app` but does not install it. Quit the old app and replace the copy in Applications with the newly built app. Keep your saved data; rebuilding does not notarize the downloaded ZIP.

## First-minute setup

- **Shortcut:** if another launcher already uses Option–Space, quit it or change its shortcut. Kestrel's shortcut is currently fixed. The wing menu works even when the shortcut is unavailable.
- **File search:** open **Settings → Search → Check access**. For missing locations, use **Choose search folder…** to grant that folder and its subfolders. Desktop, Documents, and Downloads can also require macOS approval.
- **Broad folder access (optional):** **Full Disk Access…** opens macOS settings. Use **Show Kestrel app** to locate the installed copy, add and enable it, then quit and reopen Kestrel. This grants access to protected data beyond filename search. It is not required to use the calculator, launcher, or snippets.
- **Clipboard (optional):** history starts off. Enable it in **Settings → Clipboard** only if you want copied text saved.
- **Snippets:** create reusable text in **Settings → Snippets**. Search with `snip`, then Return copies a snippet for manual pasting.
- **Appearance:** choose a palette in **Settings → Appearance**. The choice is saved immediately.

## When something is missing

| Symptom | Try this |
| --- | --- |
| Option–Space does nothing | Open Kestrel from Applications or its wing menu; check for another app using the shortcut. |
| A newly installed app is missing | Choose **Refresh applications** from the wing menu. |
| A file or folder is missing | Use at least two letters, check access, then check whether Spotlight can find it. Permission does not index excluded files. Try a more specific name in large result sets. |
| “Readable” appears but a file is still missing | This only confirms folder-listing access. Spotlight coverage and result limits are separate. |
| Clipboard search is empty | Enable history, then copy ordinary text. Earlier clipboard contents are not imported. Some sensitive/transient content is intentionally skipped. |
| Closing the panel does not quit the app | This is expected. Use **Quit Kestrel** in the wing menu. |
| Access stops working after an update | Quit/reopen Kestrel and check access. Ad-hoc-signed replacements may need permission approval again. |

## Updates and uninstall

In builds with **Check for Updates…**, open that option from the wing menu or **Settings → General**. Kestrel checks automatically by default and shows the available version and release notes. You choose when to download, install, and relaunch. Turn off **Check automatically** in General settings to use manual checks only. Save any snippet draft before restarting; choosing to cancel the quit keeps it open.

Version 1.5.0 and earlier do not include the updater. They need one manual upgrade: quit Kestrel, keep a backup of the previous app if needed, replace the copy in Applications with the newer download, and reopen it. Your saved data remains in place. Keep only one active installed copy to avoid shortcut and permission confusion.

Update feeds and downloads are verified with Kestrel's update-signing key. If verification fails, the update is rejected; retry later or report the error. This verification does not replace Apple notarization. Ad-hoc updates may still need macOS access approvals again.

To uninstall, quit Kestrel and move **Kestrel.app** to the Trash. Preferences and snippets remain in your user account so reinstalling does not erase them. Use **Settings → General → Show Data Folder** before uninstalling if you want to back up or remove that data; review its contents before deleting it.

## Your data

Data lives at `~/Library/Application Support/LocalPilot/` for compatibility with early versions. `state.json` stores preferences, learned ranking, snippets, and enabled clipboard history; `search-folders.json` stores folder-access bookmarks. The folder and state file use user-only permissions, but the contents are not encrypted.

Clipboard history holds at most 100 text items for 30 days. Kestrel skips some concealed, transient, autogenerated, and password-manager content, but ordinary copied text can still contain secrets. Use **Clear History** when needed. No telemetry or cloud sync is included. Automatic and manual update checks contact GitHub; system-profile reporting is disabled, and clipboard contents, snippets, and search queries are not included. Choosing web search opens Google in your default browser and shares that query with Google.
