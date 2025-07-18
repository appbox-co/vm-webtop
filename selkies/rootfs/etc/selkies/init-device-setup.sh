#!/bin/bash

# Device and permission setup script
# This script runs as root to set up device nodes and fix permissions

# Create input device directory
mkdir -pm1777 /dev/input

# Create joystick and event device nodes
mknod /dev/input/js0 c 13 0 2>/dev/null || true
mknod /dev/input/js1 c 13 1 2>/dev/null || true
mknod /dev/input/js2 c 13 2 2>/dev/null || true
mknod /dev/input/js3 c 13 3 2>/dev/null || true
mknod /dev/input/event1000 c 13 1064 2>/dev/null || true
mknod /dev/input/event1001 c 13 1065 2>/dev/null || true
mknod /dev/input/event1002 c 13 1066 2>/dev/null || true
mknod /dev/input/event1003 c 13 1067 2>/dev/null || true

# Set permissions on device nodes
chmod 777 /dev/input/js* /dev/input/event* 2>/dev/null || true

# Fix permissions on selkies web directory
chown -R abc:abc /usr/share/selkies/www/ 2>/dev/null || true

# Ensure config directory has proper ownership
chown -R abc:abc /config 2>/dev/null || true

# Create temporary files with proper permissions
touch /tmp/selkies_js.log
chmod 666 /tmp/selkies_js.log
chown abc:abc /tmp/selkies_js.log

# Create defaults directory if it doesn't exist
mkdir -p /defaults
chown abc:abc /defaults 