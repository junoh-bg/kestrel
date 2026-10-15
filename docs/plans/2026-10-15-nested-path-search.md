# Nested path search

## Behavior

Slash-separated queries describe adjacent directories and a final filename or folder name. Parent components match exactly, ignoring case and accents. The final component supports exact and prefix matches, with exact matches first. A trailing slash requests folders only. Home and absolute paths anchor the parent location; relative paths match anywhere in the existing search scopes. Empty components, dot traversal, and web URLs do not enter path-search mode. Ordinary searches keep existing ranking and usage behavior.

## Implementation

`PathSearchQuery` owns parsing and matching. `FileSearch` first resolves relative parent directories with a folder-only exact Spotlight query, filters their full paths before the result cap, and then runs exact/prefix leaf queries in those scopes. Explicit parent paths skip the first stage. Leaf candidates must be direct children of a matching parent, because Spotlight scopes include descendants. The metadata runner retains per-phase cancellation, timeout, and bounded accepted results. No recursive filesystem crawler or shell evaluation is introduced.

## Verification

Core tests cover adjacency, boundary matching, partial leaves, Unicode, anchors, literal metacharacters, and ordinary-search compatibility. A native fixture exceeds the per-tier limit with unrelated parents and nested children to prove filtering precedes limits. Native checks cover folders, files, missing parents, cancellation/replacement, and launcher rows in normal and file-only modes. Run all repository gates, package smoke testing, and real indexed-path checks before delivery.

## Distribution

Prepare a pull request and a local tested build. The published v1.6.1 ZIP and installed app remain unchanged until a separate release. Developer ID signing and notarization remain separate work pending the publisher's account decision.
