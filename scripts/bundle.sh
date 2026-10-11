#!/usr/bin/env bash
# Builds a universal release binary and wraps it in CleanItUp.app, then zips it for download.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/CleanItUp.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CleanItUp" "$APP/Contents/MacOS/CleanItUp"
cp Support/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run locally, not notarized.
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

# Disk image with an Applications shortcut, the usual way to install a Mac app.
STAGING="build/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname CleanItUp -srcfolder "$STAGING" -ov -format UDZO build/CleanItUp.dmg
rm -rf "$STAGING"
echo "Built build/CleanItUp.dmg"
