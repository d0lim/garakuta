# Changelog

All notable changes to Garakuta are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
