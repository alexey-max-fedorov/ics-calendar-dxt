#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building ICalBridge for arm64-apple-macosx..."
swift build -c release --arch arm64

OUT_BIN_DIR="../bin"
APP_PATH="$OUT_BIN_DIR/ICalBridge.app"
APP_CONTENTS="$APP_PATH/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"

rm -rf "$APP_PATH"
mkdir -p "$APP_MACOS"

cp .build/arm64-apple-macosx/release/ICalBridge "$APP_MACOS/ical-bridge"
chmod +x "$APP_MACOS/ical-bridge"

cp Sources/ICalBridge/BundleInfo.plist "$APP_CONTENTS/Info.plist"

# Re-sign the .app with ad-hoc identity so the bundle Info.plist is sealed.
codesign --force --sign - --deep "$APP_PATH"

# Optional: also keep a thin standalone binary for terminal hardware tests
cp "$APP_MACOS/ical-bridge" "$OUT_BIN_DIR/ical-bridge"

echo "Built: $APP_PATH"
echo "        $OUT_BIN_DIR/ical-bridge (terminal-only fallback)"
