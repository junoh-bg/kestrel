# Settings checkbox contrast

The shipped 1.6.0 binary declares macOS 14 SDK compatibility. A standalone preview compiled with the current SDK followed a different AppKit drawing path and showed legible checkbox titles, while the shipped app drew black titles on dark surfaces. Matching the preview's Mach-O SDK compatibility to 14 reproduced the user's screenshot. A standalone pixel regression failed in 12 cases before the fix.

The shared button cell now draws checkbox text with the explicit palette color instead of passing it back through NSButtonCell's compatibility-dependent title renderer. Native checkbox glyphs, state, accessibility, actions, and normal action-button layout remain unchanged. Text is vertically centered in the native title rectangle.

Final review covered drawing bounds, disabled opacity, native toggling and accessibility semantics, theme changes, detached pages, and release metadata. No blocking findings remained. The initial direct-drawing experiment also changed action-button text alignment; the final patch restricts it to checkboxes.

Verification on macOS 27.0.1:

- 76 serial Swift tests and eight packaging tests passed.
- The standalone checkbox pixel regression passed with both macOS 14 and current SDK compatibility; checked, unchecked, enabled, disabled, and system appearance combinations are included.
- All 25 Settings section/theme combinations were rendered through actual theme-selection actions and visually reviewed with isolated sample data.
- The compatibility-matched live fixture reproduced the original black checkbox title, then showed the corrected light title.
- Release build, package identity/icons, nested code signatures, isolated packaged startup, strict Swift formatting, and diff checks passed.

Version 1.6.1/build 12 carries the correction. Existing 1.6.0 installations can use the signed updater. This does not establish acceptance on a physical macOS 14 device; that and separate-Mac download checks remain unverified.
