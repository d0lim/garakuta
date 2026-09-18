#!/bin/sh
# Wraps the SwiftPM build product in a minimal .app bundle and ad-hoc signs it.
# Needed until an Xcode project exists: TCC (Accessibility / Screen Recording) keys permissions to a bundle ID.
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
# Version comes from $VERSION, else the nearest v* tag, else 0.0.0 for local builds.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="build/Garakuta.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Garakuta" "$APP/Contents/MacOS/Garakuta"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Now-playing helper: loaded into the system perl interpreter at runtime (see Sources/NowPlayingBridge).
cp "$BIN_DIR/libNowPlayingBridge.dylib" "$APP/Contents/Frameworks/libNowPlayingBridge.dylib"
cp Resources/nowplaying.pl "$APP/Contents/Resources/nowplaying.pl"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Garakuta</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.d0lim.garakuta</string>
  <key>CFBundleName</key><string>Garakuta</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Garakuta reads what is playing in Music, Spotify or a browser tab to show it in the notch panel.</string>
  <key>NSAudioCaptureUsageDescription</key><string>Garakuta reads the level of what you are playing so the bars beside the notch can move with the music. Only the levels are used; no audio is recorded or kept.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Ad-hoc signature with a designated requirement based on the bundle identifier instead of the default code hash,
# so Accessibility and Screen Recording grants survive rebuilds and updates.
codesign --force --sign - "$APP/Contents/Frameworks/libNowPlayingBridge.dylib"
codesign --force --sign - --identifier com.d0lim.garakuta \
  --requirements '=designated => identifier "com.d0lim.garakuta"' "$APP"
echo "built $APP ($VERSION, build $BUILD_NUMBER)"
