#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Qelvora.xcodeproj"
SCHEME="Qelvora"
CONFIGURATION="Release"
DERIVED_DATA="/tmp/qelvora-dmg-derived"
STAGING_DIR="/tmp/qelvora-dmg-staging"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Qelvora.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Qelvora/Resources/Info.plist")"
DMG_PATH="$DIST_DIR/Qelvora-$VERSION.dmg"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-923MBLC4X4}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: Cyril Dieumegard (923MBLC4X4)}"

echo "Building Qelvora $VERSION..."
echo "Signing identity: $CODE_SIGN_IDENTITY"

rm -rf "$DERIVED_DATA" "$STAGING_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but Qelvora.app was not found at: $APP_PATH" >&2
  exit 1
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/Qelvora.app"
ln -s /Applications "$STAGING_DIR/Applications"

codesign --verify --deep --strict "$STAGING_DIR/Qelvora.app"

echo "Creating $DMG_PATH..."
rm -f "$DMG_PATH"

hdiutil create \
  -volname "Qelvora" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"

echo "DMG ready: $DMG_PATH"
