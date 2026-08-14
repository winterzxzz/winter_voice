#!/bin/bash
# Builds a Release WinterVoice.app and packages it as build/WinterVoice.dmg
# with a drag-to-Applications layout. The app is ad-hoc signed; distribution
# signing and notarization are roadmap work (see docs/DEVELOPMENT.md).
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="build/DerivedData-Release"
DMG_PATH="build/WinterVoice.dmg"
VOLUME_NAME="WinterVoice"

# Build only the app target: the shared scheme also builds WinterVoiceTests,
# which cannot compile against a Release (non-testable) WinterVoice module.
xcodebuild \
  -project WinterVoice.xcodeproj \
  -target WinterVoice \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/$DERIVED_DATA/Build/Products" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/WinterVoice.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app bundle at $APP_PATH" >&2
  exit 1
fi

# Strip any test bundles a previous scheme-based build embedded as plug-ins;
# they are not shippable and break deep signing.
rm -rf "$APP_PATH/Contents/PlugIns/"*.xctest

codesign --force --deep --options runtime --sign - "$APP_PATH"

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "Created $DMG_PATH"
