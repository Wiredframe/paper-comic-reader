#!/usr/bin/env bash
#
# build-ipa.sh — build an UNSIGNED .ipa of Paper Comic Reader for sideloading.
#
# The .ipa is intentionally unsigned: sideload tools (AltStore, Sideloadly, TrollStore)
# re-sign it with the user's own Apple ID at install time. This is NOT an App Store
# build — there is no signing, no provisioning, and no upload here.
#
# Output: build/PaperComicReader-<version>.ipa
#
set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="ComicReader"
CONFIG="Release"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/ComicReader.xcarchive"
STAGE="$BUILD_DIR/ipa"
APP_NAME="ComicReader.app"

# Keep the project in sync with project.yml before archiving.
if command -v xcodegen >/dev/null 2>&1; then
  echo "▸ xcodegen generate"
  xcodegen generate
fi

rm -rf "$ARCHIVE" "$STAGE"
mkdir -p "$STAGE/Payload"

echo "▸ Archiving (unsigned)…"
xcodebuild \
  -project ComicReader.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

APP="$ARCHIVE/Products/Applications/$APP_NAME"
[ -d "$APP" ] || { echo "✗ Built app not found at $APP" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null || echo 0.0.0)"
OUT="$BUILD_DIR/PaperComicReader-$VERSION.ipa"

echo "▸ Packaging $OUT"
cp -R "$APP" "$STAGE/Payload/"
rm -f "$OUT"
( cd "$STAGE" && zip -qry "../$(basename "$OUT")" Payload )

echo "✓ Wrote $OUT"
