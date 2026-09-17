# Changelog

All notable changes to Garakuta are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The compact state sizes its side areas to the content they show instead of a fixed width, so a small glyph
  adds only a little to the notch and a longer label gets the room it needs.
- The notch panel and the island no longer cast a shadow in any state.
- The panel appears in screenshots by default; hiding it from screen capture is now an opt-in setting.
- The timer widget is redrawn: duration presets, minute adjustment, a progress bar while running, and buttons
  that are legible on the dark panel.
- The chevron itself is the boundary of the hidden section; the separate divider next to it is gone.

### Fixed

- Now Playing shows media playing in browsers (YouTube, YouTube Music and the like). The system reports that a
  browser is playing but withholds its metadata, so the title of the playing tab is read through Apple Events
  instead; the browser asks for Automation permission once.
- The now-playing helper could stall for good when the service answered a query on the queue the helper was
  waiting on; queries, callbacks and notifications now run on separate queues, and an unanswered query is dropped.

## [0.3.0] - 2026-09-17

### Added

- Now Playing follows whatever app the system reports as playing (browsers, podcast and video players included), with
  artwork and live progress. A small helper is loaded into the system perl interpreter for this; the Music and
  Spotify Apple Events polling remains as a fallback.
- Menu Bar settings and the setup assistant show an animated guide to arranging icons with ⌘-drag.
- The shelf keeps its files across relaunches, shows Quick Look previews, and offers Open, Reveal in Finder, Share
  (including AirDrop), Compress, Copy and Remove per file, plus Drag all, Share and Compress for the whole shelf.
  A hint appears while a file is dragged over the panel.

### Changed

- The menu bar item is a chevron that points at the hidden items and flips when they are shown; the section
  boundaries are thin dividers.
- Menu Bar settings no longer list every icon with a section picker; group members are chosen from a menu on the
  group row. Automatic arrangement hides the leftmost visible icon first.
- The window switcher lays tiles out in as many columns as fit the screen instead of a single column.
- A paused now-playing item keeps its activity for five minutes, then steps aside.
- The compact state adds less width on each side of the notch or island when an activity appears.

### Fixed

- The island on displays without a notch no longer jumps when opening or closing; its top edge stays put.
- A two-finger swipe on the expanded panel turns exactly one page.
- Starting the timer while the panel is open keeps the timer widget on screen instead of jumping to the new
  activity page.

## [0.2.0] - 2026-09-17

### Added

- App icon, and a matching template glyph for the menu bar item and the onboarding window.
- "Reset…" next to each permission, for grants that belong to an earlier copy of the app.

### Changed

- Settings window pages are switched from an icon strip along the top instead of a segmented control.
- The setup assistant window no longer shows a title bar.
- On displays without a notch the island now sits inside the menu bar and expands from the top edge of the
  screen, like the notch panel. The previous floating position is still available under Notch → Appearance.

### Fixed

- Accessibility and Screen Recording grants stayed attached to one exact build: the app bundle is now signed with a
  designated requirement based on its bundle identifier, so a grant survives rebuilds and updates.

## [0.1.0] - 2026-09-17

First public release.

### Added

- Menu bar: hidden and always-hidden sections, reveal on hover, click, scroll or hotkey with auto-rehide, a secondary bar for hidden items (below the notch or near the pointer), automatic arrangement when the menu bar runs out of room, spacers and groups. Works on macOS 26, where status items are hosted by Control Center and discovered through Accessibility.
- Notch panel: island-style panel on every display with widgets (now playing, timer, battery, clock, file shelf), live activities, hover, swipe and drag gestures, per-display appearance, full-screen and Mission Control rules, and exclusion from screenshots and screen sharing.
- Window switcher: Option-Tab switcher with live thumbnails, minimized windows and windows on other Spaces, type-to-filter, titles-only mode, per-app rules and a choice of target display.
- Setup assistant on first launch: feature bundles, conflict detection, permission guidance with live status, module tours, launch at login.
- Settings window with per-module tabs and permission status.

### Known limitations

- The app is ad-hoc signed. macOS quarantines downloaded copies; the Homebrew cask clears the flag after install, and manual downloads need "Open Anyway" in System Settings › Privacy & Security.
- Now-playing information comes from Music and Spotify through Apple Events only.
- Intel Macs are untested.

[Unreleased]: https://github.com/d0lim/garakuta/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/d0lim/garakuta/releases/tag/v0.3.0
[0.2.0]: https://github.com/d0lim/garakuta/releases/tag/v0.2.0
[0.1.0]: https://github.com/d0lim/garakuta/releases/tag/v0.1.0
