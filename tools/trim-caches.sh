#!/usr/bin/env bash
# Clears every app's cache on the TV (pm trim-caches). Caches rebuild themselves; nothing else is touched.
# Needs FIRETV_IP. Skips quietly when the TV is unreachable or an app other than Home is on screen.
# usage: FIRETV_IP=192.168.0.x tools/trim-caches.sh
set -u
: "${FIRETV_IP:?set FIRETV_IP}"
S="$FIRETV_IP:5555"
a(){ adb -s "$S" "$@"; }
log(){ echo "$(date '+%F %T') $*"; }
adb connect "$S" >/dev/null 2>&1
a get-state >/dev/null 2>&1 || { log "TV not reachable, skipped"; exit 0; }
focus=$(a shell dumpsys window | grep mCurrentFocus | head -1)
case "$focus" in
  *com.gathin.tvhome*|*com.amazon.tv.launcher*|*"=null"*) ;;
  *) log "an app is on screen, skipped: $focus"; exit 0 ;;
esac
before=$(a shell df -k /data | tail -1 | awk '{print $4}')
a shell pm trim-caches 4000000000 >/dev/null 2>&1
sleep 5
after=$(a shell df -k /data | tail -1 | awk '{print $4}')
log "trimmed caches: free space $((before/1024)) MB -> $((after/1024)) MB"
