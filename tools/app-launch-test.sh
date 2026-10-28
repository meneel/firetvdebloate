#!/usr/bin/env bash
# Cold-launch time per app (am start -W) and Home handoff time. Needs ADB_SERIAL. Writes no settings.
# usage: ADB_SERIAL=ip:5555 tools/app-launch-test.sh pkg [pkg...]
a(){ adb -s "$ADB_SERIAL" "$@"; }
for pkg in "$@"; do
  comp=$(a shell cmd package resolve-activity --brief -c android.intent.category.LEANBACK_LAUNCHER "$pkg" | tail -1 | tr -d '\r')
  for run in 1 2; do
    a shell input keyevent KEYCODE_HOME; sleep 3
    a shell am force-stop "$pkg"; sleep 2
    free=$(a shell grep MemAvailable /proc/meminfo | awk '{print int($2/1024)}')
    t=$(a shell am start -W -n "$comp" | tr -d '\r' | awk '/TotalTime/{print $2}')
    sleep 6
    t0=$(python3 -c 'import time;print(time.time())')
    a shell input keyevent KEYCODE_HOME
    until a shell dumpsys window | grep mCurrentFocus | grep -q com.gathin.tvhome; do
      [ "$(python3 -c "import time;print(int(time.time()-$t0))")" -gt 20 ] && break
    done
    h=$(python3 -c "import time;print(round(time.time()-$t0,1))")
    echo "$pkg run$run avail_before=${free}MB cold_launch=${t}ms home_handoff~${h}s(poll-limited)"
  done
  a shell am force-stop "$pkg"
done
