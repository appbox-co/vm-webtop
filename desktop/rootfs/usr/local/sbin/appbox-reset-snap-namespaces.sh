#!/bin/bash
set -euo pipefail

# Snap mount namespaces can retain a stale private /tmp after image templating or
# tmpfs resets. Rebuild them before users launch snap apps.
mkdir -p /tmp/snap-private-tmp
chown root:root /tmp/snap-private-tmp
chmod 1777 /tmp/snap-private-tmp

for snap_name in chromium snap-store; do
    if ! snap list "$snap_name" >/dev/null 2>&1; then
        continue
    fi

    private_tmp="/tmp/snap-private-tmp/snap.${snap_name}"
    if [[ -d "$private_tmp" ]]; then
        chown root:root "$private_tmp" 2>/dev/null || true
        chmod 700 "$private_tmp" 2>/dev/null || true
    fi

    /usr/lib/snapd/snap-discard-ns "$snap_name" >/dev/null 2>&1 || true
done
