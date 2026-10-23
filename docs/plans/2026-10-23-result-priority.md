# Consistent search result type priorities

## Diagnosis and intended behavior

The launcher initially displays cached applications. Its merge function then promotes up to three exact folder matches above those apps and mixes the rest of Spotlight results by relevance. Indexed applications also remain mixed with folders and files. This causes a matching app to move down after indexing finishes, even when the query has not changed.

Use the requested strict category order: applications, folders, files, then settings and web actions. Preserve existing relevance and usage ranking within each category. Apply display limits after grouping, and deduplicate cached/indexed entries. File-only mode excludes applications from every source. Calculator, clipboard, and snippet modes retain their dedicated behavior. Existing explicit keyboard selection and captured action targets remain intact.

A category bonus inside the global core ranker would couple unrelated metadata-search limits to launcher presentation. A launcher merge policy is smaller and applies consistently to both immediate and delayed results. Implement the policy in browsingRows and retain the existing core ranking algorithm.

## Verification

Cover exact folder versus matching application, indexed-only applications, prefix/substring folders versus exact files, duplicate catalog/indexed apps, settings/web placement, within-category relevance and learned usage, file-only behavior, and grouping before display limits. Include an actual asynchronous Spotlight regression verifying that an arriving exact folder does not displace the application or its default selection. Run the full required gates and inspect the signed installed package before delivery.

## Review and results

Reviewed the single merge-policy change for category precedence, filtering/deduplication, ranking stability, limits, and interaction with asynchronous results and existing selection handling. No blocking findings remained. The shared ranker and explicit-selection/action snapshot logic are unchanged.

Verified 93 Swift tests (17 XCTest plus 76 Swift Testing), 12 packaging/signing tests, strict Swift format lint, whitespace checks, release build, package validation, strict signature verification, and isolated packaged smoke testing. New regressions were observed failing before the fix, including an actual delayed Spotlight folder displacing a matching application.

On the installed 1.7.1 app, Cursor initially appeared first, then fell below three exact folder matches. Installed the signed local 1.7.2/build 15 patch with a backup of the previous app under ignored dist/archive/. The same live search kept Cursor Application first after indexing, followed by folders, files, and Google. Private search-result paths were not copied into this report. Public release links and signed feed remain on 1.7.1 pending merge/release. Separate-Mac acceptance remains unverified.
