#!/bin/bash

# Enable Nvidia GPU support if detected
if which nvidia-smi; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

XFCONF_DIR="${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"
LAYOUT_REV="$(tr -d '[:space:]' </defaults/xfce/.xfce-layout-revision 2>/dev/null || echo 1)"
CUR_REV="$(tr -d '[:space:]' <"${HOME}/.config/xfce4/.xfce-layout-revision" 2>/dev/null || echo 0)"

if [ ! -d "$XFCONF_DIR" ]; then
  mkdir -p "$XFCONF_DIR"
  for f in /defaults/xfce/*.xml; do
    [ -f "$f" ] || continue
    cp "$f" "$XFCONF_DIR/"
  done
fi

if [ "$CUR_REV" != "$LAYOUT_REV" ]; then
  mkdir -p "$XFCONF_DIR"
  if [ -f /defaults/xfce/xfce4-panel.xml ]; then
    cp /defaults/xfce/xfce4-panel.xml "$XFCONF_DIR/xfce4-panel.xml"
  fi
  if [ -d /defaults/xfce/panel ]; then
    mkdir -p "${HOME}/.local/share/xfce4/panel"
    shopt -s nullglob
    for d in "${HOME}/.local/share/xfce4/panel"/launcher-*; do
      [ -d "$d" ] && rm -rf "$d"
    done
    shopt -u nullglob
    for d in /defaults/xfce/panel/launcher-*; do
      [ -d "$d" ] || continue
      cp -a "$d" "${HOME}/.local/share/xfce4/panel/"
    done
  fi
  rm -f "${HOME}/.config/xfce4/panel/docklike-"*.rc 2>/dev/null || true
  echo "$LAYOUT_REV" > "${HOME}/.config/xfce4/.xfce-layout-revision"
fi

# Start DE
# Use the existing D-Bus session from systemd --user
if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

# Start XFCE without creating a new D-Bus session
exec /usr/bin/xfce4-session 