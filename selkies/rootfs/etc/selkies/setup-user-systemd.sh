#!/bin/bash

# Simple setup script - just ensure directories exist
# Let PAM and systemd handle the session properly

USER_NAME="appbox"
USER_ID=$(id -u "$USER_NAME")
XDG_RUNTIME_DIR="/run/user/$USER_ID"

echo "Preparing user environment..."

# Ensure user config directories exist
mkdir -p "/home/$USER_NAME/.config/systemd/user" 2>/dev/null || true
chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config" 2>/dev/null || true

# Create app directories if XDG_RUNTIME_DIR exists
if [[ -d "$XDG_RUNTIME_DIR" ]]; then
    mkdir -p "$XDG_RUNTIME_DIR"/{dconf,doc} 2>/dev/null || true
fi

# Refresh snap desktop integration
if [[ -d "/var/lib/snapd/desktop/applications" ]]; then
    echo "Refreshing snap desktop integration..."
    update-desktop-database /var/lib/snapd/desktop/applications/ 2>/dev/null || true
fi

echo "User environment ready."
