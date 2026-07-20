#!/usr/bin/env bash
#
# build-appstore.sh — archive + export a SIGNED App Store .ipa of Paper Comic Reader,
# ready to upload with Transporter or Xcode ▸ Organizer. This is the App Store path;
# build-ipa.sh is the separate UNSIGNED sideload path.
#
# Signing is automatic: Xcode manages the Apple Distribution certificate and the App
# Store provisioning profiles (the app AND the ComicThumbnail extension) through
# -allowProvisioningUpdates, so the Apple ID must be signed in under
# Xcode ▸ Settings ▸ Accounts first (see the signing note in the project memory).
#
# WHY the export forces /usr/bin to the front of PATH: Xcode's IPA-packaging step shells
# out to rsync. A Homebrew rsync 3.x on PATH shadows Apple's /usr/bin/rsync (openrsync);
# the Homebrew build rejects Apple's `--extended-attributes` flag and the whole export
# dies with an opaque "error: exportArchive Copy failed". Putting Apple's rsync first
# fixes it. (Diagnose it via the CreateIPA step in the .xcdistributionlogs.)
#
# Output: build/appstore/PaperComicReader-<version>-appstore.ipa   (NOT uploaded — you do that)
#
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="ComicReader"
TEAM="${TEAM:-7RN999S858}"
OUT="build/appstore"
ARCHIVE="$OUT/ComicReader.xcarchive"
EXPORT="$OUT/export"

if command -v xcodegen >/dev/null 2>&1; then
  echo "▸ xcodegen generate"
  xcodegen generate
fi

rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p "$OUT"

echo "▸ Archiving (Release, automatic Distribution signing)…"
xcodebuild \
  -project ComicReader.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM" \
  -allowProvisioningUpdates \
  archive

cat > "$OUT/exportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>        <string>app-store-connect</string>
	<key>teamID</key>        <string>$TEAM</string>
	<key>signingStyle</key>  <string>automatic</string>
	<key>uploadSymbols</key> <true/>
	<key>destination</key>   <string>export</string>
</dict>
</plist>
PLIST

echo "▸ Exporting App Store .ipa (Apple rsync forced ahead of Homebrew in PATH)…"
PATH="/usr/bin:$PATH" xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/exportOptions.plist" \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates

APP="$ARCHIVE/Products/Applications/ComicReader.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null || echo 0.0.0)"
OUT_IPA="$OUT/PaperComicReader-$VERSION-appstore.ipa"
cp "$EXPORT/ComicReader.ipa" "$OUT_IPA"

echo "✓ Wrote $OUT_IPA"
echo "  Upload with Transporter (drag it in) or Xcode ▸ Organizer. This script does not upload."
