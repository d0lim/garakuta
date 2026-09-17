#!/bin/sh
# Wraps the SwiftPM build product in a minimal .app bundle and ad-hoc signs it.
# Needed until an Xcode project exists: TCC (Accessibility / Screen Recording) keys permissions to a bundle ID.
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Garakuta"
APP="build/Garakuta.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Garakuta"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Garakuta</string>
  <key>CFBundleIdentifier</key><string>com.d0lim.garakuta</string>
  <key>CFBundleName</key><string>Garakuta</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Garakuta reads what Music or Spotify is playing to show it in the notch panel.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP"
