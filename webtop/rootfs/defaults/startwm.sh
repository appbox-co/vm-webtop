#!/bin/bash
# GNOME Flashback (Metacity) for Selkies / Xvfb.
# Ubuntu 26+ ships org.gnome.Shell@user.service with AssertEnvironment=XDG_SESSION_TYPE=wayland,
# so GNOME Shell does not start on X11; Flashback provides a full GNOME-style desktop on X.

DISABLE_ZINK="${DISABLE_ZINK:-false}"
if [ "${DISABLE_ZINK}" != "true" ] && command -v nvidia-smi >/dev/null 2>&1 && [ -r "/dev/dri/renderD128" ]; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
fi

export GDK_BACKEND=x11
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP="GNOME-Flashback:GNOME"
export XDG_SESSION_DESKTOP="gnome-flashback-metacity"

Wall=/defaults/gnome/wallpapers/appbox.svg
if [ -f "$Wall" ] && command -v gsettings >/dev/null 2>&1; then
  uri="file://${Wall}"
  gsettings set org.gnome.desktop.background picture-uri "$uri" 2>/dev/null || true
  gsettings set org.gnome.desktop.background picture-uri-dark "$uri" 2>/dev/null || true
  gsettings set org.gnome.desktop.background picture-options scaled 2>/dev/null || true
  gsettings set org.gnome.desktop.interface gtk-theme Yaru 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme Yaru 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
fi

exec /usr/bin/gnome-session --session=gnome-flashback-metacity
