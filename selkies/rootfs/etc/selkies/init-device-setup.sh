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
chown -R appbox:appbox /usr/share/selkies/www/ 2>/dev/null || true

# Ensure config directory has proper ownership
chown -R appbox:appbox /config 2>/dev/null || true

# Create temporary files with proper permissions
touch /tmp/selkies_js.log
chmod 666 /tmp/selkies_js.log
chown appbox:appbox /tmp/selkies_js.log

# Create defaults directory if it doesn't exist
mkdir -p /defaults
chown appbox:appbox /defaults

# Video device permissions setup (moved from init-video.sh)
echo "Setting up video device permissions..."

FILES=$(find /dev/dri /dev/dvb -type c -print 2>/dev/null || true)

for i in $FILES
do
    if [ -e "$i" ]; then
        VIDEO_GID=$(stat -c '%g' "${i}")
        VIDEO_UID=$(stat -c '%u' "${i}")
        # check if user matches device
        if id -u appbox | grep -qw "${VIDEO_UID}"; then
            echo "**** permissions for ${i} are good ****"
        else
            # check if group matches and that device has group rw
            if id -G appbox | grep -qw "${VIDEO_GID}" && [ $(stat -c '%A' "${i}" | cut -b 5,6) = "rw" ]; then
                echo "**** permissions for ${i} are good ****"
            # check if device needs to be added to video group
            elif ! id -G appbox | grep -qw "${VIDEO_GID}"; then
                # check if video group needs to be created
                VIDEO_NAME=$(getent group "${VIDEO_GID}" | awk -F: '{print $1}')
                if [ -z "${VIDEO_NAME}" ]; then
                    VIDEO_NAME="video$(head /dev/urandom | tr -dc 'a-z0-9' | head -c4)"
                    groupadd "${VIDEO_NAME}" 2>/dev/null || true
                    groupmod -g "${VIDEO_GID}" "${VIDEO_NAME}" 2>/dev/null || true
                    echo "**** creating video group ${VIDEO_NAME} with id ${VIDEO_GID} ****"
                fi
                echo "**** adding ${i} to video group ${VIDEO_NAME} with id ${VIDEO_GID} ****"
                usermod -a -G "${VIDEO_NAME}" appbox 2>/dev/null || true
            fi
            # check if device has group rw
            if [ $(stat -c '%A' "${i}" | cut -b 5,6) != "rw" ]; then
                echo -e "**** The device ${i} does not have group read/write permissions, attempting to fix inside the container. If it doesn't work, you can run the following on your docker host: ****\nsudo chmod g+rw ${i}\n"
                chmod g+rw "${i}" 2>/dev/null || true
            fi
        fi
    fi
done

echo "Video device permissions setup completed." 