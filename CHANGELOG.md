# Changelog

## 1.1.0 — 2026-11-24

- Fixed a constraints loop that could crash the app when dragging its window between monitors. Window sizing is deferred until dragging finishes and unchanged sizes do not trigger another layout.
- Added compact, draggable main and Settings windows, centered on the invoking display, with fullscreen disabled and one shared size that stays below 35% of every connected display.
- Made the main window taller and narrower while preserving its screen-area cap; hid persistent scrollbars while retaining scrolling.
- Updated the app icon and gave the menu-bar template an explicit 22-point size.
- Made engine shutdown asynchronous, guarded engine transitions and overlapping refreshes, and moved tracker synchronization out of the polling loop.
- Reduced repeated dashboard layout and graph updates.
- Added regression coverage for multi-monitor movement, tracking-mode deferral, sizing limits, and reopening.
- Included the existing Chrome extension, also usable in Chrome Beta.

## 1.0.0 — 2026-11-10

- Initial GitHub release of the native macOS download manager and Chrome extension.
- Removed redundant Settings shortcuts from the dashboard Speed Mode card and menu-bar popup. Settings remains available in the sidebar.
