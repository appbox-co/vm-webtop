#!/bin/bash
# Re-apply Appbox backdrop when Selkies/browser resizes the X display (RandR), since xfdesktop
# can revert wallpaper after output reconfiguration.
export DISPLAY="${DISPLAY:-:0}"
WallScript=/defaults/xfce/set-desktop-wallpaper.sh
[ -f "$WallScript" ] || exit 0

for _ in $(seq 1 120); do
  xrandr -q >/dev/null 2>&1 && break
  sleep 0.5
done

sig=""
while true; do
  cur="$(xrandr 2>/dev/null | md5sum | awk '{print $1}')"
  if [ -n "$sig" ] && [ -n "$cur" ] && [ "$cur" != "$sig" ]; then
    APPBOX_WALLPAPER_SKIP_SLEEP=1 /bin/bash "$WallScript"
    xfdesktop --reload 2>/dev/null || true
  fi
  sig="$cur"
  sleep 0.5
done
