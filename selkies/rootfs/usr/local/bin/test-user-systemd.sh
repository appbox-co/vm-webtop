#!/bin/bash
# Test if user systemd is working and provide alternatives
# This script should be run as root (with sudo)

USER_NAME="appbox"
XDG_RUNTIME_DIR="/run/user/$(id -u $USER_NAME)"

echo "Testing user systemd for $USER_NAME..."

# Check if running as root, if not, try to create runtime dir anyway
if [[ $EUID -eq 0 ]]; then
    # Ensure runtime directory exists (needs root)
    mkdir -p "$XDG_RUNTIME_DIR"
    chown "$USER_NAME:$USER_NAME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
else
    echo "Note: Run with sudo for full functionality"
    if [[ ! -d "$XDG_RUNTIME_DIR" ]]; then
        echo "Runtime directory $XDG_RUNTIME_DIR doesn't exist"
        echo "Run: sudo $0"
        exit 1
    fi
fi

echo "Runtime directory: $XDG_RUNTIME_DIR"

# Test user systemd
if sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user status >/dev/null 2>&1; then
    echo "✓ User systemd is working correctly!"
    echo ""
    echo "You can use user services:"
    echo "  sudo -u $USER_NAME systemctl --user start selkies-desktop"
    echo "  sudo -u $USER_NAME systemctl --user status selkies"
    echo ""
    echo "User services available:"
    sudo -u "$USER_NAME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" systemctl --user list-unit-files | grep selkies || echo "  (No user services found - may need to be enabled)"
else
    echo "✗ User systemd is not working"
    echo "This is normal for headless servers and VPS environments."
    echo ""
    echo "RECOMMENDED: Use system services instead"
    echo "System services work perfectly in all environments:"
    echo ""
    echo "  systemctl start selkies-desktop    # Start all services"
    echo "  systemctl status selkies-desktop   # Check desktop service"  
    echo "  systemctl status selkies           # Check main service"
    echo "  systemctl status selkies-nginx     # Check web server"
    echo "  systemctl status xvfb              # Check display server"
    echo ""
    echo "System services available:"
    systemctl list-unit-files | grep selkies
fi

echo ""
echo "For troubleshooting, check:"
echo "  journalctl -u selkies-desktop -f    # Follow desktop service logs"
echo "  journalctl -u selkies -f           # Follow main service logs"
