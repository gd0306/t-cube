#!/bin/bash
set -euo pipefail

TCUBE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TCUBE_SKIP_BUILD=false
if [[ "${1:-}" == "--skip-build" && $# == 1 ]]; then
    TCUBE_SKIP_BUILD=true
elif [[ $# != 0 ]]; then
    echo 'Usage: bash scripts/build-dmg.sh [--skip-build]' >&2
    exit 2
fi

if [[ "$TCUBE_SKIP_BUILD" == false ]]; then
    bash "$TCUBE_ROOT/scripts/build-app.sh"
fi

TCUBE_APP="$TCUBE_ROOT/build/T-Cube.app"
if [[ ! -d "$TCUBE_APP" || ! -x "$TCUBE_APP/Contents/MacOS/TCube" ]]; then
    echo 'Missing built app. Run bash scripts/build-app.sh first.' >&2
    exit 1
fi

TCUBE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$TCUBE_APP/Contents/Info.plist")"
if [[ ! "$TCUBE_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo 'CFBundleShortVersionString is not safe for a DMG filename.' >&2
    exit 1
fi
codesign --verify --deep --strict "$TCUBE_APP"

# Keep each staging directory for inspection; never clear another build's files.
mkdir -p "$TCUBE_ROOT/.build/dmg-staging" "$TCUBE_ROOT/build"
TCUBE_STAGE="$(mktemp -d "$TCUBE_ROOT/.build/dmg-staging/T-Cube.XXXXXX")"
ditto "$TCUBE_APP" "$TCUBE_STAGE/T-Cube.app"
ln -s /Applications "$TCUBE_STAGE/Applications"
cp "$TCUBE_ROOT/Resources/DMG-install.txt" "$TCUBE_STAGE/安装说明.txt"
codesign --verify --deep --strict "$TCUBE_STAGE/T-Cube.app"

TCUBE_DMG="$TCUBE_ROOT/build/T-Cube-$TCUBE_VERSION.dmg"
hdiutil create -volname 'T-Cube' -srcfolder "$TCUBE_STAGE" \
    -fs HFS+ -format UDZO -ov "$TCUBE_DMG"
printf '\nBuilt: %s\nStaging: %s\n' "$TCUBE_DMG" "$TCUBE_STAGE"
