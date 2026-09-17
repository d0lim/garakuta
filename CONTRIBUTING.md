# Contributing to Garakuta

Thanks for taking the time. This is a small project, so the process is light.

## Before you start

- Check [open issues](https://github.com/d0lim/garakuta/issues) first. For anything larger than a bug fix, open an issue to talk it through before writing code.
- Read the [implementation plan](docs/plan/implementation-plan.md) for the architecture and the [manual test guide](docs/plan/manual-tests.md) for how features are verified.

## Development setup

- macOS 15 or later on Apple silicon (Intel is untested).
- Xcode 16 or later for `swift test`, signing and Instruments. Command Line Tools alone can build the app but cannot run the tests.

```sh
swift build              # build the package
./scripts/bundle.sh      # produce build/Garakuta.app with an ad-hoc signature
swift test               # unit tests (Xcode required)
```

Grant Accessibility (and optionally Screen Recording) to `build/Garakuta.app` in System Settings to exercise the menu bar and switcher features. Quit any other menu bar manager or window switcher while testing; they fight over the same menu bar and shortcut.

Debug hooks: run the binary with `GARAKUTA_DEBUG_SIGNALS=1` and send `SIGUSR1` (toggle notch), `SIGUSR2` (switcher), `SIGINFO` (settings), `SIGURG` (onboarding) or `SIGALRM` with `GARAKUTA_SNAPSHOT_DIR` set (render onboarding steps to PNG).

## Code guidelines

- Swift 6 with strict concurrency. Everything that touches AppKit is `@MainActor`; anything else must be `Sendable`.
- Feature modules (`MenuBarKit`, `NotchKit`, `WindowSwitcherKit`) depend only on `GarakutaCore` and talk to each other through `EventBus`. Never import one Kit from another.
- Private macOS APIs live only in `Sources/PrivateAPIs`, resolved with `dlsym`, and every caller must degrade gracefully when a symbol is missing.
- No third-party dependencies. If you must add one, explain why in the pull request.
- Do not copy code from GPL-licensed projects. Studying an approach is fine; pasting code is not.
- Settings types get a hand-written lenient `init(from:)` so adding a field never resets a user's saved settings.

## Pull requests

1. Branch from `main`.
2. Keep the change focused; one feature or fix per PR.
3. `swift build` must pass with zero warnings. Run the relevant rows of the manual test guide and say which ones you ran.
4. Describe what changed and why in the PR body. Screenshots or a short recording help for UI work.

## Releasing (maintainers)

1. Move the `Unreleased` notes in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading and update the links at the bottom.
2. Commit, then tag and push: `git tag -a vX.Y.Z -m "Garakuta X.Y.Z" && git push origin main vX.Y.Z`.
3. The Release workflow builds the app, zips it and publishes a GitHub release with the changelog section as notes.
4. Once the release exists, run `scripts/update-cask.sh X.Y.Z` to write and push the Homebrew cask to the `d0lim/tap` tap. It downloads the asset, computes the checksum and commits `Casks/garakuta.rb`.
5. Check with `brew update && brew upgrade --cask garakuta`.

## Reporting bugs

Use the bug report template. Include your macOS version, whether Accessibility and Screen Recording are granted, which displays are connected (notch or not), and the output of:

```sh
log show --last 5m --predicate 'process == "Garakuta"' --style compact
```

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
