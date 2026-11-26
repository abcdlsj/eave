#!/usr/bin/env bash
# Builds a signed universal (arm64 + x86_64) Eave.app and packs it into a dmg.
#
#   scripts/package-release.sh 0.1.0
#   EAVE_SIGN_IDENTITY="Developer ID Application: ..." scripts/package-release.sh 0.1.0
#
# Used by .github/workflows/release.yml. Without a signing identity the app is
# ad-hoc signed: Homebrew installs carry no quarantine attribute, so it launches
# normally; a dmg downloaded through a browser is blocked by Gatekeeper instead.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: scripts/package-release.sh <version>" >&2
    exit 1
fi
VERSION="${VERSION#v}"

IDENTITY="${EAVE_SIGN_IDENTITY:--}"
BUILD_NUMBER="${EAVE_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
OUT_DIR="${EAVE_DIST_DIR:-dist}"
DERIVED_DATA="build/release"
ENTITLEMENTS="Eave/Resources/Eave.entitlements"
DMG="${OUT_DIR}/eave_${VERSION}_darwin_universal.dmg"
ZIP="${OUT_DIR}/eave_${VERSION}_darwin_universal.zip"

command -v xcodegen >/dev/null || { echo "xcodegen is required: brew install xcodegen" >&2; exit 1; }

echo "==> Generating Eave.xcodeproj from project.yml"
xcodegen generate

echo "==> Building Eave ${VERSION} (${BUILD_NUMBER}) universal release"
xcodebuild build \
    -project Eave.xcodeproj \
    -scheme Eave \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet

APP="${DERIVED_DATA}/Build/Products/Release/Eave.app"
[[ -d "$APP" ]] || { echo "missing ${APP}" >&2; exit 1; }

ARCHS_BUILT="$(lipo -archs "$APP/Contents/MacOS/Eave")"
case "$ARCHS_BUILT" in
    *arm64*x86_64*|*x86_64*arm64*) ;;
    *) echo "expected a universal binary, got: ${ARCHS_BUILT}" >&2; exit 1 ;;
esac

echo "==> Signing with identity: ${IDENTITY}"
codesign --force --deep --options runtime --timestamp=none \
    --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Packing dmg"
mkdir -p "$OUT_DIR"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "${STAGING}/Eave.app"
ln -s /Applications "${STAGING}/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Eave" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> ${DMG}"
shasum -a 256 "$DMG" "$ZIP"
