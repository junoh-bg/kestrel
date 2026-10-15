# Changelog

User-facing changes are recorded here. Release versions follow `MAJOR.MINOR.PATCH`.

## [1.7.1] — 2026-10-15 · Newly installed apps

- Refreshes the application list in the background when the launcher opens and every five seconds while it remains visible.
- Newly installed, renamed, and removed apps update automatically, including apps inside Applications subfolders. Manual refresh remains available.
- Keeps typing responsive by scanning off the main thread and reusing the current results until a changed list is ready.

[Release notes](docs/releases/1.7.1.md)

## [1.7.0] — 2026-10-15 · Nested search and lasting permissions

- Added persistent certificate-bound app signing for maintainer releases, separate from Sparkle update signing. Initial macOS installation warnings remain.

- Added nested path search: `dev/docs`, `kestrel/docs/demo`, and partial final names such as `dev/do`.
- Supports files, `~/` and absolute paths; a trailing slash limits results to folders. Parent names match adjacent directories exactly (ignoring case and accents).
- Resolves matching parent folders before applying result limits, so unrelated names cannot crowd out a path match. Spotlight indexing and macOS access still apply.

**Existing users:** upgrading from 1.6.1 or earlier may require one final Full Disk Access approval for the new signing identity. [Release notes and steps](docs/releases/1.7.0.md).

## [1.6.1] — 2026-10-15 · Settings readability fix

- Fixed dark checkbox labels in General and Clipboard settings when macOS uses the app's older SDK compatibility mode.
- Kept checkbox labels readable across all five themes, including checked, unchecked, and disabled states.
- Added visual regression checks for both legacy and current AppKit rendering paths.

[Release notes](docs/releases/1.6.1.md)

## [1.6.0] — 2026-10-15 · Software updates preview

- Refreshed the English demo with clipboard history, all five themes, and in-app updates.

- Added **Check for Updates…** to the wing menu, app menu, and General settings.
- Added automatic update checks with an option to turn them off. Users choose when to download and install; Kestrel never installs silently.
- Added signed release feeds and verified downloads through Sparkle. Existing v1.5.0 installations need one manual update to receive this feature.

[Release notes](docs/releases/1.6.0.md)

## [1.5.0] — 2026-10-14 · Design and actions preview

- Refreshed all five themes: Nightflight, Moss, Dusk, Linen, and Frost. Search and Settings share a soft glass surface, with an opaque fallback when Reduce Transparency is enabled.
- Made the launcher compact when idle and sized results to their content, up to seven visible rows.
- Added contextual primary actions and Command–K actions, including Show in Finder and Copy Path for apps, files, and folders.
- Added comfortable padding to Settings action buttons and a solid backing for the native title bar.
- Fixed selected folder icon contrast in light themes and launcher shortcuts with Korean input enabled.

- Updated the English product demo for the new design, covering app, folder and file search, daily tools, and theme customization, with a GIF in the README and an MP4 for sharing.

[Release notes](docs/releases/1.5.0.md)

## [1.4.2] — 2026-10-14 · Open-source preview

- Added a concise product guide and separate setup help.
- Added a downloadable app package with installation instructions, license, release notes, and checksum.
- Added an MIT license for the product source.
- Added an agent setup prompt and guide for assisted installation.
- Unified app versions, build numbers, and release archive naming.

[Release notes](docs/releases/1.4.2.md)

## [1.4.1] — 2026-10-13 · Private preview

- Fixed unreadable settings labels and theme transitions.
- Made theme buttons compact with consistent alignment and spacing.
- Fixed clipboard preference persistence and file-only search filtering.
- Preserved unreadable saved folder-access data instead of overwriting it.

Earlier private previews introduced app and file search, Google search, calculations, clipboard history, snippets, and five themes. They were not public releases.
