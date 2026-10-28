#!/usr/bin/env bash
# Measures the spec's three gates on the connected TV: memory, janky frames, Home handoff.
set -euo pipefail
SER=${ADB_SERIAL:?set ADB_SERIAL, e.g. ADB_SERIAL=192.168.1.50:5555}
PKG=tv.dumbtv.home
A() { adb -s "$SER" shell "$@" </dev/null | tr -d '\r'; }
fail=0
gate() { # name value limit  (pass when value <= limit)
  if python3 -I -c "import sys; sys.exit(0 if float('$2') <= float('$3') else 1)"; then
    echo "PASS $1: $2 <= $3"
  else
    echo "FAIL $1: $2 > $3"; fail=1
  fi
}

A am start -a android.intent.action.MAIN -c android.intent.category.HOME >/dev/null; sleep 5

echo "== memory"
pss=$(A dumpsys meminfo $PKG | awk '$1=="TOTAL" {print $2; exit}')
echo "PSS_KB=$pss"
gate "PSS (KB)" "${pss:-999999}" 60000

echo "== jank while moving focus"
A dumpsys gfxinfo $PKG reset >/dev/null
for _ in $(seq 1 20); do A input keyevent KEYCODE_DPAD_RIGHT; sleep 0.25; done
for _ in $(seq 1 20); do A input keyevent KEYCODE_DPAD_LEFT; sleep 0.25; done
info=$(A dumpsys gfxinfo $PKG)
echo "$info" | grep -E "Total frames rendered|Janky frames"
pct=$(echo "$info" | sed -n 's/.*Janky frames: [0-9]* (\([0-9.]*\)%).*/\1/p' | head -1)
gate "janky frames (%)" "${pct:-100}" 10

echo "== Home handoff (4 runs, system log)"
times=""
for n in 1 2 3 4; do
  # Not Settings: on Fire OS it runs inside Amazon's own launcher process, so Home from it is instant and proves nothing.
  A am start -n com.netflix.ninja/.MainActivity >/dev/null; sleep 8
  adb -s "$SER" logcat -c </dev/null; A input keyevent KEYCODE_HOME; sleep 7
  t=$(adb -s "$SER" logcat -d -v time </dev/null | python3 -I -c '
import re, sys
def sec(s):
    h, m, r = s.split(":"); return int(h) * 3600 + int(m) * 60 + float(r)
home = disp = None
for line in sys.stdin:
    m = re.search(r"(\d\d:\d\d:\d\d\.\d+)", line)
    if not m: continue
    if home is None and "START u0" in line and "category.HOME" in line and "amazon.tv.launcher" in line: home = sec(m.group(1))
    if disp is None and "Displayed tv.dumbtv.home" in line: disp = sec(m.group(1))
print(round(disp - home, 2) if home and disp else "")')
  echo "run$n: ${t:-n/a}s"; times="$times ${t:-99}"
done
mean=$(python3 -I -c "v=[float(x) for x in '$times'.split()]; print(round(sum(v)/len(v), 2))")
echo "mean=$mean"
gate "Home handoff mean (s)" "$mean" "${HANDOFF_MAX:-4.0}"

exit $fail
