#!/bin/bash
# Builds a Release WinterVoice.app and packages it as build/WinterVoice.dmg
# with a drag-to-Applications layout. The app is ad-hoc signed; distribution
# signing and notarization are roadmap work (see docs/DEVELOPMENT.md).
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED_DATA="build/DerivedData-Release"
DMG_PATH="build/WinterVoice.dmg"
VOLUME_NAME="WinterVoice"

# Start from a clean products dir: an earlier scheme-based build embeds
# XCTest frameworks and the test bundle into the app, which must not ship.
rm -rf "$DERIVED_DATA/Build/Products"

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

# Ad-hoc sign nested code first, then the app. Hardened runtime is left off:
# its library validation refuses ad-hoc-signed frameworks (whisper.framework),
# which makes the app fail at launch with a dyld Team ID mismatch.
find "$APP_PATH/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) 2>/dev/null \
  | while IFS= read -r nested; do
      codesign --force --sign - "$nested"
    done
codesign --force --sign - "$APP_PATH"

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
