# Implementation Plan: Menu Bar, Notch Panel, Window Switcher

Written 2026-09-17. Scope: the 15 features selected in the [feature list](features.md).

## 1. Scope

| Area | Feature IDs | Count |
| --- | --- | --- |
| Menu bar | M01 M02 M03 M04 M05 | 5 |
| Notch panel | N01 N02 N03 N04 N05 N06 N07 N08 | 8 |
| Window management | W01 W02 | 2 |

The three areas run independently. N08 (coordinating the menu bar with the notch panel) is the only point where the menu bar module and the notch module interact.

## 2. Technology stack

### Decision

**Swift only. Private APIs are wrapped in a small C target (header declarations plus `dlsym` loaders).** Go, Rust and C++ are not needed for this scope.

### Reasoning

All 15 features bind directly to macOS system frameworks.

| Need | Framework | Language |
| --- | --- | --- |
| Creating status items and changing their length, panel windows, animation | AppKit, SwiftUI | Swift |
| Reading and driving other apps' menu bar items and windows | ApplicationServices (AXUIElement) | Swift (C API) |
| Querying menu bar item and window positions | CoreGraphics (CGWindowList) | CoreGraphics (C API) |
| Capturing menu bar icons and window thumbnails | ScreenCaptureKit | Swift |
| Global hotkeys and mouse events | CGEvent taps, Carbon hotkeys | Swift (C API) |
| Enumerating windows on other Spaces and minimized windows, window-level focus | Private SkyLight `CGS*` / `SLPS*` functions | C declarations called from Swift |
| Now Playing | Private MediaRemote framework | Separate adapter process (see N03 in section 3) |

- **Go**: driving AppKit through cgo means every call crosses the Objective-C runtime bridge, and main-thread rules, ARC and block callbacks become awkward. There is no pure logic (networking, CLI, data processing) in this scope for Go to own. Adding Go would create an IPC boundary and nothing else.
- **Rust**: better bindings exist than for Go, but it is unnecessary for the same reasons.
- **C++**: every private API is a C function. Declaring it in a header or fetching a pointer with `dlopen`/`dlsym` lets Swift call it directly. Nothing needs C++.

### If a second language is wanted anyway

Limit it to a tool that can live apart from the core app, such as a CLI for exporting and importing settings profiles or a socket daemon for local automation. Go would suit that, talking to the app only through a Unix domain socket or JSON files. Not part of this scope.

### Development environment

- This Mac: macOS 26.6.2 (arm64), Swift 6.3.3. **Xcode is not installed; only Command Line Tools are.** SwiftPM can build the app, but **the XCTest and Swift Testing modules ship with Xcode, so `swift test` does not run.** Xcode is required for unit tests, signing and entitlements on the `.app` bundle, Instruments and SwiftUI previews. Until then `scripts/bundle.sh` produces a manual bundle.
- Minimum macOS: **15 (Sequoia)**. This gives ScreenCaptureKit's `SCScreenshotManager` (14+), `NSScreen.safeAreaInsets` (12+) and `MenuBarExtra` (13+), and accounts up front for `CGWindowListCreateImage` being removed in 15.
- Distribution: private API and Accessibility use mean distribution outside the App Store (Developer ID plus notarization).

## 3. Implementation by feature

### 3.1 Menu bar (M01–M05)

#### Constraints observed on macOS 26 (measured on this Mac, 26.6.2, 2026-09-17)

- **Every status item window is reported as owned by the Control Center process.** `CGWindowListCopyWindowInfo` returns other apps' items only as owner "Control Center" on layer 25, and even our own app's items do not appear in the CG window list (`NSStatusBarWindow.windowNumber` is the sentinel `2^32`). Identifying an item's app by window ownership, which older menu bar managers relied on, does not work on 26. (Apple Feedback FB18327911.)
- **Items are identified through Accessibility.** For each running app: `AXUIElementCreateApplication(pid)` → `AXExtrasMenuBar` → child `AXMenuBarItem` elements give position, size and title. Our own items can be read without permission (measured). Other apps' items need the Accessibility permission. Other open-source menu bar managers that support 26 use the same approach.
- **CG window IDs are used only for capture.** AX coordinates are correlated with the Control Center layer-25 window frames to obtain a window ID, which is used only for the real-icon capture in M03.
- **Our separators' positions** come from the proxy `NSStatusBarWindow.frame`. AppKit keeps it in sync with the real position hosted by Control Center (measured: 7pt of padding relative to the AX coordinates).
- **No coexistence with other menu bar managers.** Another menu bar manager running on this Mac immediately moved newly created items into its own hidden section (x ≈ -9260). It must be quit during testing, and the app warns when one is detected.
- On 26, item moves can intermittently slow down or fail and recover after `killall ControlCenter`. A verify-and-retry loop around moves is mandatory.

The basic principle is shared with other menu bar organizers. The app creates **`NSStatusItem`s that act as separators**, and treats everything to the left of a separator as the "hidden" section. Stretching a separator's `length` to a very large value (10,000pt) pushes the items to its left off screen; restoring the length brings them back. macOS remembers item positions per app, so the layout survives a relaunch.

| ID | Implementation | Permission |
| --- | --- | --- |
| M01 | Two separators (hidden, always hidden) plus the app icon. Their `NSStatusItem Preferred Position` defaults are seeded before creation to fix the order icon · hidden · always hidden. The item list comes from walking the AX tree and each item's section is decided by comparing against the separator frames. Rearranging replays a `⌘`-drag with `CGEvent` and rescans afterwards to verify. | Accessibility |
| M02 | Global `NSEvent` mouse monitors detect hovering the menu bar and clicks on its empty area; `RegisterEventHotKey` provides the hotkey. After revealing, items auto-hide once the pointer leaves or a delay passes. | Accessibility |
| M03 | A non-activating `NSPanel` below the menu bar lists the hidden items. Two image modes: (a) ScreenCaptureKit capture by the correlated window ID, (b) the owning app's icon (works without Screen Recording). Clicking sends `AXPress` to the matching `AXMenuBarItem`; on failure the item is briefly revealed and a click event is posted at its real coordinates. | Accessibility; Screen Recording for (a) only |
| M04 | Free space is computed per display from `NSScreen.frame`, `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` (the notch) and the summed AX item widths. When space runs out, the lowest-priority items move to the hidden section; visible and hidden items can be swapped temporarily. Recomputed on every display configuration change. | Accessibility |
| M05 | Spacers are fixed-length `NSStatusItem`s. A group is one status item created by the app; clicking it shows the group's members in the same panel as M03. | Accessibility |

Risks
- Replaying a `⌘`-drag on other apps' items is timing-sensitive across macOS versions. The position must be re-read after each move and retried.
- System items (clock, Control Center) are out of scope (M12) and are never touched.
- The AX walk messages every running app and can stall on an unresponsive one. The per-app messaging timeout is capped at 0.25 s, results are cached, and rescans happen only when the menu opens.

### 3.2 Notch panel (N01–N08)

The panel is one borderless, non-activating `NSPanel` per `NSScreen`. Its level is above the menu bar (`.mainMenu + 1`) and its `collectionBehavior` is `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`. Content is drawn through a SwiftUI `NSHostingView`. The notch size comes from `NSScreen.safeAreaInsets.top` and `auxiliaryTopLeftArea`; displays without a notch get a floating pill.

| ID | Implementation |
| --- | --- |
| N01 | Three-state machine: collapsed (notch size), compact (small info on both sides), expanded (shelf). Transitions use SwiftUI spring animations. |
| N02 | A `Widget` protocol (id, minimum and maximum size, view), a widget registry and a layout editor. Layout is stored as JSON. |
| N03 | A `LiveActivity` provider protocol (priority, compact view, expanded view). First providers: now playing, timer, battery and charging. One primary and one secondary activity show at once. **Since macOS 15.4 MediaRemote access requires an entitlement**, so direct calls fail. Now-playing information therefore comes from a helper: `Sources/NowPlayingBridge` is a small C library that the app loads into the system perl interpreter (`/usr/bin/perl`, an Apple-signed binary the service does answer); it streams base64-encoded property-list records over stdout and sends transport commands. AppleScript polling of Music and Spotify remains as the fallback when the helper cannot run. |
| N04 | Hover is judged by an `NSTrackingArea` on the panel plus a global mouse monitor, with open and close delays exposed as settings. Drag uses `NSDraggingDestination` (first pass: open trigger only). Swipes page through content using `scrollWheel` event phases. |
| N05 | Size (wide, compact, custom), position offsets, background color and corner radius, animation speed. Separate settings per display. |
| N06 | On Space changes (`NSWorkspace.activeSpaceDidChangeNotification`) and app activation, `CGWindowList` decides whether the frontmost app's window fills the display. Mission Control is detected from Dock-owned windows changing size. Rules: hide, compact only, or always show in full screen. |
| N07 | `NSWindow.sharingType = .none` excludes the panel from screen sharing, screenshots and ScreenCaptureKit. Optionally auto-hide while a capture is in progress (heuristic). |
| N08 | Talks to the menu bar module through the internal event bus. Expanding the panel closes the M03 bar; opening the bar forces the panel to collapse. M04's space calculation includes the panel width so items near the notch are never covered. |

Permissions: Automation only for the AppleScript media fallback. No other N feature needs a permission.

### 3.3 Window switcher (W01–W02)

| ID | Implementation |
| --- | --- |
| W01 | `⌥Tab` is intercepted with a global hotkey. The window list merges three sources: `CGWindowListCopyWindowInfo` (visible windows on the current Space), each app's `AXUIElement` tree (minimized windows, titles) and private SkyLight `CGSCopyWindowsWithOptionsAndTags` / `CGSCopySpacesForWindows` (windows on other Spaces and full-screen windows). Thumbnails are per-window captures via `SCScreenshotManager`, refreshed only while open. Search matches title and app name. Focus uses `AXRaise` plus `NSRunningApplication.activate`; windows on other Spaces are brought forward individually with private `_SLPSSetFrontProcessWithOptions`. |
| W02 | Simple mode (no thumbnails, no Screen Recording needed), per-app rules (include apps without windows, exclude, group as one), target display (pointer, menu bar or active window) and a current-Space-only filter. |

Permissions: Accessibility (required for the full experience), Screen Recording (thumbnail mode only).

Risks
- Private SkyLight functions can break with any OS update. They all live in the `PrivateAPIs` target, and a missing symbol degrades to public-API-only behaviour.
- `SCScreenshotManager` is asynchronous; calling it on every mouse move causes lag. Thumbnails are cached per window and refreshed at a limited rate while the switcher is open.

## 4. Permission matrix

| Permission | Needed by | Without it |
| --- | --- | --- |
| Accessibility | M01–M05, W01–W02 | Menu bar sections still hide and reveal; item listing and moves are unavailable; the switcher cycles on repeated presses and selects with Return |
| Screen Recording | M03 real-icon mode, W01 thumbnails | Automatically falls back to app icons and simple mode |
| Automation (Music, Spotify) | N03 media fallback | Media activity is hidden |

Permissions are requested only when a feature that needs them is enabled, and their state is shown in the settings window.

## 5. Private API inventory

| Framework | Symbols | Feature | Fallback |
| --- | --- | --- | --- |
| SkyLight | `CGSMainConnectionID`, `CGSCopyWindowsWithOptionsAndTags`, `CGSCopySpacesForWindows`, `CGSGetWindowLevel`, `CGSManagedDisplayGetCurrentSpace` | W01 | Current Space only |
| SkyLight | `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo` | W01 window-level focus | Activate the whole app |
| MediaRemote | `MRMediaRemoteRegisterForNowPlayingNotifications` and related (through a helper process) | N03 | AppleScript polling |

All are C functions loaded with `dlsym` in `Sources/PrivateAPIs`. The menu bar module (M) uses no private API.

## 6. Module layout

```
Package.swift
Sources/
  Garakuta/            Executable. App lifecycle, settings window, module on/off, onboarding
  GarakutaCore/        Settings store, permission state, hotkeys, display geometry, event bus
  PrivateAPIs/         C target. dlsym loaders for SkyLight symbols
  MenuBarKit/          M01–M05
  NotchKit/            N01–N08
  WindowSwitcherKit/   W01–W02
Helpers/
  nowplaying/          N03 MediaRemote adapter (perl + framework), planned
scripts/
  bundle.sh            Wraps the SwiftPM build product in a .app and ad-hoc signs it
Tests/
```

Dependencies are limited to `MenuBarKit`, `NotchKit`, `WindowSwitcherKit` → `GarakutaCore`. N08 goes through the event bus in `GarakutaCore` so no Kit imports another.

## 7. Milestones and status (2026-09-17)

| Step | Content | Status |
| --- | --- | --- |
| 0 | Skeleton: SwiftPM package, bundle script, settings store, permission screen | Done |
| 1 | M01 → M02 → M04 | Implemented, awaiting manual verification |
| 2 | M05 → M03 | Implemented, awaiting manual verification |
| 3 | N01 → N05 → N04 | Implemented. Panel position, expand and collapse verified through the signal hooks |
| 4 | N06 → N07 → N02 | Implemented, awaiting manual verification |
| 5 | N03 → N08 | Implemented. N03 uses the perl-hosted helper with AppleScript polling (Music, Spotify) as fallback |
| 6 | W01 → W02 | Implemented. Show and hide verified through the signal hooks; all 15 private symbols load |
| 7 | Integration QA | [Manual test guide](manual-tests.md) written. Not run yet: needs the Accessibility grant and any other menu bar manager quit |

Fixed during implementation
- `NSPanel.isFloatingPanel = true` reset the level to floating (3), pushing the panel under the menu bar. Removed; only the explicit level (mainMenu+2) is used.
- `NSHostingView`'s default `sizingOptions` grew the window to the SwiftUI content size. Set to `[]` so the state machine owns the frame.
- In an accessory app the SwiftUI `Settings` scene did not open via `showSettingsWindow:`. The settings window is hosted in an `NSWindow` directly.
- Synthetic input (`CGEventPost`) from a process without Accessibility is dropped. Signal hooks, enabled only with `GARAKUTA_DEBUG_SIGNALS=1`, drive the app for testing.

Added later (2026-09-17)
- Interactive onboarding (O02 feature bundle choice, O07 launch at login, O10 per-feature permission guidance): an eight-step setup assistant. Permission grants, quitting conflicting apps, opening the notch and invoking the switcher are reflected live through 0.5 s polling. Shown on first launch and reopenable from Settings.
- Debug signal hook `SIGALRM`: renders each onboarding step to PNG with `ImageRenderer` so layouts can be reviewed without Screen Recording access.

Fixed after code review (2026-09-17)
- The menu bar scan sent AX messages to every process and could stall. It now scans UI apps only, skips Control Center, SystemUIServer, Spotlight and Siri, and caches results for 1 s. System items are never moved.
- Assignment-enforcement and auto-arrange tasks stayed alive after the module was turned off and could still ⌘-drag. Every task, monitor and timer is torn down in `stop()` and `isRunning` is checked.
- Auto-arrange and assignment enforcement no longer ping-pong the same item; items explicitly assigned `visible` are excluded from auto-arrange.
- Now Playing AppleScript execution moved from the main thread to a dedicated serial queue. Overlapping polls are skipped and only running players are queried.
- Enumeration of windows on other Spaces relied on AX alone. Window IDs are now collected first with SkyLight's `CGSCopyWindowsWithOptionsAndTags`, so the list is built from window server data even when AX is unavailable or times out.
- The switcher's window scan runs in the background and shows the last result immediately. AX timeout is 0.1 s.
- Every settings type decodes leniently so adding a field never wipes existing settings.
- `SpaceStateObserver` polls only while it has subscribers.

## 8. Prior art and licensing

Existing open-source menu bar managers, notch panels and window switchers were studied for their approaches; they are published under GPL-3.0 and MIT licenses. **No code was copied from any of them.** Everything under `Sources/` was written for this project. The private SkyLight record layout used for window-level focus follows a publicly documented description.

## 9. Confirmed decisions (2026-09-17)

- Language: **Swift only.** Private APIs are loaded with `dlsym` in the `PrivateAPIs` C target. No Go side tool.
- Minimum macOS: **15 (Sequoia).** Intel support (O09) is undecided; only arm64 is verified.
- App name `Garakuta`, bundle ID `com.d0lim.garakuta`.
- Xcode is installed after milestone 0, before signing, entitlements and unit tests.
