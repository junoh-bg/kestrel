# Dotfile filename recall

## Diagnosis

Kestrel relies on Spotlight metadata for ordinary file search. An actual filename audit found exact .env files in development projects while both mdfind and the app's Foundation metadata-query API returned no exact matches. Permissions and ranking cannot recover names absent from the metadata source. Existing result caps also hide matches in larger sets.

## Design

For a query whose final component starts with a dot, run a filename-only directory traversal concurrently with the existing metadata query. Search user-selected roots first, then Desktop, Documents, and Downloads. An absolute dotfile path reads only its immediate parent. Relative nested paths retain the existing adjacent-parent semantics. Merge sources by canonical parent path and filename, preserving symlink filenames, then apply ranking and the launcher's application/folder/file priority.

Traversal reads directory entries and file resource attributes only. It never opens file contents, creates a persistent index, executes search text, or follows directory symlinks. Skip VCS, dependency, build, cache, and package contents; an explicitly chosen scope overrides exclusions inherited from an ancestor. Suppress repeated traversal across overlapping scopes. Respect existing macOS access and report inaccessible locations.

Bound each scan to five seconds checked between entries, 150,000 entries, and 5,000 collected candidates. Cancellation stops the background task; a generation guard prevents stale callbacks from changing results for another query. Allow up to 120 scrollable dotfile matches and report a cap or incomplete scan. Ordinary queries retain Spotlight coverage and existing result limits.

## Alternatives

Changing Spotlight predicates alone cannot retrieve unindexed names. A persistent whole-disk index would introduce separate storage, change tracking, and privacy concerns. A targeted, bounded fallback addresses the reported dotfile gap while retaining the existing source for ordinary queries.

## Verification scope

Regression tests cover unindexed and unreadable-content dotfiles, variants, hidden parents, relative and absolute paths, overlapping scopes, dependency exclusions, explicitly selected roots, directory-loop avoidance, retained file symlink names, cancellation/replacement, scan bounds, and more than twelve scrollable matches. All files in fixtures contain empty synthetic data. Filename audits print counts/timing only. Release remains paused until user authorization to resume.

## Review and verification

Reviewed traversal scope, cancellation/generation handling, result-source merging, permission handling, alias and symlink behavior, bounds, and file-content privacy. Corrected an exclusion edge case so a user-selected folder beneath a skipped ancestor remains searchable; its regression failed before that correction and passed afterward. No remaining blocking code findings were identified.

The full suite passed 101 Swift tests (17 XCTest plus 84 Swift Testing), and all 12 packaging/signing tests passed. Strict Swift format lint, whitespace checks, release build, package validation, nested signature verification, and isolated packaged smoke test passed. The filename-only audit matched the independent exact-name count for the development projects, completed in approximately 2.5 seconds, and reported neither truncation nor inaccessible folders. Private filenames and credential contents are not part of this report.

Prepared signed 1.7.2/build 16 locally. The Mac locked before installing this combined build and checking its actual launcher, so that acceptance step remains pending. The prior build-15 ordering fix was already verified in the installed launcher. The public release/feed remain unchanged, and PR #17 remains unmerged while the user evaluates the additional fix.
