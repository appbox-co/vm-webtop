#!/bin/bash
# Apply centered Appbox wallpaper to every backdrop monitor XFCE knows about (selkies renames primary).
export DISPLAY="${DISPLAY:-:0}"
Wall=/defaults/xfce/wallpapers/appbox.svg
[ -f "$Wall" ] || exit 0
if [ "${APPBOX_WALLPAPER_SKIP_SLEEP:-}" != 1 ]; then
  sleep 1.5
fi

apply_one () {
  local base="$1"
  # Solid fill: appbox.co dark hsl(228 18% 7%) → #0e0f15 (XFCE 4.20+: rgba1 = doubles 0..1)
  xfconf-query -c xfce4-desktop -p "$base/color-style" -s 0 -t int 2>/dev/null || \
    xfconf-query -c xfce4-desktop -p "$base/color-style" -n -t int -s 0 -a
  xfconf-query -c xfce4-desktop -p "$base/rgba1" -r -R 2>/dev/null || true
  xfconf-query -c xfce4-desktop -p "$base/rgba1" -n -t double -s 0.054902 -t double -s 0.058824 -t double -s 0.082353 -t double -s 1.0 -a
  xfconf-query -c xfce4-desktop -p "$base/last-image" -s "$Wall" -t string 2>/dev/null || \
    xfconf-query -c xfce4-desktop -p "$base/last-image" -n -t string -s "$Wall" -a
  xfconf-query -c xfce4-desktop -p "$base/image-style" -s 1 -t int 2>/dev/null || \
    xfconf-query -c xfce4-desktop -p "$base/image-style" -n -t int -s 1 -a
  xfconf-query -c xfce4-desktop -p "$base/image-show" -s true -t bool 2>/dev/null || \
    xfconf-query -c xfce4-desktop -p "$base/image-show" -n -t bool -s true -a
}

mons=$(xfconf-query -c xfce4-desktop -lv 2>/dev/null | sed -n 's|^/backdrop/screen0/\(monitor[^/]*\)/.*|\1|p' | sort -u)
xr=$(xrandr 2>/dev/null | awk '/ connected /{print $1; exit}')
[ -n "$xr" ] && mons=$(printf '%s\n' $mons "monitor${xr}" | sort -u)
# Always include selkies/xrandr names so reconfigure does not miss a branch xfdesktop still uses.
mons=$(printf '%s\n' $mons monitorscreen monitorselkies-primary | sort -u)

for m in $mons; do
  [ -n "$m" ] || continue
  apply_one "/backdrop/screen0/${m}/workspace0"
done
