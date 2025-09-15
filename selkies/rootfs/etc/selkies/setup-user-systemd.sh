#!/bin/bash

# Setup user systemd environment for appbox user
# This script ensures the user has proper access to their systemd --user instance

USER_NAME="appbox"
USER_ID=$(id -u "$USER_NAME")
XDG_RUNTIME_DIR="/run/user/$USER_ID"

# Ensure XDG_RUNTIME_DIR exists and has proper permissions
if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
    mkdir -p "$XDG_RUNTIME_DIR"
    chown "$USER_NAME:$USER_NAME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

# Set up environment for user systemd
export XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"

# D-Bus will be started by XFCE's dbus-launch, so we don't start it here
echo "D-Bus session will be managed by XFCE startup..."

# Ensure user systemd directories exist
mkdir -p "/home/$USER_NAME/.config/systemd/user"
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config"

# Ensure user systemd is properly set up
echo "Setting up user systemd for $USER_NAME..."

# Enable lingering for the user so systemd --user starts at boot
loginctl enable-linger "$USER_NAME" 2>/dev/null || true

echo "User systemd will be started within the XFCE D-Bus session..."

# PulseAudio services will be disabled after XFCE starts and systemd --user is running
echo "PulseAudio service cleanup will happen after desktop starts..."

echo "User systemd setup completed. Systemd --user will start with XFCE."
    
# Always try to refresh snap desktop integration
if [[ -d "/var/lib/snapd/desktop/applications" ]]; then
    echo "Refreshing snap desktop integration..."
    update-desktop-database /var/lib/snapd/desktop/applications/ 2>/dev/null || true
fi
