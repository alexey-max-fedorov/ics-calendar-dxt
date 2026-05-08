#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building ICalBridge for arm64-apple-macosx..."
swift build -c release --arch arm64

OUT_DIR="../bin"
mkdir -p "$OUT_DIR"
cp .build/arm64-apple-macosx/release/ICalBridge "$OUT_DIR/ical-bridge"
chmod +x "$OUT_DIR/ical-bridge"

echo "Built: $OUT_DIR/ical-bridge"
