#!/bin/bash
# Boots a simulator, installs the app, and takes screenshots of key screens.
# usage: ci/simulator-test.sh <device name> <app path> <out dir> [landscape]
set -u
DEVICE="$1"; APP="$2"; OUT="$3"; LAND="${4:-}"
BUNDLE=com.ashalnidamhifz.quran
mkdir -p "$OUT"
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
want=sys.argv[1]
devs=[(rt,x) for rt,l in sorted(d.items(), reverse=True) if 'iOS' in rt for x in l]
c=[x for rt,x in devs if x['name']==want] or [x for rt,x in devs if x['name'].startswith(want)]
print(c[0]['udid'] if c else '')
print(c[0]['name'] if c else '', file=sys.stderr)" "$DEVICE")
[ -n "$UDID" ] || { echo "no simulator named $DEVICE"; xcrun simctl list devices available; exit 1; }
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$UDID" || true
sleep 5
if [ -n "$LAND" ]; then
  osascript -e 'tell application "Simulator" to activate' -e 'delay 1' \
    -e 'tell application "System Events" to key code 123 using command down' || echo "rotate failed (non-fatal)"
  sleep 3
fi
xcrun simctl install "$UDID" "$APP"
shot() { xcrun simctl io "$UDID" screenshot "$OUT/$1.png" && echo "shot $1"; }

# 1) first launch: welcome screen
xcrun simctl launch "$UDID" "$BUNDLE"; sleep 10; shot 01-first-launch
xcrun simctl terminate "$UDID" "$BUNDLE"

# 2) a user in the middle of the plan (state preloaded by the test hook)
xcrun simctl uninstall "$UDID" "$BUNDLE"; xcrun simctl install "$UDID" "$APP"
xcrun simctl spawn "$UDID" defaults write "$BUNDLE" ui_test_state -string "$(cat ci/test-state.json)"
xcrun simctl launch "$UDID" "$BUNDLE"; sleep 10; shot 02-home
xcrun simctl terminate "$UDID" "$BUNDLE"

# 3) mushaf opened from the home-screen quick action path
xcrun simctl spawn "$UDID" defaults write "$BUNDLE" pending_shortcut -string mushaf
xcrun simctl launch "$UDID" "$BUNDLE"; sleep 15; shot 03-shortcut-mushaf
xcrun simctl terminate "$UDID" "$BUNDLE"

# 4) fixed screens opened by the test hook
for act in mushaf hafs tafsir dark-tafsir; do
  xcrun simctl spawn "$UDID" defaults write "$BUNDLE" ui_test_action -string "$act"
  xcrun simctl launch "$UDID" "$BUNDLE"; sleep 14; shot "04-$act"
  xcrun simctl terminate "$UDID" "$BUNDLE"
done
xcrun simctl spawn "$UDID" defaults delete "$BUNDLE" ui_test_action || true

# crash check
if xcrun simctl spawn "$UDID" log show --last 5m --predicate "process == 'App' AND eventMessage CONTAINS[c] 'fatal'" 2>/dev/null | grep -qi fatal; then
  echo "::warning::fatal messages found in the app log"
fi
ls -la "$OUT"
