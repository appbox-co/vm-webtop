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

# Test user systemd functionality
if sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user daemon-reload 2>/dev/null; then
    echo "✓ User systemd is working for $USER_NAME"
else
    echo "⚠ User systemd may need additional setup for $USER_NAME"
fi
