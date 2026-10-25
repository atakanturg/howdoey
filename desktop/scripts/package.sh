#!/bin/bash
set -euo pipefail
DESKTOP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DESKTOP_ROOT"
BUILD_CONFIG="${HOWDOEY_BUILD_CONFIG:-release}"
SIGNING_DIR="$HOME/Library/Application Support/Howdoey/DevelopmentSigning"
IDENTITY="${HOWDOEY_SIGN_IDENTITY:-}"
LOCAL_SIGNING=0
if [ -z "$IDENTITY" ] && [ -f "$SIGNING_DIR/identity" ]; then
    IDENTITY="$(cat "$SIGNING_DIR/identity")"
    LOCAL_SIGNING=1
fi
if [ -z "$IDENTITY" ]; then
    if [ -d "$DESKTOP_ROOT/dist/Howdoey.app" ] && [ "${HOWDOEY_ALLOW_ADHOC_REPLACE:-0}" != "1" ]; then
        printf 'Refusing to replace an existing test app with another ad-hoc identity: this invalidates macOS permissions.
Configure stable signing first. An intentional local override is HOWDOEY_ALLOW_ADHOC_REPLACE=1.
' >&2
        exit 1
    fi
    IDENTITY="-"
fi
swift build -c "$BUILD_CONFIG" --product Howdoey
BIN_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
mkdir -p "$DESKTOP_ROOT/dist"
STAGE_DIR="$(mktemp -d "$DESKTOP_ROOT/dist/staging.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
BUNDLE="$STAGE_DIR/Howdoey.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/Howdoey" "$BUNDLE/Contents/MacOS/Howdoey"
cp "$DESKTOP_ROOT/Info.plist" "$BUNDLE/Contents/Info.plist"
if [ -f "$DESKTOP_ROOT/Resources/AppIcon.icns" ]; then cp "$DESKTOP_ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/"; fi
if [ "$LOCAL_SIGNING" = "1" ]; then
    swift "$DESKTOP_ROOT/scripts/local-signing-keychain.swift" unlock "$SIGNING_DIR" 2> "$SIGNING_DIR/helper.log"
    DEV_KEYCHAIN="$(cat "$SIGNING_DIR/keychain-path")"
    codesign --force --timestamp=none --keychain "$DEV_KEYCHAIN" --sign "$IDENTITY" "$BUNDLE"
elif [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$BUNDLE"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$BUNDLE"
fi
codesign --verify --strict "$BUNDLE"
# Replace only our generated build artifact. Website files are never touched.
if [ -d "$DESKTOP_ROOT/dist/Howdoey.app" ]; then rm -rf "$DESKTOP_ROOT/dist/Howdoey.app"; fi
mv "$BUNDLE" "$DESKTOP_ROOT/dist/Howdoey.app"
ditto -c -k --sequesterRsrc --keepParent "$DESKTOP_ROOT/dist/Howdoey.app" "$DESKTOP_ROOT/dist/Howdoey-macOS-$(uname -m).zip"
shasum -a 256 "$DESKTOP_ROOT/dist/Howdoey-macOS-$(uname -m).zip" > "$DESKTOP_ROOT/dist/SHA256SUMS.txt"
printf '\nBuilt: %s\nArchive: %s\n' "$DESKTOP_ROOT/dist/Howdoey.app" "$DESKTOP_ROOT/dist/Howdoey-macOS-$(uname -m).zip"
if [ "$IDENTITY" = "-" ]; then printf 'Local development build: ad-hoc signed, NOT notarized or ready for public distribution.\n'; fi

if [ "$LOCAL_SIGNING" = "1" ]; then printf 'Local development certificate: stable identity, NOT Apple Developer ID signed or notarized.
'; fi
