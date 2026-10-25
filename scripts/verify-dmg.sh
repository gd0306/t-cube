#!/bin/bash
set -euo pipefail

TCUBE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TCUBE_APP="$TCUBE_ROOT/build/T-Cube.app"
TCUBE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TCUBE_APP/Contents/Info.plist")"
TCUBE_DMG="$TCUBE_ROOT/build/T-Cube-$TCUBE_VERSION.dmg"
hdiutil verify "$TCUBE_DMG"
mkdir -p "$TCUBE_ROOT/.build/dmg-staging"
TCUBE_MOUNT="$(mktemp -d "$TCUBE_ROOT/.build/dmg-staging/verify.XXXXXX")"
hdiutil attach -readonly -nobrowse -mountpoint "$TCUBE_MOUNT" "$TCUBE_DMG"
trap 'hdiutil detach "$TCUBE_MOUNT"' EXIT
test -d "$TCUBE_MOUNT/T-Cube.app"
test -x "$TCUBE_MOUNT/T-Cube.app/Contents/MacOS/TCube"
test -L "$TCUBE_MOUNT/Applications"
test "$(readlink "$TCUBE_MOUNT/Applications")" = /Applications
cmp "$TCUBE_ROOT/Resources/DMG-install.txt" "$TCUBE_MOUNT/安装说明.txt"
cmp "$TCUBE_APP/Contents/Info.plist" "$TCUBE_MOUNT/T-Cube.app/Contents/Info.plist"
cmp "$TCUBE_APP/Contents/MacOS/TCube" "$TCUBE_MOUNT/T-Cube.app/Contents/MacOS/TCube"
codesign --verify --deep --strict "$TCUBE_MOUNT/T-Cube.app"
printf 'Verified T-Cube %s: app, executable, signature, Applications link and installation note.\n' "$TCUBE_VERSION"
hdiutil detach "$TCUBE_MOUNT"
trap - EXIT
