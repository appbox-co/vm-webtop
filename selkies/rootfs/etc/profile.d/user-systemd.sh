#!/bin/bash

# User systemd environment setup
# This ensures users have proper access to systemd --user

# Only set up for the appbox user
if [[ "$USER" == "appbox" ]] || [[ "$LOGNAME" == "appbox" ]]; then
    # Set XDG_RUNTIME_DIR if not already set
    if [[ -z "$XDG_RUNTIME_DIR" ]]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    fi
    
    # Ensure the directory exists
    if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
        mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
        chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
    fi
    
    # Set DBUS session bus address if not set and socket exists
    if [[ -z "$DBUS_SESSION_BUS_ADDRESS" ]] && [[ -S "${XDG_RUNTIME_DIR}/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
    fi
    
    # Set up systemd user environment
    export SYSTEMD_USER_RUNTIME_DIR="$XDG_RUNTIME_DIR/systemd"
    
    # Add Flatpak directories to XDG_DATA_DIRS for desktop integration
    if [[ -d "/var/lib/flatpak/exports/share" ]] || [[ -d "$HOME/.local/share/flatpak/exports/share" ]]; then
        FLATPAK_DIRS=""
        [[ -d "/var/lib/flatpak/exports/share" ]] && FLATPAK_DIRS="/var/lib/flatpak/exports/share"
        [[ -d "$HOME/.local/share/flatpak/exports/share" ]] && FLATPAK_DIRS="$FLATPAK_DIRS:$HOME/.local/share/flatpak/exports/share"
        
        if [[ -n "$FLATPAK_DIRS" ]]; then
            export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:$FLATPAK_DIRS"
        fi
    fi
fi
