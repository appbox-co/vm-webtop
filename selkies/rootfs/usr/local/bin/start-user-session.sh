#!/bin/bash
# Start user systemd session for Selkies desktop environment
# This script should be called from within the desktop session

set -euo pipefail

USER_NAME="$(whoami)"
USER_ID="$(id -u)"

echo "Starting user systemd session for $USER_NAME (UID: $USER_ID)..."

# Set up XDG_RUNTIME_DIR
export XDG_RUNTIME_DIR="/run/user/$USER_ID"

# Ensure runtime directory exists (this should be created by systemd-logind or pam_systemd)
if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
    echo "Creating runtime directory: $XDG_RUNTIME_DIR"
    sudo mkdir -p "$XDG_RUNTIME_DIR"
    sudo chown "$USER_NAME:$USER_NAME" "$XDG_RUNTIME_DIR"
    sudo chmod 700 "$XDG_RUNTIME_DIR"
fi

# Set up D-Bus session bus if not already running
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    echo "Starting D-Bus session bus..."
    eval $(dbus-launch --sh-syntax --exit-with-session)
    export DBUS_SESSION_BUS_ADDRESS
    echo "D-Bus session bus started: $DBUS_SESSION_BUS_ADDRESS"
fi

# Start systemd --user if not already running
if ! systemctl --user status >/dev/null 2>&1; then
    echo "Starting systemd --user daemon..."
    systemd --user &
    SYSTEMD_PID=$!
    
    # Wait for systemd to be ready
    for i in {1..30}; do
        if systemctl --user status >/dev/null 2>&1; then
            echo "✓ systemd --user is ready"
            break
        fi
        echo "Waiting for systemd --user to start... ($i/30)"
        sleep 1
    done
    
    if ! systemctl --user status >/dev/null 2>&1; then
        echo "⚠ systemd --user failed to start properly"
        return 1
    fi
else
    echo "✓ systemd --user is already running"
fi

# Reload and start user services
echo "Setting up user services..."
systemctl --user daemon-reload

# Start user services if they exist and are enabled
USER_SERVICES=("selkies-pulseaudio" "selkies" "selkies-desktop")
for service in "${USER_SERVICES[@]}"; do
    if systemctl --user list-unit-files "${service}.service" >/dev/null 2>&1; then
        echo "Starting user service: ${service}.service"
        systemctl --user start "${service}.service" || echo "Failed to start ${service}.service"
    fi
done

echo "✓ User systemd session setup completed"

# Export environment for the rest of the session
echo "export XDG_RUNTIME_DIR=\"$XDG_RUNTIME_DIR\"" >> ~/.bashrc
echo "export DBUS_SESSION_BUS_ADDRESS=\"$DBUS_SESSION_BUS_ADDRESS\"" >> ~/.bashrc
