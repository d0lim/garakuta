# Security Policy

## Scope

Garakuta runs entirely on your Mac. It has no accounts, no network features and no telemetry. The sensitive surfaces are the permissions it can hold:

- **Accessibility** lets it read other apps' menu bar items and windows and post input events.
- **Screen Recording** lets it capture menu bar icons and window thumbnails. Captures are kept in memory only.
- **Automation** (Music, Spotify) is used to read playback state.

A bug that leaks captured images, records input, or acts on other apps beyond what the UI shows counts as a security issue.

## Reporting

Please do not open a public issue for security problems. Use [GitHub's private vulnerability reporting](https://github.com/d0lim/garakuta/security/advisories/new) on this repository. Include steps to reproduce and your macOS version.

You should get an acknowledgement within a week. Fixes ship as a new release with a note in the changelog; credit is given unless you prefer otherwise.

## Supported versions

Only the latest release on `main` receives fixes.
