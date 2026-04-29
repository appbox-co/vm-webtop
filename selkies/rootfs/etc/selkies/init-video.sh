#!/bin/bash

# Video device permissions check script
# This script runs as user appbox and only checks permissions
# Actual permission setting is done by selkies-setup.service as root

echo "Checking video device permissions..."

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
            else
                echo "**** Warning: User appbox may not have proper access to ${i} ****"
                echo "**** This should have been handled by selkies-setup.service ****"
            fi
        fi
    fi
done

echo "Video device permissions check completed." 