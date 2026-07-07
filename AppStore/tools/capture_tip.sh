#!/usr/bin/env bash
set -uo pipefail
SP="/private/tmp/claude-501/-Users-wiredframe-Projekte-Claude-Code-Comic-Reader-iOS/9a16b6bb-f86a-4ab9-8572-055260e005b7/scratchpad"
PROJ="/Users/wiredframe/Projekte/Claude Code/Comic Reader iOS"
APP="$PROJ/build/Build/Products/Debug-iphonesimulator/ComicReader.app"
BUNDLE="de.wiredframe.comicreader"; LIB="$SP/library"
OUT="$SP/shots/iphone69"; mkdir -p "$OUT"
LOG="$SP/capture_tip.log"; : > "$LOG"
RT=$(xcrun simctl list runtimes | grep -oE 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]+' | tail -1)
xcrun simctl delete "CR-tip" >/dev/null 2>&1 || true
UDID=$(xcrun simctl create "CR-tip" "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max" "$RT")
echo "udid=$UDID rt=$RT" >>"$LOG"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >>"$LOG" 2>&1
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >>"$LOG" 2>&1 || true
sleep 25
xcrun simctl install "$UDID" "$APP" >>"$LOG" 2>&1
env SIMCTL_CHILD_SEED_LIBRARY_DIR="$LIB" SIMCTL_CHILD_SCREENSHOT_TIPS=1 xcrun simctl launch "$UDID" "$BUNDLE" >>"$LOG" 2>&1
sleep 16
xcrun simctl io "$UDID" screenshot "$OUT/06_tipjar.png" >>"$LOG" 2>&1
echo "shot -> $(sips -g pixelWidth -g pixelHeight "$OUT/06_tipjar.png" 2>/dev/null | grep pixel | tr '\n' ' ')" | tee -a "$LOG"
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
echo "DONE" | tee -a "$LOG"
