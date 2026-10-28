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
mkdir -p "$TCUBE_ROOT/.build/app-bundles" "$TCUBE_ROOT/build"
TCUBE_STAGE="$(mktemp -d "$TCUBE_ROOT/.build/app-bundles/T-Cube.XXXXXX")"
TCUBE_APP="$TCUBE_STAGE/T-Cube.app"
mkdir -p "$TCUBE_APP/Contents/MacOS" "$TCUBE_APP/Contents/Resources" "$TCUBE_APP/Contents/Frameworks"
cp "$TCUBE_BIN/TCube" "$TCUBE_APP/Contents/MacOS/TCube"
cp "$TCUBE_ROOT/Resources/Info.plist" "$TCUBE_APP/Contents/Info.plist"

# SwiftPM links binary frameworks but this script creates the application bundle.
# Preserve Sparkle's version symlinks, helpers, permissions, and resources.
TCUBE_SPARKLE="$TCUBE_BIN/Sparkle.framework"
if [[ ! -d "$TCUBE_SPARKLE" ]]; then
    TCUBE_SPARKLE="$(find "$TCUBE_ROOT/.build/app/artifacts" -type d -name Sparkle.framework -print -quit)"
fi
if [[ -z "$TCUBE_SPARKLE" || ! -d "$TCUBE_SPARKLE" ]]; then
    echo 'Missing Sparkle.framework in SwiftPM build artifacts.' >&2
    exit 1
fi
ditto "$TCUBE_SPARKLE" "$TCUBE_APP/Contents/Frameworks/Sparkle.framework"

# Public configuration only. Never put an EdDSA private key in the application.
if [[ -n "${TCUBE_UPDATE_FEED_URL:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $TCUBE_UPDATE_FEED_URL" "$TCUBE_APP/Contents/Info.plist"
fi
if [[ -n "${TCUBE_UPDATE_PUBLIC_KEY:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $TCUBE_UPDATE_PUBLIC_KEY" "$TCUBE_APP/Contents/Info.plist"
fi

TCUBE_ICONSET="$TCUBE_ROOT/.build/AppIcon.iconset"
mkdir -p "$TCUBE_ICONSET"
swift "$TCUBE_ROOT/scripts/make-icon.swift" "$TCUBE_ICONSET"
iconutil --convert icns "$TCUBE_ICONSET" --output "$TCUBE_APP/Contents/Resources/AppIcon.icns"
TCUBE_SIGN_IDENTITY="${TCUBE_SIGN_IDENTITY:--}"
TCUBE_SIGN_OPTIONS=(--timestamp=none)
if [[ "$TCUBE_SIGN_IDENTITY" != '-' ]]; then
    TCUBE_SIGN_OPTIONS=(--options runtime --timestamp)
fi
TCUBE_FRAMEWORK="$TCUBE_APP/Contents/Frameworks/Sparkle.framework"
# Sign inside out as required by Sparkle's manual distribution instructions.
# Do not use --deep for signing; helpers have their own entitlement requirements.
codesign --force --sign "$TCUBE_SIGN_IDENTITY" "${TCUBE_SIGN_OPTIONS[@]}" "$TCUBE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$TCUBE_SIGN_IDENTITY" "${TCUBE_SIGN_OPTIONS[@]}" --preserve-metadata=entitlements "$TCUBE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$TCUBE_SIGN_IDENTITY" "${TCUBE_SIGN_OPTIONS[@]}" "$TCUBE_FRAMEWORK/Versions/B/Autoupdate"
codesign --force --sign "$TCUBE_SIGN_IDENTITY" "${TCUBE_SIGN_OPTIONS[@]}" "$TCUBE_FRAMEWORK/Versions/B/Updater.app"
codesign --force --sign "$TCUBE_SIGN_IDENTITY" "${TCUBE_SIGN_OPTIONS[@]}" "$TCUBE_FRAMEWORK"
codesign --force --sign "$TCUBE_SIGN_IDENTITY" "${TCUBE_SIGN_OPTIONS[@]}" "$TCUBE_APP"
codesign --verify --deep --strict "$TCUBE_APP"
# Keep the previous generated bundle for inspection; no user installation is touched.
if [[ -e "$TCUBE_ROOT/build/T-Cube.app" ]]; then
    mv "$TCUBE_ROOT/build/T-Cube.app" "$TCUBE_STAGE/Previous-T-Cube.app"
fi
mv "$TCUBE_APP" "$TCUBE_ROOT/build/T-Cube.app"
TCUBE_APP="$TCUBE_ROOT/build/T-Cube.app"
printf '\nBuilt: %s\n' "$TCUBE_APP"
