#!/usr/bin/env bash
# Fire TV debloat: backup | apply <tier...> | revert [backup_dir] | status
# Only ever uses `pm disable-user` (reversible); nothing is uninstalled.
set -u
cd "$(dirname "$0")"
IP="${FIRETV_IP:?set FIRETV_IP to the TV address, e.g. FIRETV_IP=192.168.1.50}:5555"
sh() { adb -s "$IP" shell "$@" </dev/null | tr -d '\r'; }
adb connect "$IP" >/dev/null 2>&1
[ "$(adb -s "$IP" get-state 2>&1)" = device ] || { echo "Fire TV not reachable/authorized at $IP"; exit 1; }
ANIM="window_animation_scale transition_animation_scale animator_duration_scale"

disabled_now() { sh pm list packages -d | sed 's/package://' | sort; }
latest_backup() { ls -d backups/[0-9]*/ 2>/dev/null | tail -1; }   # dated folders only (backups/dumbtv-conf sorts last)

case "${1:-}" in
backup)
  d="backups/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$d"
  sh pm list packages -f   > "$d/packages_all.txt"
  disabled_now             > "$d/disabled_before.txt"
  for k in $ANIM; do echo "$k=$(sh settings get global $k)"; done > "$d/anim_before.txt"
  for ns in global secure system; do sh settings list $ns > "$d/settings_$ns.txt"; done
  sh getprop > "$d/getprop.txt"
  echo "backup saved: $d ($(wc -l < "$d/disabled_before.txt") already disabled)"
  ;;
apply)
  shift; b="$(latest_backup)"; [ -n "$b" ] || { echo "run ./fire.sh backup first"; exit 1; }
  for tier in "$@"; do
    if [ "$tier" = anim ]; then
      for k in $ANIM; do sh settings put global $k 0.5; done; echo "animations -> 0.5x"; continue
    fi
    [ -f "tiers/$tier.txt" ] || { echo "no such tier: $tier"; continue; }
    while read -r pkg _; do
      case "$pkg" in ''|\#*) continue;; esac
      grep -q "=$pkg\$" "$b/packages_all.txt" || { echo "skip (not installed): $pkg"; continue; }
      out="$(sh pm disable-user --user 0 "$pkg" 2>&1)"; echo "$pkg: $out"
    done < "tiers/$tier.txt"
  done
  ;;
revert)
  b="${2:-$(latest_backup)}"; [ -d "$b" ] || { echo "no backup dir"; exit 1; }
  # re-enable everything disabled now that wasn't disabled in the backup
  comm -13 "$b/disabled_before.txt" <(disabled_now) | while read -r pkg; do
    echo "enable $pkg: $(sh pm enable "$pkg" 2>&1)"
  done
  while IFS== read -r k v; do
    if [ "$v" = null ]; then sh settings delete global "$k" >/dev/null; else sh settings put global "$k" "$v"; fi
  done < "$b/anim_before.txt"
  for k in amz_limit_ad_tracking non_amz_limit_ad_tracking; do
    v="$(grep "^$k=" "$b/settings_secure.txt" | cut -d= -f2)"; [ -n "$v" ] && sh settings put secure "$k" "$v"
  done
  echo "reverted to $b. Reboot the TV for a clean state: adb -s $IP reboot"
  ;;
launcher-on)
  # Install Projectivy and enable its accessibility service (it intercepts the Home button).
  # Amazon's launcher stays installed and untouched. Needs: Projectivy > Settings > General > "Override current launcher".
  [ -f apk/projectivy.apk ] || { echo "apk/projectivy.apk missing"; exit 1; }
  adb -s "$IP" install -r apk/projectivy.apk </dev/null
  svc=com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService
  cur="$(sh settings get secure enabled_accessibility_services)"
  case "$cur" in *"$svc"*) ;; null|"") sh settings put secure enabled_accessibility_services "$svc";; *) sh settings put secure enabled_accessibility_services "$cur:$svc";; esac
  sh settings put secure accessibility_enabled 1
  echo "a11y now: $(sh settings get secure enabled_accessibility_services)"
  ;;
launcher-off)
  # Remove the accessibility service entry, restore the previous value, uninstall Projectivy.
  svc=com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService
  cur="$(sh settings get secure enabled_accessibility_services)"
  new="$(printf '%s' "$cur" | tr ':' '\n' | grep -vF "$svc" | paste -sd: -)"
  if [ -z "$new" ]; then sh settings delete secure enabled_accessibility_services; sh settings put secure accessibility_enabled 0
  else sh settings put secure enabled_accessibility_services "$new"; fi
  sh pm uninstall --user 0 com.spocky.projengmenu
  sh input keyevent KEYCODE_HOME
  echo "Projectivy removed; Amazon home restored. a11y now: $(sh settings get secure enabled_accessibility_services)"
  ;;
status)
  sh "dumpsys meminfo | grep -E 'Total RAM|Free RAM|ZRAM|status'"; sh "dumpsys meminfo | head -8 | tail -6"
  echo "disabled packages: $(disabled_now | wc -l)"
  ;;
*) echo "usage: $0 backup | apply <tier1|tier2|tier3|anim>... | launcher-on | launcher-off | revert [dir] | status"; exit 1;;
esac
