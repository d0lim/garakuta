# Manual Test Guide (M01–M05, N01–N08, W01–W02)

Steps to verify by hand what cannot be checked automatically. Matches the code as of 2026-09-17.

## Preconditions

1. **Quit any other menu bar manager or window switcher.** A running menu bar manager pulls Garakuta's separators into its own hidden section; another switcher may own the `⌥⇥` shortcut. The General tab of the settings window shows detected conflicts.
2. Build and run:
   ```sh
   ./scripts/bundle.sh
   open build/Garakuta.app
   ```
3. Permissions. Turn on `Garakuta` under System Settings → Privacy & Security.
   - Accessibility: all menu bar (M) and window switcher (W) features.
   - Screen Recording (optional): M03 real-icon mode, W01 thumbnails.
   - Automation (Music, Spotify): macOS asks the first time playback info is read (N03).
   - The bundle is ad-hoc signed with a designated requirement based on the bundle identifier, so a grant survives rebuilds. If System Settings shows Garakuta switched on while the app still reports the permission missing, the grant belongs to a copy signed differently: use **Reset…** next to the permission (or `tccutil reset Accessibility com.d0lim.garakuta`) and grant again.
4. Settings window: right-click the menu bar icon → Settings…. Logs:
   ```sh
   log stream --predicate 'process == "Garakuta"' --style compact
   ```

## Verified automatically (without permissions, through signal hooks)

Run with `GARAKUTA_DEBUG_SIGNALS=1` and drive the app with `SIGUSR1` (toggle notch), `SIGUSR2` (show/hide switcher), `SIGINFO` (settings window), `SIGURG` (onboarding) and `SIGALRM` (render onboarding steps to PNG when `GARAKUTA_SNAPSHOT_DIR` is set). This confirmed:

- On the notch display the panel appears in the notch area (765–962 × 33pt) at layer 26. External displays get a 160×26 island centred in the menu bar.
- Toggling expands the pill to 480×180 and collapses it again.
- The switcher panel appears at layer 101 on the display with the pointer and hides again.
- The settings window opens and closes.
- No crash while running; no process left behind after quitting.

## Onboarding (first-launch setup assistant)

Shown on first launch (no `onboardingCompleted` in `app.json`) or when run with `GARAKUTA_FORCE_ONBOARDING=1`. Also opened from "Run again…" in the General tab. The eight step layouts were rendered to PNG with `SIGALRM` (Toggle and Picker controls show as placeholders because of a renderer limitation; they are normal in the real window).

| # | Action | Expected |
| --- | --- | --- |
| O-1 | First launch | A "Set up Garakuta" window appears instead of the settings window. |
| O-2 | Pick a bundle on Welcome | Modules turn on and off immediately. The sidebar step list changes to match the enabled modules. |
| O-3 | Other utilities | Detected menu bar managers and switchers are listed with a reason; Quit removes them from the list once they exit. Without Accessibility, a note explains that detection is unavailable. |
| O-4 | Accessibility → Grant… → enable in System Settings | Within a second the banner turns green and a checkmark appears in the sidebar. |
| O-5 | Menu bar step → "Show hidden items now" | The menu bar expands; the step shows the animated ⌘-drag guide. |
| O-6 | Notch step → hover or click the notch | The banner changes to "You opened the panel". The Size segment applies the preset immediately. |
| O-7 | Switcher step → `⌥⇥` | The banner changes to "You opened the switcher". |
| O-8 | Done → turn on Launch at login → Finish | Registered as a login item; the window closes. Onboarding does not appear on the next launch. |

## Menu bar (M)

| # | Action | Expected |
| --- | --- | --- |
| M01-1 | Launch the app | A `‹` chevron is visible in the right-hand area; items left of the (collapsed) divider are hidden. |
| M01-2 | Left-click the chevron | The hidden section expands, showing the single divider and its items; the chevron flips to `›`. Clicking again collapses it. |
| M01-3 | Right-click → Show Always-Hidden Items | The double divider and the always-hidden section expand as well. |
| M01-4 | `⌘`-drag another app's icon between the dividers, then relaunch | The layout is preserved. |
| M01-5 | Right-click the chevron → Menu Bar Items → an item → Move to … | The cursor moves briefly and returns; the item moves. On failure the log shows `move ... failed`; gives up after 3 retries. |
| M01-6 | Settings › Menu Bar | The tab opens with the animated ⌘-drag guide; "Show all sections while I arrange" expands both dividers. |
| M02-1 | Hover the menu bar and wait for the configured delay | The hidden section expands. Moving the pointer away collapses it after the auto-hide delay. |
| M02-2 | Click an empty menu bar area / two-finger scroll | Each expands the section (when enabled in settings). |
| M02-3 | Record a hotkey in settings and press it | Toggles the section. |
| M03-1 | Enable Secondary bar in settings → expand the hidden section | A hidden-items bar appears below the menu bar (under the notch or near the pointer). App-icon mode is the default. |
| M03-2 | Click an item in the bar | The app's menu opens (AXPress). On failure the item is briefly revealed and clicked. |
| M03-3 | Allow Screen Recording, choose Captured mode | Real icon images are shown. |
| M03-4 | Esc or click outside | The bar closes. |
| M04-1 | Enable Auto-arrange and add enough icons to hide behind the notch | The leftmost visible items move to the hidden section (at most 3 per pass). They return when space frees up. |
| M04-2 | Right-click the chevron → Menu Bar Items → a hidden item → Show Temporarily | The item appears for the configured duration, swapping out the leftmost visible one when the bar is full. |
| M05-1 | Add and remove a Spacer in settings | A fixed-width empty item appears and disappears. |
| M05-2 | Create a Group → pick members from its menu → click the group icon | A bar containing only the group's members appears. |

## Notch panel (N)

| # | Action | Expected |
| --- | --- | --- |
| N01-1 | Launch the app | The notch continues as a black panel. External displays show an island inside the menu bar (or under it, when chosen in Appearance). Opening and closing the island keeps its top edge fixed; nothing jumps. |
| N01-2 | Click the notch | Opens expanded (shelf). Clicking again closes it. |
| N02-1 | Reorder and toggle widgets in Settings › Notch | The expanded panel's page composition changes. |
| N03-1 | Play in Music or Spotify | The panel goes compact with playback info on both sides. The Automation prompt appears once. |
| N03-2 | Start the timer widget while playing | Primary and secondary activities show together. |
| N03-3 | Connect or disconnect the power adapter | The battery activity shows for a few seconds. |
| N04-1 | Hover the notch → opens after the delay, closes when leaving | The configured delays apply. |
| N04-2 | Two-finger horizontal swipe while expanded | One page per swipe, however far the fingers travel; the next swipe turns the next page. Vertical swipe opens and closes. |
| N04-4 | Start the timer while the panel is open on a widget page | The timer widget stays on screen (the activity page is inserted before it without changing what is visible). |
| N04-3 | Drag a file onto the collapsed notch | The panel opens and the file is added to the shelf. It can be dragged out of the shelf. |
| N05-1 | Change size preset, corner radius, color, animation speed, offsets | Applied immediately. Per-display overrides work. |
| N06-1 | Enter a full-screen app | Behaves per rule (hide, compact only, always). The rule also applies in Mission Control. |
| N07-1 | Screenshot (⇧⌘3) or screen share | The panel does not appear (on by default). Turning it off makes it appear. |
| N08-1 | Open the M03 bar | The notch panel stays collapsed. Expanding the notch closes the M03 bar. |

## Window switcher (W)

| # | Action | Expected |
| --- | --- | --- |
| W01-1 | Hold `⌥⇥` | The switcher appears after the delay. `⇥` moves forward, `⇧⇥` backward. |
| W01-2 | Release `⌥` | The selected window comes to the front. Minimized windows are restored. |
| W01-3 | Select a window on another Space | Switches to that Space and brings the window forward. Without the private symbols only the app is activated. |
| W01-4 | Type while open | Filters by title and app name. Esc cancels. |
| W01-5 | Allow Screen Recording | Live thumbnails refresh roughly every 250 ms. Icons otherwise. The grid uses as many columns as fit in 80% of the screen width. |
| W01-6 | Middle-click (when enabled) | Closes the window. |
| W02-1 | Simple mode | Titles and icons only, no thumbnails. |
| W02-2 | Add app rules (Group as one / Exclude / Include even without windows) | One tile per app / removed from the list / apps without windows shown. |
| W02-3 | Change the target display (pointer, menu bar, active window) | The switcher appears on that display. |
| W02-4 | Current Space only | Windows on other Spaces disappear from the list. |

## Known limitations

- On macOS 26, if item moves fail intermittently, run `killall ControlCenter` and retry.
- External displays report a zero-height menu bar through `NSScreen.visibleFrame`; the status bar thickness is used instead.
- Capture detection for N07's auto-hide is a heuristic based on capture app bundle IDs. `sharingType = .none` is the reliable part.
- The switcher panel can get narrow with few windows; a 240pt-wide panel was observed with a short list.
