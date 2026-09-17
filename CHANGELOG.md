# Changelog

All notable changes to Garakuta are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- App icon, and a matching template glyph for the menu bar item and the onboarding window.
- "Reset…" next to each permission, for grants that belong to an earlier copy of the app.

### Changed

- Settings window pages are switched from an icon strip along the top instead of a segmented control.
- The setup assistant window no longer shows a title bar.

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

[Unreleased]: https://github.com/d0lim/garakuta/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/d0lim/garakuta/releases/tag/v0.1.0
