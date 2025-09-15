#!/bin/bash

# Enable Nvidia GPU support if detected
if which nvidia-smi; then
  export LIBGL_KOPPER_DRI2=1
  export MESA_LOADER_DRIVER_OVERRIDE=zink
  export GALLIUM_DRIVER=zink
fi

# Default settings
if [ ! -d "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml ]; then
  mkdir -p "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml
  cp /defaults/xfce/* "${HOME}"/.config/xfce4/xfconf/xfce-perchannel-xml/
fi

# Start DE with proper systemd integration
(
  # Start D-Bus session and XFCE
  eval $(dbus-launch --sh-syntax)
  export DBUS_SESSION_BUS_ADDRESS
  
  # Start systemd user manager within this D-Bus session
  if ! systemctl --user status >/dev/null 2>&1; then
    echo "Starting systemd --user within XFCE D-Bus session..."
    systemd --user --daemon &
    sleep 1
  fi
  
  # Update systemd environment with D-Bus info
  systemctl --user import-environment DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
  
  # Start XFCE session
  exec /usr/bin/xfce4-session
) > /dev/null 2>&1 