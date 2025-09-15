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

# Ensure user systemd directories exist
mkdir -p "/home/$USER_NAME/.config/systemd/user"
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config"

# Start user systemd daemon if not running
if ! systemctl --user --machine="$USER_NAME"@ status >/dev/null 2>&1; then
    echo "Starting user systemd daemon for $USER_NAME..."
    sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemd --user --daemon 2>/dev/null || true
    sleep 1
fi

# Disable user PulseAudio services since we use system services
echo "Disabling conflicting user PulseAudio services..."
sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user disable pulseaudio.service pulseaudio.socket 2>/dev/null || true
sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user mask pulseaudio.service pulseaudio.socket 2>/dev/null || true

# Test user systemd functionality
if sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user daemon-reload 2>/dev/null; then
    echo "✓ User systemd is working for $USER_NAME"
        
        # Refresh snap desktop integration
        if [[ -d "/var/lib/snapd/desktop/applications" ]]; then
            echo "Refreshing snap desktop integration..."
            update-desktop-database /var/lib/snapd/desktop/applications/ 2>/dev/null || true
        fi
else
    echo "⚠ User systemd may need additional setup for $USER_NAME"
    fi
    
    # Always try to refresh snap desktop integration
    if [[ -d "/var/lib/snapd/desktop/applications" ]]; then
        echo "Refreshing snap desktop integration..."
        update-desktop-database /var/lib/snapd/desktop/applications/ 2>/dev/null || true
fi
