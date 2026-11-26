#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Eave"
DEST_APP="/Applications/${APP_NAME}.app"
BUILT_APP="build/Build/Products/Release/${APP_NAME}.app"
ENTITLEMENTS="Eave/Resources/Eave.entitlements"
DEFAULT_LOCAL_CERT="abcdlsj Local Dev"

resolve_sign_identity() {
    if [[ -n "${EAVE_SIGN_IDENTITY:-}" ]]; then
        echo "$EAVE_SIGN_IDENTITY"
        return
    fi

    if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"${DEFAULT_LOCAL_CERT}\""; then
        echo "$DEFAULT_LOCAL_CERT"
        return
    fi

    echo "-"
}

SIGN_IDENTITY="$(resolve_sign_identity)"
echo "==> Building ${APP_NAME} (Release, arm64)..."
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "⚠️  No stable local certificate found (looked for \"${DEFAULT_LOCAL_CERT}\"). Falling back to ad-hoc signing."
    echo "    macOS Accessibility permission may reset across rebuilds. Set EAVE_SIGN_IDENTITY to use a stable cert."
else
    echo "==> Using stable signing identity: ${SIGN_IDENTITY}"
fi

BUILD_REVISION="$(git describe --tags --always --dirty 2>/dev/null || true)"
xcodebuild build \
    -project Eave.xcodeproj \
    -scheme Eave \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    EAVE_BUILD_REVISION="$BUILD_REVISION" \
    -quiet

echo "==> Signing ${BUILT_APP}..."
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "-" "$BUILT_APP"
else
    codesign --force --deep --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$BUILT_APP"
fi

codesign --verify --deep --strict "$BUILT_APP"

echo "==> Replacing ${DEST_APP}..."
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

rm -rf "$DEST_APP"
ditto "$BUILT_APP" "$DEST_APP"

echo "==> Verifying installed signature & designated requirement:"
codesign -d -r - "$DEST_APP" 2>&1

echo "==> Launching ${DEST_APP}..."
open -a "$DEST_APP"
sleep 0.8
pgrep -fl "${DEST_APP}/Contents/MacOS/${APP_NAME}"
