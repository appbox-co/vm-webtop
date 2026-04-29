#!/bin/bash

# User systemd environment setup for desktop sessions
# This ensures systemctl --user works in desktop terminals

# Only set up if we're in an X session and variables aren't already set
if [[ -n "$DISPLAY" ]] && [[ -z "$DBUS_SESSION_BUS_ADDRESS" ]]; then
    # Set XDG_RUNTIME_DIR
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    
    # Set DBUS session bus address
    if [[ -S "${XDG_RUNTIME_DIR}/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
    fi
    
    # Additional systemd-related environment variables
    export SYSTEMD_USER_RUNTIME_DIR="$XDG_RUNTIME_DIR/systemd"
fi
