#!/usr/bin/env bash
# Emulator smoke test (CI only, advisory). It proves three things on a real Android runtime:
#   1. the release APK installs and the app starts without crashing;
#   2. an OS alarm armed through the app's own scheduler code fires while the app is in the
#      background AND after its process has been killed;
#   3. that alarm revives the background service (the exact failure behind "scheduling does not work").
# No SMS is sent and no call is made. Usage: tools/emulator_smoke.sh path/to/app.apk
set -u
APK="${1:?apk path}"
PKG=com.smsandcall.app
RECEIVER="$PKG/com.amirali.smsbridge.WakeReceiver"
fail=0

check() { # check "description" command...
  local what="$1"; shift
  if "$@"; then echo "PASS  $what"; else echo "FAIL  $what"; fail=1; fi
}

adb wait-for-device
adb root >/dev/null 2>&1 || true
adb wait-for-device
sleep 3

echo "== install =="
adb install -r -g "$APK"
adb shell settings put global window_animation_scale 0 >/dev/null 2>&1 || true

echo "== 1. launch =="
adb logcat -c
adb shell am start -n "$PKG/.MainActivity" >/dev/null
sleep 25
check "app process is alive after launch" adb shell pidof "$PKG"
if adb logcat -d | grep -E "FATAL EXCEPTION|Process: $PKG.*(died|crash)" >/dev/null; then
  echo "FAIL  crash found in logcat"; adb logcat -d | grep -B2 -A12 "FATAL EXCEPTION" | head -60; fail=1
else
  echo "PASS  no crash in logcat"
fi

echo "== 2. alarm survives process death =="
adb shell input keyevent KEYCODE_HOME
sleep 2
adb shell am broadcast -n "$RECEIVER" -a com.amirali.smsbridge.ARM_TEST \
  --el delayMs 25000 --es slot smoke --es reason smoketest >/dev/null
sleep 2
PID=$(adb shell pidof "$PKG" | tr -d '\r')
if [ -n "$PID" ]; then adb shell kill -9 $PID; fi
sleep 3
check "process is really gone" bash -c "! adb shell pidof $PKG | grep -q '[0-9]'"

echo "waiting for the alarm (about 30 s)..."
sleep 40

PREFS=$(adb shell "cat /data/data/$PKG/shared_prefs/smsbridge_wake.xml" 2>/dev/null | tr -d '\r')
echo "$PREFS"
check "alarm fired with the right reason" bash -c "echo '$PREFS' | grep -q 'smoketest'"
check "receiver reported that it started the service" \
  bash -c "echo '$PREFS' | grep -q 'last_started_service\" value=\"true\"'"
check "background service is running again" \
  bash -c "adb shell dumpsys activity services $PKG | grep -q BackgroundService"
if adb logcat -d | grep -E "ForegroundServiceStartNotAllowedException|MissingForegroundServiceType" >/dev/null; then
  echo "FAIL  Android refused to start the foreground service from the alarm"; fail=1
else
  echo "PASS  no foreground-service start restriction hit"
fi

adb logcat -d | tail -80 > smoke-logcat-tail.txt || true
exit $fail
