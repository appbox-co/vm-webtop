#!/bin/bash

# Enable Nvidia GPU support if detected
if which nvidia-smi; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

XfceRevSrc=/defaults/xfce/.vm-images-xfce-revision
UserRev="${HOME}/.config/xfce4/.vm-images-xfce-revision"
XfceConfDir="${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
need_sync=false
if [ ! -d "$XfceConfDir" ]; then
  need_sync=true
elif [ -f "$XfceRevSrc" ]; then
  want=$(tr -d ' \n\r\t' < "$XfceRevSrc" 2>/dev/null || echo "")
  got=$(tr -d ' \n\r\t' < "$UserRev" 2>/dev/null || echo "")
  [ -n "$want" ] && [ "$want" != "$got" ] && need_sync=true
fi

if [ "$need_sync" = true ]; then
  mkdir -p "$XfceConfDir"
  for f in /defaults/xfce/*.xml; do
    [ -f "$f" ] || continue
    cp "$f" "$XfceConfDir/"
  done
  if [ -d /defaults/xfce/panel ]; then
    mkdir -p "${HOME}/.local/share/xfce4/panel"
    for d in /defaults/xfce/panel/launcher-*; do
      [ -d "$d" ] || continue
      base=$(basename "$d")
      rm -rf "${HOME}/.local/share/xfce4/panel/${base}"
      cp -a "$d" "${HOME}/.local/share/xfce4/panel/"
    done
  fi
  if [ -f "$XfceRevSrc" ]; then
    mkdir -p "${HOME}/.config/xfce4"
    cp "$XfceRevSrc" "$UserRev"
  fi
elif [ -d /defaults/xfce/panel ]; then
  mkdir -p "${HOME}/.local/share/xfce4/panel"
  for d in /defaults/xfce/panel/launcher-*; do
    [ -d "$d" ] || continue
    base=$(basename "$d")
    if [ ! -d "${HOME}/.local/share/xfce4/panel/${base}" ]; then
      cp -a "$d" "${HOME}/.local/share/xfce4/panel/"
    fi
  done
fi

# Start DE
# Use the existing D-Bus session from systemd --user
if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

# Start XFCE without creating a new D-Bus session
exec /usr/bin/xfce4-session
