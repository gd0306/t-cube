#!/bin/bash
set -euo pipefail

TCUBE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TCUBE_CONFIGURATION=release
if [[ "${1:-}" == "--debug" && $# == 1 ]]; then
    TCUBE_CONFIGURATION=debug
elif [[ $# != 0 ]]; then
    echo 'Usage: bash scripts/build-app.sh [--debug]' >&2
    exit 2
fi

swift build --package-path "$TCUBE_ROOT" \
    --scratch-path "$TCUBE_ROOT/.build/app" \
    --configuration "$TCUBE_CONFIGURATION" --product TCube
TCUBE_BIN="$(swift build --package-path "$TCUBE_ROOT" \
    --scratch-path "$TCUBE_ROOT/.build/app" \
    --configuration "$TCUBE_CONFIGURATION" --show-bin-path)"
TCUBE_APP="$TCUBE_ROOT/build/T-Cube.app"
mkdir -p "$TCUBE_APP/Contents/MacOS" "$TCUBE_APP/Contents/Resources"
cp "$TCUBE_BIN/TCube" "$TCUBE_APP/Contents/MacOS/TCube"
cp "$TCUBE_ROOT/Resources/Info.plist" "$TCUBE_APP/Contents/Info.plist"

TCUBE_ICONSET="$TCUBE_ROOT/.build/AppIcon.iconset"
mkdir -p "$TCUBE_ICONSET"
swift "$TCUBE_ROOT/scripts/make-icon.swift" "$TCUBE_ICONSET"
iconutil --convert icns "$TCUBE_ICONSET" --output "$TCUBE_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$TCUBE_APP"
printf '\nBuilt: %s\n' "$TCUBE_APP"
