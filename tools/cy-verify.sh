#!/usr/bin/env bash
# Gates for the CleanYourTV launcher on the connected TV: memory, janky frames, Home handoff.
set -euo pipefail
SER=${ADB_SERIAL:?set ADB_SERIAL, e.g. ADB_SERIAL=192.168.1.50:5555}
PKG=com.gathin.tvhome
HERE=$(cd "$(dirname "$0")" && pwd)
A() { adb -s "$SER" shell "$@" </dev/null | tr -d '\r'; }
fail=0
gate() { # name value limit (pass when value <= limit)
  if python3 -I -c "import sys; sys.exit(0 if float('$2') <= float('$3') else 1)"; then
    echo "PASS $1: $2 <= $3"
  else
    echo "FAIL $1: $2 > $3"; fail=1
  fi
}

A input keyevent KEYCODE_HOME; sleep 8
echo "== memory"
pss=$(A dumpsys meminfo $PKG | awk '$1=="TOTAL" {print $2; exit}')
echo "PSS_KB=$pss"
gate "PSS (KB)" "${pss:-999999}" "${PSS_MAX:-70000}"

echo "== jank while navigating"
A dumpsys gfxinfo $PKG reset >/dev/null
for _ in $(seq 1 15); do A input keyevent KEYCODE_DPAD_RIGHT; sleep 0.25; done
for _ in $(seq 1 15); do A input keyevent KEYCODE_DPAD_LEFT; sleep 0.25; done
for _ in $(seq 1 6); do A input keyevent KEYCODE_DPAD_DOWN; sleep 0.3; done
for _ in $(seq 1 6); do A input keyevent KEYCODE_DPAD_UP; sleep 0.3; done
info=$(A dumpsys gfxinfo $PKG)
echo "$info" | grep -E "Total frames rendered|Janky frames"
pct=$(echo "$info" | sed -n 's/.*Janky frames: [0-9]* (\([0-9.]*\)%).*/\1/p' | head -1)
gate "janky frames (%)" "${pct:-100}" 10

echo "== Home handoff (4 runs, system log)"
times=""
for n in 1 2 3 4; do
  A am start -n com.netflix.ninja/.MainActivity >/dev/null; sleep 9
  adb -s "$SER" logcat -c </dev/null; A input keyevent KEYCODE_HOME; sleep 8
  line=$(adb -s "$SER" logcat -d -v time </dev/null | python3 -I "$HERE/handoff-time.py" $PKG)
  t=${line%%s*}
  echo "run$n: $line"; times="$times ${t:-99}"
done
mean=$(python3 -I -c "v=[float(x) for x in '$times'.split() if x.replace('.','',1).isdigit()]; print(round(sum(v)/len(v), 2) if v else 99)")
echo "mean=$mean"
gate "Home handoff mean (s)" "$mean" "${HANDOFF_MAX:-3.3}"
exit $fail
