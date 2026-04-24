#!/bin/bash

# Enable Nvidia/Zink overrides only when explicitly allowed and usable.
# This avoids unstable GL paths on software-only hosts.
DISABLE_ZINK="${DISABLE_ZINK:-false}"
if [ "${DISABLE_ZINK}" != "true" ] && command -v nvidia-smi >/dev/null 2>&1 && [ -r "/dev/dri/renderD128" ]; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

# Default settings (copy *.xml only; subdirs like panel/ are seeded below)
if [ ! -d "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml ]; then
  mkdir -p "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml
  for f in /defaults/xfce/*.xml; do
    [ -f "$f" ] || continue
    cp "$f" "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/
  done
fi
# Xfce launcher plugins read ~/.local/share/xfce4/panel/launcher-N/*.desktop
if [ -d /defaults/xfce/panel ]; then
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