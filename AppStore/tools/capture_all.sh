#!/usr/bin/env bash
# Captures App Store screenshots for both required device sizes by launching the app
# in "screenshot mode" (DEBUG launch-env hooks) and grabbing simctl screenshots.
set -uo pipefail

SP="/private/tmp/claude-501/-Users-wiredframe-Projekte-Claude-Code-Comic-Reader-iOS/9a16b6bb-f86a-4ab9-8572-055260e005b7/scratchpad"
PROJ="/Users/wiredframe/Projekte/Claude Code/Comic Reader iOS"
APP="$PROJ/build/Build/Products/Debug-iphonesimulator/ComicReader.app"
BUNDLE="de.wiredframe.comicreader"
LIB="$SP/library"
INK="$SP/Inklings.cbz"
LOG="$SP/capture.log"
: > "$LOG"

RUNTIME=$(xcrun simctl list runtimes | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]+' | tail -1)
echo "runtime=$RUNTIME" | tee -a "$LOG"

capture_device() { # typeId  label  outdir
  local TYPE="$1" LABEL="$2" OUT="$3"
  mkdir -p "$OUT"
  echo "=== $LABEL ($TYPE) ===" | tee -a "$LOG"
  xcrun simctl delete "CR-$LABEL" >/dev/null 2>&1 || true
  local UDID
  UDID=$(xcrun simctl create "CR-$LABEL" "$TYPE" "$RUNTIME")
  echo "udid=$UDID" | tee -a "$LOG"
  xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$UDID" -b >>"$LOG" 2>&1
  # Clean, App-Store-style status bar (9:41, full signal/battery).
  xcrun simctl status_bar "$UDID" override --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 >>"$LOG" 2>&1 || true
  # Let one-time first-boot system banners (e.g. "Ready for Apple Intelligence")
  # appear and auto-dismiss before we start shooting.
  echo "  settling 25s to clear first-run banners..." | tee -a "$LOG"
  sleep 25

  shot() { # name delay env...
    local name="$1" delay="$2"; shift 2
    xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl install "$UDID" "$APP" >>"$LOG" 2>&1
    env "$@" xcrun simctl launch "$UDID" "$BUNDLE" >>"$LOG" 2>&1
    sleep "$delay"
    xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >>"$LOG" 2>&1
    echo "  shot $name -> $(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" 2>/dev/null | grep pixel | tr '\n' ' ')" | tee -a "$LOG"
  }

  # Reader/settings first; the Library shot goes last, well past the banner window.
  shot 02_splash    13 SIMCTL_CHILD_SEED_COMIC_PATH="$INK" SIMCTL_CHILD_SCREENSHOT_OPEN_PAGE=3
  shot 03_panels    13 SIMCTL_CHILD_SEED_COMIC_PATH="$INK" SIMCTL_CHILD_SCREENSHOT_OPEN_PAGE=2
  shot 04_dialogue  13 SIMCTL_CHILD_SEED_COMIC_PATH="$INK" SIMCTL_CHILD_SCREENSHOT_OPEN_PAGE=4
  shot 05_settings  16 SIMCTL_CHILD_SEED_LIBRARY_DIR="$LIB" SIMCTL_CHILD_SCREENSHOT_TAB=settings
  shot 01_library   16 SIMCTL_CHILD_SEED_LIBRARY_DIR="$LIB" SIMCTL_CHILD_SCREENSHOT_TAB=library

  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}

capture_device "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"      "iphone69" "$SP/shots/iphone69"
capture_device "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB" "ipad13"   "$SP/shots/ipad13"

echo "ALL DONE" | tee -a "$LOG"
