# Garakuta

[![CI](https://github.com/d0lim/garakuta/actions/workflows/ci.yml/badge.svg)](https://github.com/d0lim/garakuta/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black)

A menu bar organizer, a notch panel and a window switcher for macOS in one small, local-only app. Swift, no dependencies, no accounts, no telemetry.

## What it does

**Menu bar** — hide icons behind a separator, keep an always-hidden section, reveal them by hover, click, scroll or hotkey, and browse hidden icons in a bar below the menu bar (also under the notch). Icons can be auto-hidden when the menu bar runs out of room, grouped, or spaced out. Works on macOS 26, where every status item is hosted by Control Center and has to be discovered through Accessibility.

**Notch panel** — an island-style panel on every display: music controls (Music, Spotify), a timer, battery, and a shelf you can drop files on. Hover, click, swipe and drag gestures, per-display appearance, full-screen and Mission Control rules, and it stays out of screenshots and screen sharing.

**Window switcher** — hold ⌥⇥ to see every window with live thumbnails, including minimized windows and windows on other Spaces. Type to filter. Per-app rules, a titles-only mode and a choice of which display it opens on.

A first-launch setup assistant walks through feature bundles, conflicting utilities, permissions and a live tour of each module.

## Status

All 15 planned features are implemented and the app builds and runs. Interaction paths that need Accessibility permission have been exercised only by the [manual test guide](docs/plan/manual-tests.md); expect rough edges. There are no releases yet, so build it yourself.

## Build

Requires macOS 15 or later. Xcode 16 is recommended; Command Line Tools alone can build the app but not run the tests.

```sh
swift build
./scripts/bundle.sh        # → build/Garakuta.app, ad-hoc signed
open build/Garakuta.app
```

Then grant Accessibility (and, if you want icon captures and thumbnails, Screen Recording) in System Settings. Quit any other menu bar manager or window switcher first; they compete for the same menu bar and shortcut. Because the bundle is ad-hoc signed, macOS may forget the Accessibility grant after a rebuild; remove and re-add the app in the list.

## Permissions

| Permission | Needed for | Without it |
| --- | --- | --- |
| Accessibility | Listing and moving other apps' menu bar icons, clicking them from the hidden-items bar, minimized windows, releasing ⌥ to select | Sections still hide and reveal; you ⌘-drag icons yourself; the switcher cycles with repeated ⌥⇥ and selects with Return |
| Screen Recording | Real icon images and window thumbnails | App icons and titles |
| Automation (Music, Spotify) | Now-playing info in the notch | No music activity |

## Project layout

```
Sources/Garakuta           app shell, settings window, onboarding
Sources/GarakutaCore       settings store, hotkeys, display geometry, event bus, window capture
Sources/MenuBarKit         M01–M05
Sources/NotchKit           N01–N08
Sources/WindowSwitcherKit  W01–W02
Sources/PrivateAPIs        dlsym loaders for SkyLight / HIServices private symbols (C)
docs/plan                  feature list, implementation plan, manual test guide
```

Feature IDs refer to the [feature list](docs/plan/features.md); the architecture and the macOS 26 constraints are in the [implementation plan](docs/plan/implementation-plan.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues go through [SECURITY.md](SECURITY.md). Prior art and included third-party material are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE)
