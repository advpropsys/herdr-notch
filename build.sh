#!/bin/sh
# Builds "Herdr Notch.app" and installs it into ~/Applications (or the folder given as the first argument).
# Needs only the Xcode command line tools: xcode-select --install
set -e
cd "$(dirname "$0")"
DEST="${1:-$HOME/Applications}"
APP="$DEST/Herdr Notch.app"

swift build -c release
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/HerdrNotch" "$APP/Contents/MacOS/HerdrNotch"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
echo "Start it with: open \"$APP\""
