# Refresh newly installed applications

## Diagnosis

Gemini.app exists in /Applications, but the running 1.7.0 launcher returns only Google search. AppCatalog is populated at startup and by the explicit Refresh applications action; opening the launcher never rescans it. Spotlight searches primarily cover the user's home directory and do not repair this stale application catalog.

## Design

Refresh asynchronously when opening the launcher and every five seconds while it is visible. Keep cached results during scanning, coalesce concurrent refresh requests, and publish changed lists on the main actor so the visible query updates. Scan only the existing bounded Applications roots. Stop the repeating timer on dismissal or once it observes the panel is hidden. Preserve manual refresh and prevent a stale background scan from overwriting a newer manual result.

A synchronous rescan on every keystroke could interrupt typing; permanent recursive filesystem watchers add lifecycle and nested-directory complexity. An opening refresh plus visible-only polling fixes the install case without either cost. It does not depend on Spotlight finishing indexing.

## Acceptance

- Add an app after catalog startup and discover it on launcher opening.
- Add an app inside an Applications subfolder while open and discover it automatically.
- Rename/remove apps and discard stale results on reopening.
- Verify the actual Gemini application in the packaged installed app.
- Keep the persistent signing identity and existing user data.

## Verification

Reproduced on the installed 1.7.0 app: Gemini.app was present in /Applications but the launcher returned only Google and indexed files. Three new native regressions failed before automatic refresh, then passed with the fix. The full suite passed 86 Swift tests (17 XCTest and 69 Swift Testing); all 12 packaging/signing tests passed, along with strict formatting, whitespace, release build, package validation, nested signature verification, and isolated smoke testing.

Installed the persistently signed local 1.7.1/build 14 patch, retaining the prior app under ignored dist/archive/. The live launcher returned Gemini as an Application with Open Application available. Public releases and the signed update feed remain unchanged pending review and merge.
