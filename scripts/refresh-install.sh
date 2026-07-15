#!/usr/bin/env bash
#
# refresh-install.sh — rebuild Paper Comic Reader and (re)install it on the paired
# iPhone over the network, renewing the free-account 7-day signing profile before
# it expires.
#
# Meant to run unattended from a launchd LaunchAgent (see
# de.wiredframe.comicreader.refresh.plist), but is also safe to run by hand to test:
#
#     bash scripts/refresh-install.sh
#
# Config lives in scripts/refresh.env (gitignored). Copy refresh.env.example to
# refresh.env and fill in DEVICE_ID and TEAM_ID.
#
set -euo pipefail

# launchd runs with a minimal PATH — make Homebrew (xcodegen) and the toolchain
# reachable regardless of who invokes us.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

cd "$(dirname "$0")/.."

# ---- config -----------------------------------------------------------------
ENV_FILE="scripts/refresh.env"
# shellcheck source=/dev/null
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

SCHEME="${SCHEME:-ComicReader}"
CONFIG="${CONFIG:-Debug}"
DEVICE_ID="${DEVICE_ID:?Set DEVICE_ID in scripts/refresh.env — see: xcrun devicectl list devices}"
TEAM_ID="${TEAM_ID:?Set TEAM_ID in scripts/refresh.env — your Apple Developer team id}"
DERIVED="build/refresh-dd"
LOG_DIR="build/refresh-logs"
NOTIFY_ON_SUCCESS="${NOTIFY_ON_SUCCESS:-0}"

mkdir -p "$LOG_DIR"

notify() { # notify "title" "message"
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

fail() {
  echo "✗ $1" >&2
  notify "Comic Reader refresh FAILED" "$1"
  exit 1
}

echo "▸ $(date '+%Y-%m-%d %H:%M:%S') refresh start (device=$DEVICE_ID, team=$TEAM_ID)"

# Keep the Xcode project in sync with project.yml.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null 2>&1 || fail "xcodegen generate failed"
fi

echo "▸ Building ($CONFIG) for device…"
if ! xcodebuild \
  -project ComicReader.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build >"$LOG_DIR/build.log" 2>&1; then
  tail -25 "$LOG_DIR/build.log" >&2
  fail "xcodebuild build failed (see $LOG_DIR/build.log)"
fi

APP="$(/usr/bin/find "$DERIVED/Build/Products/$CONFIG-iphoneos" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
[ -n "$APP" ] && [ -d "$APP" ] || fail "Built .app not found under $DERIVED"

echo "▸ Installing over network → $APP"
if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >"$LOG_DIR/install.log" 2>&1; then
  tail -25 "$LOG_DIR/install.log" >&2
  fail "devicectl install failed — iPhone offline / not on Wi-Fi / not charging?"
fi

echo "✓ $(date '+%Y-%m-%d %H:%M:%S') installed OK — 7-day clock reset"
[ "$NOTIFY_ON_SUCCESS" = "1" ] && notify "Comic Reader aktualisiert" "Neu signiert & installiert — 7-Tage-Uhr zurückgesetzt."
exit 0
